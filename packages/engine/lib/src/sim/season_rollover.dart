import 'dart:math' as math;

import '../competition/fixtures.dart';
import '../competition/promotion.dart';
import '../competition/season_calendar_builder.dart';
import '../competition/standings.dart';
import '../core/game_date.dart';
import '../core/ids.dart';
import '../core/rng.dart';
import '../data/country_data.dart';
import '../gen/player_generator.dart';
import '../gen/world_generator.dart';
import '../model/enums.dart';
import '../model/events.dart';
import '../model/player.dart';
import '../model/world.dart';

/// Senior squad bounds after the rollover: fillers are generated up to the
/// floor, the lowest-rated seniors are released above the cap.
const int seniorSquadFloor = 18;
const int seniorSquadCap = 28;

/// Players aged this or more on the season's last day retire.
const int retirementAge = 35;

/// Ends season `w.seasonYear` on `w.date` (the calendar's `seasonEnd`) and
/// sets up the next one. The day loop calls it from `endOfDay`, with
/// `SeededRng(seed).fork('rollover:<seasonYear>')` as [rng].
///
/// In order:
/// 1. archive: final tables, `SeasonArchive` in `history`, `LeagueChampion`;
/// 2. promotion/relegation per country (`Promoted`, `Relegated`);
/// 3. career lines for players who appeared and for employed managers;
///    every player's `season` is reset;
/// 4. retirement of every player aged [retirementAge] or more
///    (`PlayerRetired`);
/// 5. youth intake of `3 + rng.nextInt(4)` sixteen-year-olds per club
///    (`YouthIntake`), then youth aged 18 or more become seniors;
/// 6. squad balance: fillers aged 19–24 until every senior squad has
///    [seniorSquadFloor] players; above [seniorSquadCap] the lowest-CA
///    seniors are released to free agency (`contract = null`);
/// 7. contracts: every contract ending on or before today is extended to
///    June 30 two years on. This AI auto-renew applies to the user's club
///    too in Faz 0 (no negotiation yet);
/// 8. the next season's calendar and fixtures (old fixtures are kept);
/// 9. lineups cleared, `SeasonEnded` then `NewSeasonStarted`.
///
/// `w.date` is left alone: the day loop idles through the summer.
List<GameEvent> rolloverSeason(World w, SeededRng rng) {
  final events = <GameEvent>[];
  final oldYear = w.seasonYear;
  final data = CountryData.load();
  NamePool poolOf(CountryId c) => data.pools[w.countries[c]!.namePool]!;

  final tables = _archiveSeason(w, events);
  _promoteAndRelegate(w, tables, events);
  _recordCareers(w);
  _retirePlayers(w, events);
  _youthIntake(w, rng, poolOf, events);
  _balanceSquads(w, rng, poolOf);
  _renewContracts(w);
  final nextYear = _scheduleNextSeason(w, rng);
  _startNewSeason(w, events, oldYear: oldYear, nextYear: nextYear);
  return events;
}

/// Step 1. Every final table is computed before any league changes.
Map<LeagueId, List<TableRow>> _archiveSeason(World w, List<GameEvent> events) {
  final tables = {
    for (final id in w.leagues.keys.toList()..sort())
      id: computeTable(w, id, w.seasonYear),
  };
  w.history.add(
    SeasonArchive(
      seasonYear: w.seasonYear,
      champions: {for (final e in tables.entries) e.key: e.value.first.clubId},
      finalOrder: {
        for (final e in tables.entries)
          e.key: [for (final r in e.value) r.clubId],
      },
    ),
  );
  for (final e in tables.entries) {
    events.add(
      LeagueChampion(
        date: w.date,
        leagueId: e.key,
        clubId: e.value.first.clubId,
      ),
    );
  }
  return tables;
}

/// Step 2.
void _promoteAndRelegate(
  World w,
  Map<LeagueId, List<TableRow>> tables,
  List<GameEvent> events,
) {
  for (final c in w.countries.keys.toList()..sort()) {
    for (final m in applyPromotionRelegation(w, c, tables)) {
      final down = w.leagues[m.to]!.tier > w.leagues[m.from]!.tier;
      events.add(
        down
            ? Relegated(
                date: w.date,
                clubId: m.clubId,
                fromLeagueId: m.from,
                toLeagueId: m.to,
              )
            : Promoted(
                date: w.date,
                clubId: m.clubId,
                fromLeagueId: m.from,
                toLeagueId: m.to,
              ),
      );
    }
  }
}

/// Step 3.
void _recordCareers(World w) {
  for (final id in w.players.keys.toList()..sort()) {
    final p = w.players[id]!;
    final clubId = p.contract?.clubId;
    if (clubId != null && p.season.apps > 0) {
      p.career.add(
        CareerLine(seasonYear: w.seasonYear, clubId: clubId, stats: p.season),
      );
    }
    p.season = SeasonStats();
  }
  for (final id in w.managers.keys.toList()..sort()) {
    final m = w.managers[id]!;
    final clubId = m.clubId;
    if (clubId != null) {
      m.career.add(CareerLine(seasonYear: w.seasonYear, clubId: clubId));
    }
  }
}

/// Step 4.
void _retirePlayers(World w, List<GameEvent> events) {
  for (final id in w.players.keys.toList()..sort()) {
    final p = w.players[id]!;
    if (p.ageAt(w.date) < retirementAge) continue;
    w.players.remove(id);
    events.add(
      PlayerRetired(date: w.date, playerId: id, clubId: p.contract?.clubId),
    );
  }
}

