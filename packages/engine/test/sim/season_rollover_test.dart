import 'package:engine/engine.dart';
import 'package:test/test.dart';

World _world({ClubId? startClubId}) => createNewGame(
  NewGameSpec(
    seed: 1,
    size: WorldSize.small,
    managerFirstName: 'Test',
    managerLastName: 'Manager',
    managerCountryCode: 'TR',
    startClubId: startClubId,
  ),
);

/// What the world looked like on `seasonEnd`, just before the rollover.
class _Snapshot {
  _Snapshot(World w)
    : date = w.date,
      seasonYear = w.seasonYear,
      tables = {
        for (final id in w.leagues.keys.toList()..sort())
          id: computeTable(w, id, w.seasonYear),
      },
      clubIds = {for (final l in w.leagues.values) l.id: List.of(l.clubIds)},
      youthOf = {for (final c in w.clubs.keys) c: List.of(w.youthOf(c))},
      seniorsOf = {for (final c in w.clubs.keys) c: List.of(w.squadOf(c))},
      ages = {for (final p in w.players.values) p.id: p.ageAt(w.date)},
      apps = {for (final p in w.players.values) p.id: p.season.apps},
      fixtureCount = w.fixtures.length;

  final GameDate date;
  final int seasonYear;
  final Map<LeagueId, List<TableRow>> tables;
  final Map<LeagueId, List<ClubId>> clubIds;
  final Map<ClubId, List<PlayerId>> youthOf;
  final Map<ClubId, List<PlayerId>> seniorsOf;
  final Map<PlayerId, int> ages;
  final Map<PlayerId, int> apps;
  final int fixtureCount;
}

/// One full season advanced with the real rollover hook; records the
/// pre-rollover [_Snapshot], the hook's returned events and the date the
/// hook left the world on.
class _SeasonRun {
  _SeasonRun(this.w) {
    final runner = DayRunner(
      const PoissonMatchSimulator(),
      rollover: (w, rng) {
        before = _Snapshot(w);
        events = rolloverSeason(w, rng);
        dateAfterHook = w.date;
        return events;
      },
    );
    final seasonEnd = w.calendar.seasonEnd;
    while (!w.date.isAfter(seasonEnd)) {
      runner.advanceDay(w, const []);
    }
    this.runner = runner;
  }

  final World w;
  late final DayRunner runner;
  late _Snapshot before;
  late List<GameEvent> events;
  late GameDate dateAfterHook;
}

