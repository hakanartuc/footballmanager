import '../competition/fixtures.dart';
import '../competition/season_calendar_builder.dart';
import '../core/game_date.dart';
import '../core/ids.dart';
import '../core/rng.dart';
import '../data/country_data.dart';
import '../model/club.dart';
import '../model/country.dart';
import '../model/enums.dart';
import '../model/fixture.dart';
import '../model/manager.dart';
import '../model/player.dart';
import '../model/world.dart';
import 'club_generator.dart';
import 'player_generator.dart';

/// How many countries the world holds, taken in `countries.json` order.
enum WorldSize {
  small(4),
  medium(8),
  large(16);

  const WorldSize(this.countryCount);

  final int countryCount;
}

/// Senior squad template: 24 players by main position. The season
/// rollover's youth intake draws positions from the same quota.
const Map<Position, int> squadQuota = {
  Position.gk: 3,
  Position.dc: 4,
  Position.dl: 2,
  Position.dr: 2,
  Position.dm: 2,
  Position.mc: 4,
  Position.ml: 1,
  Position.mr: 1,
  Position.amc: 2,
  Position.st: 3,
};

/// Builds a fresh world of [size] countries from [seed] with the first
/// season's fixtures scheduled, an AI manager at every club and
/// `userManagerId` left at 0: `createNewGame` adds the user manager.
///
/// [startDate] is expected to be `seasonStart − 14` of the calendar for
/// `startDate.seasonYear`. Every random stream is a named fork of
/// `SeededRng(seed).fork('world')` (`country:<code>`, `players:<clubId>`,
/// `managers:<clubId>`, `fixtures:<leagueId>`), so adding countries does
/// not change the ones already there.
World generateWorld({
  required int seed,
  required WorldSize size,
  required GameDate startDate,
}) {
  final rng = SeededRng(seed).fork('world');
  final ids = IdAllocator();
  final seasonYear = startDate.seasonYear;
  final calendar = buildSeasonCalendar(seasonYear);
  final data = CountryData.load();

  final countries = <CountryId, Country>{};
  final leagues = <LeagueId, League>{};
  final clubs = <ClubId, Club>{};
  final players = <PlayerId, Player>{};
  final managers = <ManagerId, Manager>{};
  final fixtures = <FixtureId, Fixture>{};
  final poolOf = <CountryId, NamePool>{};

  for (final t in data.countries.take(size.countryCount)) {
    final country = Country(
      id: ids.next('country'),
      code: t.code,
      name: t.name,
      continent: t.continent,
      namePool: t.namePool,
      tiers: [],
      climate: t.climate,
      southernHemisphere: t.southernHemisphere,
    );
    countries[country.id] = country;
    poolOf[country.id] = data.pools[t.namePool]!;
    for (var i = 0; i < t.tiers.length; i++) {
      final tier = t.tiers[i];
      final league = League(
        id: ids.next('league'),
        countryId: country.id,
        tier: i + 1,
        name: '${t.code}_${tier.nameKey}',
        clubIds: [],
        promotedCount: tier.promoted,
        relegatedCount: tier.relegated,
        reputation: (t.reputation - 15 * i).clamp(1, 100),
      );
      leagues[league.id] = league;
      country.tiers.add(league.id);
    }

    final clubGen = ClubGenerator(
      poolOf[country.id]!,
      rng.fork('country:${t.code}'),
      ids,
    );
    final usedNames = <String>{};
    for (var i = 0; i < t.tiers.length; i++) {
      final league = leagues[country.tiers[i]]!;
      final n = t.tiers[i].clubs;
      for (var rank = 0; rank < n; rank++) {
        final club = clubGen.generate(
          countryId: country.id,
          leagueId: league.id,
          tier: i + 1,
          countryReputation: t.reputation,
          indexInLeague: rank,
          leagueSize: n,
          usedNames: usedNames,
        );
        clubs[club.id] = club;
        league.clubIds.add(club.id);
      }
    }
  }

  final countryIds = countries.keys.toList();
  for (final club in clubs.values) {
    final clubRng = rng.fork('players:${club.id}');
    final gen = PlayerGenerator(poolOf[club.countryId]!, clubRng, ids);
    for (final p in _buildSquad(gen, clubRng, club, countryIds, startDate)) {
      players[p.id] = p;
    }
  }

  for (final club in clubs.values) {
    final m = _aiManager(
      poolOf[club.countryId]!,
      rng.fork('managers:${club.id}'),
      ids,
      club,
      startDate,
    );
    managers[m.id] = m;
    club.managerId = m.id;
  }

  for (final league in leagues.values) {
    final scheduled = scheduleLeagueFixtures(
      league: league,
      calendar: calendar,
      seasonYear: seasonYear,
      ids: ids,
      rng: rng.fork('fixtures:${league.id}'),
    );
    for (final f in scheduled) {
      fixtures[f.id] = f;
    }
  }

  return World(
    schemaVersion: currentSchemaVersion,
    seed: seed,
    date: startDate,
    seasonYear: seasonYear,
    countries: countries,
    leagues: leagues,
    clubs: clubs,
    players: players,
    managers: managers,
    fixtures: fixtures,
    calendar: calendar,
    userManagerId: 0,
    ids: ids,
  );
}