/// Step 5. Each club draws from `rollover.fork('youth:<club>:<year>')`;
/// positions are picked uniformly from the 24 [squadQuota] slots.
void _youthIntake(
  World w,
  SeededRng rng,
  NamePool Function(CountryId) poolOf,
  List<GameEvent> events,
) {
  final slots = [
    for (final MapEntry(key: p, value: n) in squadQuota.entries)
      for (var i = 0; i < n; i++) p,
  ];
  for (final id in w.clubs.keys.toList()..sort()) {
    final club = w.clubs[id]!;
    final fork = rng.fork('youth:${club.id}:${w.seasonYear}');
    final gen = PlayerGenerator(poolOf(club.countryId), fork, w.ids);
    final base = (club.reputation * 0.6 + 20).round();
    final count = 3 + fork.nextInt(4);
    final intake = <PlayerId>[];
    for (var i = 0; i < count; i++) {
      final p = gen.generate(
        nationality: club.countryId,
        position: fork.pick(slots),
        targetCa: (base + fork.nextInt(21) - 10).clamp(20, 120),
        age: 16,
        today: w.date,
        clubId: club.id,
        youth: true,
      );
      w.players[p.id] = p;
      intake.add(p.id);
    }
    events.add(YouthIntake(date: w.date, clubId: club.id, playerIds: intake));
  }
  for (final id in w.players.keys.toList()..sort()) {
    final p = w.players[id]!;
    if (p.isYouth && p.ageAt(w.date) >= 18) {
      p.isYouth = false;
      p.contract!.status = PlayerStatus.backup;
    }
  }
}

/// Step 6. Fillers come from `rollover.fork('fillers:<club>:<year>')`, each
/// at the quota position with the fewest seniors (goalkeepers first until
/// there are two). Excess seniors are released lowest CA first (ties by
/// id).
void _balanceSquads(
  World w,
  SeededRng rng,
  NamePool Function(CountryId) poolOf,
) {
  w.rebuildIndexes();
  final outfield = [
    for (final p in squadQuota.keys)
      if (p != Position.gk) p,
  ];
  for (final id in w.clubs.keys.toList()..sort()) {
    final club = w.clubs[id]!;
    final squad = w.squadOf(club.id);
    if (squad.length > seniorSquadCap) {
      final byCa = [for (final pid in squad) w.players[pid]!]
        ..sort((a, b) {
          final c = a.ca.compareTo(b.ca);
          return c != 0 ? c : a.id.compareTo(b.id);
        });
      for (final p in byCa.take(squad.length - seniorSquadCap)) {
        p.contract = null;
      }
      continue;
    }
    if (squad.length >= seniorSquadFloor) continue;
    final counts = {for (final p in squadQuota.keys) p: 0};
    for (final pid in squad) {
      final pos = w.players[pid]!.mainPosition;
      if (counts.containsKey(pos)) counts[pos] = counts[pos]! + 1;
    }
    final fork = rng.fork('fillers:${club.id}:${w.seasonYear}');
    final gen = PlayerGenerator(poolOf(club.countryId), fork, w.ids);
    for (var n = squad.length; n < seniorSquadFloor; n++) {
      final position = counts[Position.gk]! < 2
          ? Position.gk
          : outfield.reduce((a, b) => counts[b]! < counts[a]! ? b : a);
      final p = gen.generateForTier(
        clubReputation: math.max(5, club.reputation - 12),
        nationality: club.countryId,
        position: position,
        age: 19 + fork.nextInt(6),
        today: w.date,
        clubId: club.id,
      );
      p.contract!.status = PlayerStatus.backup;
      w.players[p.id] = p;
      counts[position] = counts[position]! + 1;
    }
  }
}

/// Step 7. See [rolloverSeason] for the auto-renew note.
void _renewContracts(World w) {
  for (final id in w.players.keys.toList()..sort()) {
    final contract = w.players[id]!.contract;
    if (contract != null && !contract.end.isAfter(w.date)) {
      contract.end = GameDate.ymd(w.date.year + 2, 6, 30);
    }
  }
}

/// Step 8. Returns the new season year.
int _scheduleNextSeason(World w, SeededRng rng) {
  final nextYear = w.seasonYear + 1;
  w.calendar = buildSeasonCalendar(nextYear);
  for (final id in w.leagues.keys.toList()..sort()) {
    final scheduled = scheduleLeagueFixtures(
      league: w.leagues[id]!,
      calendar: w.calendar,
      seasonYear: nextYear,
      ids: w.ids,
      rng: rng.fork('fixtures:$id:$nextYear'),
    );
    for (final f in scheduled) {
      w.fixtures[f.id] = f;
    }
  }
  w.seasonYear = nextYear;
  return nextYear;
}

/// Step 9.
void _startNewSeason(
  World w,
  List<GameEvent> events, {
  required int oldYear,
  required int nextYear,
}) {
  for (final club in w.clubs.values) {
    club.lineup = null;
  }
  w.rebuildIndexes();
  events
    ..add(SeasonEnded(date: w.date, seasonYear: oldYear))
    ..add(NewSeasonStarted(date: w.date, seasonYear: nextYear));
}