void main() {
  late _SeasonRun run;
  late World w;
  late _Snapshot before;

  setUpAll(() {
    run = _SeasonRun(_world());
    w = run.w;
    before = run.before;
  });

  group('rolloverSeason', () {
    test('archives the season with the table leaders as champions', () {
      expect(w.history, hasLength(1));
      final a = w.history.single;
      expect(a.seasonYear, before.seasonYear);
      for (final MapEntry(key: id, value: table) in before.tables.entries) {
        expect(a.champions[id], table.first.clubId);
        expect(a.finalOrder[id], table.map((r) => r.clubId).toList());
        final champion = run.events.whereType<LeagueChampion>().singleWhere(
          (e) => e.leagueId == id,
        );
        expect(champion.clubId, table.first.clubId);
        expect(champion.date, before.date);
      }
    });

    test('promotes and relegates exactly the table ends', () {
      for (final country in w.countries.values) {
        final tiers = country.tiers;
        for (var k = 0; k < tiers.length; k++) {
          final upper = w.leagues[tiers[k]]!;
          final expected = {...before.clubIds[upper.id]!};
          if (k + 1 < tiers.length) {
            final lower = w.leagues[tiers[k + 1]]!;
            final down = before.tables[upper.id]!.reversed
                .take(upper.relegatedCount)
                .map((r) => r.clubId);
            final up = before.tables[lower.id]!
                .take(lower.promotedCount)
                .map((r) => r.clubId);
            expect(down.length, up.length);
            expected
              ..removeAll(down)
              ..addAll(up);
            for (final c in down) {
              expect(w.clubs[c]!.leagueId, lower.id);
              final e = run.events.whereType<Relegated>().singleWhere(
                (e) => e.clubId == c,
              );
              expect(e.fromLeagueId, upper.id);
              expect(e.toLeagueId, lower.id);
            }
            for (final c in up) {
              expect(w.clubs[c]!.leagueId, upper.id);
              final e = run.events.whereType<Promoted>().singleWhere(
                (e) => e.clubId == c,
              );
              expect(e.fromLeagueId, lower.id);
              expect(e.toLeagueId, upper.id);
            }
          }
          if (k > 0) {
            final above = w.leagues[tiers[k - 1]]!;
            expected
              ..removeAll(
                before.tables[upper.id]!
                    .take(upper.promotedCount)
                    .map((r) => r.clubId),
              )
              ..addAll(
                before.tables[above.id]!.reversed
                    .take(above.relegatedCount)
                    .map((r) => r.clubId),
              );
          }
          expect(upper.clubIds.toSet(), expected);
          expect(upper.clubIds, List.of(upper.clubIds)..sort());
          expect(upper.clubIds.length, before.clubIds[upper.id]!.length);
        }
      }
      final moves = run.events.where((e) => e is Promoted || e is Relegated);
      expect(moves, isNotEmpty);
    });

    test('records career lines for players who played and resets stats', () {
      var lines = 0;
      for (final p in w.players.values) {
        expect(p.season.apps, 0);
        expect(p.season.goals, 0);
        final apps = before.apps[p.id];
        if (apps == null) continue; // youth intake / fillers
        if (apps > 0) {
          final line = p.career.single;
          expect(line.seasonYear, before.seasonYear);
          expect(line.clubId, p.contract!.clubId);
          expect(line.stats.apps, apps);
          lines++;
        } else {
          expect(p.career, isEmpty);
        }
      }
      final survivors = before.apps.entries.where(
        (e) => e.value > 0 && w.players.containsKey(e.key),
      );
      expect(lines, survivors.length);
      expect(lines, greaterThan(w.clubs.length * 10));
      for (final m in w.managers.values) {
        if (m.clubId == null) {
          expect(m.career, isEmpty);
        } else {
          expect(m.career.single.seasonYear, before.seasonYear);
          expect(m.career.single.clubId, m.clubId);
        }
      }
    });

    test('retires every player aged 35 or more', () {
      final retired = before.ages.entries.where((e) => e.value >= 35);
      expect(retired, isNotEmpty);
      final events = run.events.whereType<PlayerRetired>().toList();
      expect(events.map((e) => e.playerId), retired.map((e) => e.key));
      for (final e in events) {
        expect(w.players.containsKey(e.playerId), isFalse);
        expect(e.clubId, isNotNull);
        expect(e.date, before.date);
      }
      for (final p in w.players.values) {
        expect(p.ageAt(before.date), lessThan(35));
      }
    });

    test('youth intake adds 3..6 sixteen-year-olds and promotes the 18s', () {
      for (final club in w.clubs.values) {
        final intake = run.events.whereType<YouthIntake>().singleWhere(
          (e) => e.clubId == club.id,
        );
        expect(intake.playerIds.length, inInclusiveRange(3, 6));
        for (final id in intake.playerIds) {
          final p = w.players[id]!;
          expect(p.isYouth, isTrue);
          expect(p.ageAt(before.date), 16);
          expect(p.contract!.clubId, club.id);
          expect(p.contract!.status, PlayerStatus.youth);
          expect(p.nationality, club.countryId);
          expect(p.ca, inInclusiveRange(10, 130));
        }
        // Promotion mirrors the rule: lowest id first, only below 28.
        var seniors = before.seniorsOf[club.id]!
            .where((id) => before.ages[id]! < 35)
            .length;
        final promoted = <PlayerId>[];
        for (final id in before.youthOf[club.id]!) {
          if (before.ages[id]! < 18 || seniors >= 28) continue;
          promoted.add(id);
          seniors++;
        }
        for (final id in before.youthOf[club.id]!) {
          final p = w.players[id]!;
          if (promoted.contains(id)) {
            expect(p.isYouth, isFalse);
            expect(p.contract!.status, PlayerStatus.backup);
            expect(w.squadOf(club.id), contains(id));
          } else {
            expect(p.isYouth, isTrue);
            expect(p.contract!.status, PlayerStatus.youth);
          }
        }
        expect(
          w.youthOf(club.id).length,
          before.youthOf[club.id]!.length -
              promoted.length +
              intake.playerIds.length,
        );
      }
    });

    test('every senior squad is 18..28', () {
      for (final club in w.clubs.values) {
        expect(
          w.squadOf(club.id).length,
          inInclusiveRange(18, 28),
          reason: club.name,
        );
      }
    });

    test('schedules the next season and keeps the old fixtures', () {
      final next = before.seasonYear + 1;
      expect(w.seasonYear, next);
      expect(w.calendar.seasonYear, next);
      final added = w.fixtures.values.where((f) => f.seasonYear == next);
      expect(w.fixtures.length, before.fixtureCount + added.length);
      var expectedTotal = 0;
      for (final league in w.leagues.values) {
        final n = league.clubIds.length;
        final mine = added.where((f) => f.leagueId == league.id).toList();
        expect(mine, hasLength(n * (n - 1)));
        expectedTotal += n * (n - 1);
        final rounds = mine.map((f) => f.round).toSet();
        expect(rounds.length, n.isEven ? 2 * (n - 1) : 2 * n);
        final dates = leagueMatchdays(w.calendar, rounds.length);
        for (final f in mine) {
          expect(f.date, dates[f.round - 1]);
          expect(f.result, isNull);
          expect(league.clubIds, containsAll([f.homeId, f.awayId]));
        }
        final table = computeTable(w, league.id, next);
        expect(table, hasLength(n));
        expect(table.every((r) => r.played == 0), isTrue);
      }
      expect(added.length, expectedTotal);
      for (final club in w.clubs.values) {
        expect(club.lineup, isNull);
      }
    });

    test('leaves the date alone and ends with the two season events', () {
      expect(run.dateAfterHook, before.date);
      expect(w.date, before.date.addDays(1));
      final tail = run.events.sublist(run.events.length - 2);
      expect(tail[0], isA<SeasonEnded>());
      expect((tail[0] as SeasonEnded).seasonYear, before.seasonYear);
      expect(tail[1], isA<NewSeasonStarted>());
      expect((tail[1] as NewSeasonStarted).seasonYear, before.seasonYear + 1);
      expect(run.events.whereType<SeasonEnded>(), hasLength(1));
      expect(run.events.whereType<NewSeasonStarted>(), hasLength(1));
      final inbox = w.inbox.map((m) => m.event).toList();
      expect(inbox[inbox.length - 2], same(tail[0]));
      expect(inbox.last, same(tail[1]));
    });
  });

  group('rollover edge cases', () {
    late _SeasonRun run2;
    late World w2;
    late ClubId userClub;
    late ClubId agedClub;
    late Set<PlayerId> expiring;
    late PlayerId unexpired;
    late ClubId fullClub;
    late List<PlayerId> fullYouth;
    late GameDate nextStart;

    setUpAll(() {
      final tr = w.countries.values.firstWhere((c) => c.code == 'TR');
      userClub = before.tables[tr.tiers[0]]!.last.clubId;
      w2 = _world(startClubId: userClub);
      final seasonEnd = w2.calendar.seasonEnd;
      nextStart = buildSeasonCalendar(w2.seasonYear + 1).seasonStart;
      expect(nextStart.isAfter(seasonEnd), isTrue);

      agedClub = w2.clubs.values
          .firstWhere(
            (c) => c.countryId != tr.id && w2.squadOf(c.id).length >= 25,
          )
          .id;
      for (final id in w2.squadOf(agedClub).take(25)) {
        final p = w2.players[id]!;
        p.birth = GameDate.ymd(seasonEnd.year - 36, 1, 1);
      }

      final seniors = w2.squadOf(userClub);
      expiring = {seniors[0], seniors[1], seniors[2]};
      w2.players[seniors[0]]!.contract!.end = seasonEnd;
      w2.players[seniors[1]]!.contract!.end = GameDate.ymd(
        seasonEnd.year,
        6,
        30,
      );
      w2.players[seniors[2]]!.contract!.end = seasonEnd.addDays(-200);
      unexpired = seniors[3];
      w2.players[unexpired]!.contract!.end = nextStart;

      fullClub = w2.clubs.values
          .firstWhere(
            (c) =>
                c.countryId != tr.id &&
                c.id != agedClub &&
                w2.squadOf(c.id).length == 26,
          )
          .id;
      for (final id in w2.squadOf(fullClub)) {
        w2.players[id]!.birth = GameDate.ymd(seasonEnd.year - 25, 1, 1);
      }
      for (final id in w2.youthOf(fullClub)) {
        w2.players[id]!.birth = GameDate.ymd(seasonEnd.year - 18, 1, 1);
      }
      fullYouth = List.of(w2.youthOf(fullClub));
      // The third-lowest id misses promotion (the cap is reached after two)
      // and is 19, so it must be released; the 18-year-olds behind it stay.
      w2.players[fullYouth[2]]!.birth = GameDate.ymd(seasonEnd.year - 19, 1, 1);

      run2 = _SeasonRun(w2);
    });

    test('the table is the same as in the unemployed run', () {
      final tr = w2.countries.values.firstWhere((c) => c.code == 'TR');
      final top = tr.tiers[0];
      expect(
        run2.before.tables[top]!.map((r) => r.clubId),
        before.tables[top]!.map((r) => r.clubId),
      );
    });

    test('a relegated user manager still points at a valid club', () {
      final tr = w2.countries.values.firstWhere((c) => c.code == 'TR');
      final club = w2.userClub!;
      expect(club.id, userClub);
      expect(club.leagueId, tr.tiers[1]);
      expect(w2.leagues[tr.tiers[1]]!.clubIds, contains(userClub));
      expect(w2.leagues[tr.tiers[0]]!.clubIds, isNot(contains(userClub)));
      expect(club.managerId, w2.userManagerId);
      final relegated = run2.events.whereType<Relegated>().singleWhere(
        (e) => e.clubId == userClub,
      );
      expect(w2.inbox.map((m) => m.event), contains(relegated));
      expect(w2.fixturesOfClub(userClub, w2.seasonYear), isNotEmpty);
    });

    test('a squad of 36-year-olds is refilled to exactly 18 seniors', () {
      final retired = run2.events.whereType<PlayerRetired>().where(
        (e) => e.clubId == agedClub,
      );
      expect(retired.length, greaterThanOrEqualTo(25));
      final squad = w2.squadOf(agedClub);
      expect(squad, hasLength(18));
      final players = squad.map((id) => w2.players[id]!).toList();
      expect(
        players.where((p) => p.mainPosition == Position.gk).length,
        greaterThanOrEqualTo(2),
      );
      final fillers = players.where(
        (p) =>
            !run2.before.seniorsOf[agedClub]!.contains(p.id) &&
            !run2.before.youthOf[agedClub]!.contains(p.id),
      );
      expect(fillers, isNotEmpty);
      for (final p in fillers) {
        expect(p.ageAt(run2.before.date), inInclusiveRange(19, 24));
        expect(p.contract!.status, PlayerStatus.backup);
        expect(p.contract!.clubId, agedClub);
        expect(p.isYouth, isFalse);
      }
    });

    test('the refilled club plays its first fixture of the new season', () {
      final first = w2.fixtures[w2.fixturesOfClub(agedClub, w2.seasonYear)[0]]!;
      expect(first.result, isNull);
      while (!w2.date.isAfter(first.date)) {
        run2.runner.advanceDay(w2, const []);
      }
      expect(first.result, isNotNull);
      final lineup = w2.clubs[agedClub]!.lineup!;
      expect(validateLineup(w2, agedClub, lineup), isEmpty);
      for (final id in lineup.starters) {
        expect(w2.players[id]!.contract!.clubId, agedClub);
      }
    });

    test('youth promotion stops at 28 seniors, the rest stay youth', () {
      final squad = w2.squadOf(fullClub);
      expect(squad, hasLength(28));
      expect(fullYouth, hasLength(6));
      final intake = run2.events
          .whereType<YouthIntake>()
          .singleWhere((e) => e.clubId == fullClub)
          .playerIds;
      final kept = fullYouth.sublist(3);
      expect(w2.youthOf(fullClub), [...kept, ...intake]..sort());
      for (final id in fullYouth.take(2)) {
        expect(squad, contains(id));
        expect(w2.players[id]!.isYouth, isFalse);
        expect(w2.players[id]!.contract!.status, PlayerStatus.backup);
      }
      for (final id in kept) {
        expect(w2.players[id]!.isYouth, isTrue);
        expect(w2.players[id]!.contract!.status, PlayerStatus.youth);
        expect(w2.players[id]!.ageAt(run2.before.date), 18);
      }
    });

    test('unpromoted youth aged 19 are released and removed', () {
      final released = fullYouth[2];
      expect(w2.players.containsKey(released), isFalse);
      expect(w2.youthOf(fullClub), isNot(contains(released)));
      expect(w2.squadOf(fullClub), isNot(contains(released)));
      final event = run2.events.whereType<YouthReleased>().singleWhere(
        (e) => e.clubId == fullClub,
      );
      expect(event.playerIds, [released]);
      expect(event.date, run2.before.date);
      expect(run2.events.whereType<YouthReleased>(), isNotEmpty);
      expect(
        run2.events.sublist(run2.events.length - 2).map((e) => e.runtimeType),
        [SeasonEnded, NewSeasonStarted],
      );
    });

    test('expired contracts are extended by two years', () {
      final seasonEnd = run2.before.date;
      final renewed = GameDate.ymd(seasonEnd.year + 2, 6, 30);
      for (final id in expiring) {
        expect(w2.players[id]!.contract!.end, renewed, reason: '$id');
      }
      expect(w2.players[unexpired]!.contract!.end, nextStart);
      expect(w2.calendar.seasonStart, nextStart);
      for (final p in w2.players.values) {
        expect(p.contract!.end.isBefore(nextStart), isFalse, reason: '${p.id}');
      }
    });
  });

  group('applyPromotionRelegation', () {
    test('swaps the table ends and returns the moves', () {
      final fresh = _world();
      final tr = fresh.countries.values.firstWhere((c) => c.code == 'TR');
      final top = fresh.leagues[tr.tiers[0]]!;
      final second = fresh.leagues[tr.tiers[1]]!;
      final tables = {
        for (final id in tr.tiers)
          id: computeTable(fresh, id, fresh.seasonYear),
      };
      final order = tables[top.id]!.map((r) => r.clubId).toList();
      final down = order.sublist(order.length - top.relegatedCount);
      final up = tables[second.id]!
          .take(second.promotedCount)
          .map((r) => r.clubId)
          .toList();

      final moves = applyPromotionRelegation(fresh, tr.id, tables);

      expect(moves.map((m) => m.clubId), [...down, ...up]);
      for (final m in moves) {
        expect(fresh.clubs[m.clubId]!.leagueId, m.to);
        expect(fresh.leagues[m.to]!.clubIds, contains(m.clubId));
        expect(fresh.leagues[m.from]!.clubIds, isNot(contains(m.clubId)));
      }
      expect(top.clubIds, List.of(top.clubIds)..sort());
      expect(second.clubIds, List.of(second.clubIds)..sort());
    });
  });

  group('scheduleLeagueFixtures', () {
    test('matches the world generator schedule for the same inputs', () {
      final fresh = _world();
      final league = fresh.leagues.values.first;
      final existing = fresh.fixtures.values
          .where((f) => f.leagueId == league.id)
          .toList();
      final ids = IdAllocator();
      final scheduled = scheduleLeagueFixtures(
        league: league,
        calendar: fresh.calendar,
        seasonYear: fresh.seasonYear,
        ids: ids,
        rng: SeededRng(fresh.seed).fork('world').fork('fixtures:${league.id}'),
      );
      expect(scheduled, hasLength(existing.length));
      for (var i = 0; i < existing.length; i++) {
        expect(scheduled[i].id, i + 1);
        expect(scheduled[i].round, existing[i].round);
        expect(scheduled[i].date, existing[i].date);
        expect(scheduled[i].homeId, existing[i].homeId);
        expect(scheduled[i].awayId, existing[i].awayId);
        expect(scheduled[i].seasonYear, existing[i].seasonYear);
        expect(scheduled[i].leagueId, league.id);
        expect(scheduled[i].result, isNull);
      }
    });
  });
}