/// [club]'s senior squad (22..26 players, statuses ranked by CA) followed
/// by 6 youth players. Nationality is drawn from a sub-fork so that the
/// player streams do not depend on how many countries the world has.
List<Player> _buildSquad(
  PlayerGenerator gen,
  SeededRng rng,
  Club club,
  List<CountryId> countryIds,
  GameDate today,
) {
  final natRng = rng.fork('nationality');
  final others = [
    for (final id in countryIds)
      if (id != club.countryId) id,
  ];
  CountryId nationality() => others.isEmpty || natRng.nextBool(0.85)
      ? club.countryId
      : natRng.pick(others);

  final positions = [
    for (final MapEntry(key: p, value: n) in squadQuota.entries)
      for (var i = 0; i < n; i++) p,
  ];
  final outfield = [
    for (final p in squadQuota.keys)
      if (p != Position.gk) p,
  ];
  final squadSize = 22 + rng.nextInt(5);
  while (positions.length < squadSize) {
    positions.add(rng.pick(outfield));
  }
  // The goalkeepers come first in the quota, so trimming the tail only
  // ever drops outfield players.
  positions.length = squadSize;

  final squad = [
    for (final p in positions)
      gen.generateForTier(
        clubReputation: club.reputation,
        nationality: nationality(),
        position: p,
        today: today,
        clubId: club.id,
      ),
  ];
  final byCa = List.of(squad)
    ..sort((a, b) {
      final c = b.ca.compareTo(a.ca);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  for (var i = 0; i < byCa.length; i++) {
    byCa[i].contract!.status = switch (i) {
      < 4 => PlayerStatus.keyPlayer,
      < 14 => PlayerStatus.firstTeam,
      < 20 => PlayerStatus.rotation,
      _ => PlayerStatus.backup,
    };
  }

  final quotaPositions = squadQuota.keys.toList();
  final quotaWeights = [for (final n in squadQuota.values) n.toDouble()];
  final youthBase = (club.reputation * 0.6 + 20).round();
  final youth = [
    for (var i = 0; i < 6; i++)
      gen.generate(
        nationality: nationality(),
        position: quotaPositions[rng.weightedIndex(quotaWeights)],
        targetCa: (youthBase + rng.nextInt(21) - 10).clamp(20, 120),
        age: 15 + rng.nextInt(3),
        today: today,
        clubId: club.id,
        youth: true,
      ),
  ];
  return [...squad, ...youth];
}

/// An AI manager aged 35..60 with reputation within ±10 of [club]'s.
Manager _aiManager(
  NamePool pool,
  SeededRng rng,
  IdAllocator ids,
  Club club,
  GameDate today,
) {
  final age = 35 + rng.nextInt(26);
  return Manager(
    id: ids.next('manager'),
    firstName: rng.pick(pool.firstNames),
    lastName: rng.pick(pool.lastNames),
    nationality: club.countryId,
    birth: GameDate.ymd(today.year - age, today.month, today.day),
    reputation: (club.reputation + rng.nextInt(21) - 10).clamp(1, 100),
    clubId: club.id,
    preferredFormation: Formation.f442,
  );
}
