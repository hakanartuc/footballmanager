import 'dart:math' as math;

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

ClubId _firstTrClub() {
  final w = _world();
  final tr = w.countries.values.firstWhere((c) => c.code == 'TR');
  return w.clubs.values.firstWhere((c) => c.countryId == tr.id).id;
}

/// Advances [w] until the day after [date] and returns that day's summary.
DaySummary _advanceThrough(DayRunner runner, World w, GameDate date) {
  late DaySummary last;
  while (!w.date.isAfter(date)) {
    last = runner.advanceDay(w, const []);
  }
  return last;
}

/// Runs the possession engine and keeps every context it was given.
class _CapturingSimulator implements MatchSimulator {
  final contexts = <MatchContext>[];

  @override
  MatchResult simulate(MatchContext ctx) {
    contexts.add(ctx);
    return const PossessionMatchSimulator().simulate(ctx);
  }
}

void main() {
  final runner = DayRunner();

  group('advanceDay', () {
    test('increments the date by one day per call', () {
      final w = _world();
      final start = w.date;
      for (var i = 1; i <= 5; i++) {
        final s = runner.advanceDay(w, const []);
        expect(s.date, start.addDays(i - 1));
        expect(w.date, start.addDays(i));
      }
    });

    test('plays exactly the fixtures of the first matchday', () {
      final w = _world();
      final first = w.fixtures.values
          .map((f) => f.date)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      final expected = w.fixturesOn(first);
      expect(expected, isNotEmpty);

      final s = _advanceThrough(runner, w, first);
      expect(s.date, first);
      expect(s.playedFixtures, expected);
      expect(
        s.events.whereType<MatchPlayed>().map((e) => e.fixtureId),
        expected,
      );
      for (final f in w.fixtures.values) {
        expect(f.result, f.date == first ? isNotNull : isNull);
      }
    });

    test('a valid SetLineup for the user club is used in its next match', () {
      final c = _firstTrClub();
      final w = _world(startClubId: c);
      final auto = autoLineup(w, c);
      final custom = Lineup(
        formation: auto.formation,
        starters: [...auto.starters]..[10] = auto.bench[1],
        bench: [...auto.bench]..[1] = auto.starters[10],
      );
      expect(validateLineup(w, c, custom), isEmpty);

      runner.advanceDay(w, [SetLineup(clubId: c, lineup: custom)]);
      final matchDay =
          w.fixtures[w.fixturesOfClub(c, w.seasonYear).first]!.date;
      _advanceThrough(runner, w, matchDay);

      final f = w.fixtures[w.fixturesOfClub(c, w.seasonYear).first]!;
      expect(
        f.result!.finalCondition.keys,
        containsAll([...custom.starters, ...custom.bench]),
      );
      for (final id in custom.starters) {
        expect(w.players[id]!.season.apps, 1);
      }
      expect(w.players[auto.starters[10]]!.season.apps, 0);
    });

    test('SetLineup stores a copy, not the caller\'s object', () {
      final c = _firstTrClub();
      final w = _world(startClubId: c);
      final custom = autoLineup(w, c);
      final starters = List.of(custom.starters);
      final bench = List.of(custom.bench);

      runner.advanceDay(w, [SetLineup(clubId: c, lineup: custom)]);
      final stored = w.clubs[c]!.lineup!;
      expect(stored, isNot(same(custom)));

      custom.starters[0] = custom.bench[0];
      custom.bench.clear();
      expect(stored.starters, starters);
      expect(stored.bench, bench);
    });

    test('an invalid SetLineup is ignored and an auto lineup is used', () {
      final c = _firstTrClub();
      final w = _world(startClubId: c);
      final auto = autoLineup(w, c);
      final tenMen = Lineup(
        formation: auto.formation,
        starters: auto.starters.take(10).toList(),
        bench: auto.bench,
      );

      runner.advanceDay(w, [SetLineup(clubId: c, lineup: tenMen)]);
      expect(w.clubs[c]!.lineup, isNull);
      final matchDay =
          w.fixtures[w.fixturesOfClub(c, w.seasonYear).first]!.date;
      _advanceThrough(runner, w, matchDay);

      final f = w.fixtures[w.fixturesOfClub(c, w.seasonYear).first]!;
      final squad = w.squadOf(c).toSet();
      final used = f.result!.finalCondition.keys.where(squad.contains);
      expect(used, hasLength(18));
      expect(
        w.players.values.where(
          (p) => p.season.apps == 1 && squad.contains(p.id),
        ),
        hasLength(greaterThanOrEqualTo(11)),
      );
    });

    test('match results update appearances and goals', () {
      final w = _world();
      final first = w.fixtures.values
          .map((f) => f.date)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      _advanceThrough(runner, w, first);

      var goals = 0;
      var appearances = 0;
      for (final id in w.fixturesOn(first)) {
        final r = w.fixtures[id]!.result!;
        goals += r.events.whereType<Goal>().where((g) => !g.isOwnGoal).length;
        appearances += 22 + r.events.whereType<Substitution>().length;
      }
      expect(goals, greaterThan(0));
      final tallied = w.players.values.fold(0, (n, p) => n + p.season.goals);
      expect(tallied, goals);
      expect(
        w.players.values.fold(0, (n, p) => n + p.season.apps),
        appearances,
      );
    });

    test('applies daily condition recovery', () {
      final w = _world();
      final p = w.players.values.first;
      p.state.condition = 50;
      runner.advanceDay(w, const []);
      expect(p.state.condition, 62);
      p.state.condition = 95;
      runner.advanceDay(w, const []);
      expect(p.state.condition, 100);
    });

    test('user club matches reach the inbox, others do not', () {
      final c = _firstTrClub();
      final w = _world(startClubId: c);
      final matchDay =
          w.fixtures[w.fixturesOfClub(c, w.seasonYear).first]!.date;
      _advanceThrough(runner, w, matchDay);

      final played = w.inbox.map((m) => m.event).whereType<MatchPlayed>();
      expect(played, isNotEmpty);
      for (final e in played) {
        final f = w.fixtures[e.fixtureId]!;
        expect([f.homeId, f.awayId], contains(c));
      }
      expect(
        w.fixtures.values.where((f) => f.result != null).length,
        greaterThan(played.length),
      );
    });

    test('inbox ids are strictly increasing across days', () {
      final w = _world(startClubId: _firstTrClub());
      for (var i = 0; i < 40; i++) {
        runner.advanceDay(w, const []);
      }
      final ids = w.inbox.map((m) => m.id).toList();
      expect(ids.length, greaterThan(2));
      expect(ids, [for (var i = 1; i <= ids.length; i++) i]);
      expect(w.ids.next('inbox'), ids.length + 1);
    });

    test('a 7-day advance stays well under 200 ms per day', () {
      final w = _world();
      for (var i = 0; i < 7; i++) {
        final s = runner.advanceDay(w, const []);
        expect(s.elapsed.inMilliseconds, lessThan(200));
      }
    });
  });

  group('availability', () {
    /// The user's club, its first two fixtures and its best senior.
    (World, ClubId, Fixture, Fixture, Player) setup() {
      final c = _firstTrClub();
      final w = _world(startClubId: c);
      final ids = w.fixturesOfClub(c, w.seasonYear);
      final best = w
          .squadOf(c)
          .map((id) => w.players[id]!)
          .reduce((a, b) => a.ca >= b.ca ? a : b);
      return (w, c, w.fixtures[ids[0]]!, w.fixtures[ids[1]]!, best);
    }

    test('a banned player misses exactly the next fixture', () {
      final (w, _, first, second, p) = setup();
      p.state.suspensionMatches = 1;
      _advanceThrough(runner, w, first.date);
      expect(first.result!.finalCondition.keys, isNot(contains(p.id)));
      expect(p.state.suspensionMatches, 0);
      _advanceThrough(runner, w, second.date);
      expect(second.result!.finalCondition.keys, contains(p.id));
    });

    test('an injured player is not picked until healed', () {
      final (w, _, first, second, p) = setup();
      // Heals on the morning after the first fixture.
      p.state.injury = InjuryStub(
        daysLeft: first.date.dayIndex - w.date.dayIndex + 2,
        type: 'sprain',
      );
      _advanceThrough(runner, w, first.date);
      expect(first.result!.finalCondition.keys, isNot(contains(p.id)));
      expect(p.state.injury!.daysLeft, 1);
      runner.advanceDay(w, const []);
      expect(p.state.injury, isNull);
      expect(p.state.sharpness, DisciplineTuning.returnSharpness);
      _advanceThrough(runner, w, second.date);
      expect(second.result!.finalCondition.keys, contains(p.id));
    });

    test('condition carries over from the final whistle', () {
      final (w, _, first, _, _) = setup();
      final s = _advanceThrough(runner, w, first.date);
      expect(s.playedFixtures, contains(first.id));
      final r = first.result!;
      expect(r.finalCondition, isNotEmpty);
      expect(r.finalCondition.values.any((v) => v < 100 - 12), isTrue);
      for (final MapEntry(key: id, value: v) in r.finalCondition.entries) {
        expect(w.players[id]!.state.condition, v);
      }
      // The next day's start adds one recovery on top.
      runner.advanceDay(w, const []);
      for (final MapEntry(key: id, value: v) in r.finalCondition.entries) {
        expect(
          w.players[id]!.state.condition,
          closeTo(math.min(100, v + conditionRecoveryPerDay), 1e-9),
        );
      }
    });
  });

  group('playMatches', () {
    test('every result carries statistics, events and final conditions', () {
      final w = _world();
      final until = w.date.addDays(45);
      while (w.date.isBefore(until)) {
        runner.advanceDay(w, const []);
      }
      final results = [
        for (final f in w.fixtures.values)
          if (f.result != null) f.result!,
      ];
      expect(results.length, greaterThan(50));
      for (final r in results) {
        expect(r.homeStats, isNotNull);
        expect(r.awayStats, isNotNull);
        expect(r.events.last, isA<FullTime>());
        expect(r.finalCondition.length, greaterThanOrEqualTo(22));
        expect(r.conditions, isNotNull);
      }
    });

    test('the context carries league rules, conditions and tactics', () {
      final w = _world();
      final capture = _CapturingSimulator();
      final capturing = DayRunner(sim: capture);
      final first = w.fixtures.values
          .map((f) => f.date)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      _advanceThrough(capturing, w, first);
      expect(capture.contexts, isNotEmpty);
      for (final ctx in capture.contexts) {
        final f = ctx.fixture;
        expect(ctx.rules, same(w.leagues[f.leagueId]!.rules));
        expect(ctx.homeTactic, same(w.clubs[f.homeId]!.tactic));
        expect(ctx.awayTactic, same(w.clubs[f.awayId]!.tactic));
        expect(ctx.detail, MatchDetail.result);
        final expected = sampleConditions(
          w: w,
          f: f,
          rng: SeededRng(w.seed).fork('conditions:${f.id}:${w.seasonYear}'),
        );
        expect(ctx.conditions!.weather, expected.weather);
        expect(ctx.conditions!.pitch, expected.pitch);
        expect(ctx.conditions!.attendance, expected.attendance);
        expect(ctx.conditions!.homeAdvantage, expected.homeAdvantage);
        expect(f.result!.conditions!.attendance, expected.attendance);
      }
    });
  });

  group('startOfDay', () {
    test('re-picks a stored lineup on another formation than the tactic', () {
      final c = _firstTrClub();
      final w = _world(startClubId: c);
      final club = w.clubs[c]!;
      final stored = autoLineup(w, c);
      expect(stored.formation, Formation.f442);
      club.lineup = stored;
      club.formation = Formation.f433;

      final matchDay =
          w.fixtures[w.fixturesOfClub(c, w.seasonYear).first]!.date;
      final capture = _CapturingSimulator();
      _advanceThrough(DayRunner(sim: capture), w, matchDay);
      final ctx = capture.contexts.singleWhere(
        (x) => x.fixture.homeId == c || x.fixture.awayId == c,
      );
      final used = ctx.fixture.homeId == c ? ctx.home : ctx.away;
      expect(used, isNot(same(stored)));
      expect(used.formation, Formation.f433);
    });

    test('a custom tactic plays on its own slots', () {
      final c = _firstTrClub();
      final w = _world(startClubId: c);
      final club = w.clubs[c]!;
      final slots = List.of(formationSlots(Formation.f442))
        ..[10] = Position.amc;
      club.tactics[club.activeTactic] = Tactic.custom(slots, name: 'own');

      final f = w.fixtures[w.fixturesOfClub(c, w.seasonYear).first]!;
      final capture = _CapturingSimulator();
      _advanceThrough(DayRunner(sim: capture), w, f.date);
      expect(f.result, isNotNull);
      final ctx = capture.contexts.singleWhere((x) => x.fixture.id == f.id);
      final used = ctx.fixture.homeId == c ? ctx.home : ctx.away;
      expect(used.formation, Formation.custom);
      expect(used.starters, hasLength(11));
      expect(
        (ctx.fixture.homeId == c ? ctx.homeTactic : ctx.awayTactic)!.slots,
        slots,
      );
    });
  });

  group('endOfDay', () {
    test('keeps at most the 300 most recent inbox messages', () {
      final w = _world();
      final events = [
        for (var i = 0; i < 400; i++) SeasonEnded(date: w.date, seasonYear: i),
      ];
      runner.endOfDay(w, dayEvents: events);
      expect(w.inbox, hasLength(300));
      expect((w.inbox.last.event as SeasonEnded).seasonYear, 399);
      expect((w.inbox.first.event as SeasonEnded).seasonYear, 100);
    });

    test('assigns ids from the allocator; they survive the trim', () {
      final w = _world();
      expect(w.inbox.single.id, 1);
      runner.endOfDay(
        w,
        dayEvents: [
          for (var i = 0; i < 400; i++)
            SeasonEnded(date: w.date, seasonYear: i),
        ],
      );
      runner.endOfDay(
        w,
        dayEvents: [SeasonEnded(date: w.date, seasonYear: 400)],
      );
      // 401 messages issued after the initial one: ids 2..402; the newest
      // 300 remain.
      expect(w.inbox, hasLength(inboxLimit));
      expect(w.inbox.map((m) => m.id), [for (var i = 103; i <= 402; i++) i]);
      expect(w.ids.next('inbox'), 403);
    });

    test('calls the rollover hook on the season end date', () {
      final w = _world();
      final calls = <int>[];
      final hooked = DayRunner(
        rollover: (w, rng) {
          calls.add(w.seasonYear);
          return [SeasonEnded(date: w.date, seasonYear: w.seasonYear)];
        },
      );
      expect(hooked.endOfDay(w), isEmpty);
      w.date = w.calendar.seasonEnd;
      final events = hooked.endOfDay(w);
      expect(events.single, isA<SeasonEnded>());
      expect(calls, [w.seasonYear]);
      expect(w.inbox.last.event, same(events.single));
    });
  });

  group('unemployed user', () {
    test('advances 60 days and only sees season-level events', () {
      final w = _world();
      for (var i = 0; i < 60; i++) {
        runner.advanceDay(w, const []);
      }
      expect(w.fixtures.values.where((f) => f.result != null), isNotEmpty);
      for (final m in w.inbox) {
        expect(m.event, anyOf(isA<SeasonEnded>(), isA<NewSeasonStarted>()));
      }
    });
  });

  group('isUserRelevant', () {
    test('season-level events are always relevant', () {
      final w = _world();
      expect(
        isUserRelevant(w, SeasonEnded(date: w.date, seasonYear: 1)),
        isTrue,
      );
      expect(
        isUserRelevant(w, NewSeasonStarted(date: w.date, seasonYear: 1)),
        isTrue,
      );
    });

    test('club events need the user club', () {
      final c = _firstTrClub();
      final w = _world(startClubId: c);
      final league = w.clubs[c]!.leagueId;
      final other = w.clubs.values.firstWhere((x) => x.leagueId != league);
      final rival = w.clubs.values.firstWhere(
        (x) => x.leagueId == league && x.id != c,
      );
      final d = w.date;
      expect(
        isUserRelevant(
          w,
          LeagueChampion(date: d, leagueId: league, clubId: rival.id),
        ),
        isTrue,
      );
      expect(
        isUserRelevant(
          w,
          LeagueChampion(date: d, leagueId: other.leagueId, clubId: other.id),
        ),
        isFalse,
      );
      // The league the user played in can be passed explicitly.
      expect(
        isUserRelevant(
          w,
          LeagueChampion(date: d, leagueId: other.leagueId, clubId: other.id),
          userLeagueId: other.leagueId,
        ),
        isTrue,
      );
      expect(
        isUserRelevant(
          w,
          LeagueChampion(date: d, leagueId: league, clubId: rival.id),
          userLeagueId: other.leagueId,
        ),
        isFalse,
      );
      expect(
        isUserRelevant(w, PlayerRetired(date: d, playerId: 1, clubId: c)),
        isTrue,
      );
      expect(
        isUserRelevant(w, PlayerRetired(date: d, playerId: 1, clubId: null)),
        isFalse,
      );
      expect(
        isUserRelevant(
          w,
          YouthIntake(date: d, clubId: rival.id, playerIds: []),
        ),
        isFalse,
      );
      expect(
        isUserRelevant(w, YouthReleased(date: d, clubId: c, playerIds: [1])),
        isTrue,
      );
      for (final (club, relevant) in [(c, isTrue), (rival.id, isFalse)]) {
        expect(
          isUserRelevant(
            w,
            PlayerInjured(date: d, playerId: 1, clubId: club, days: 7),
          ),
          relevant,
        );
        expect(
          isUserRelevant(
            w,
            PlayerSentOff(date: d, playerId: 1, clubId: club, fixtureId: 1),
          ),
          relevant,
        );
        expect(
          isUserRelevant(
            w,
            PlayerSuspended(date: d, playerId: 1, clubId: club, matches: 1),
          ),
          relevant,
        );
      }
      expect(
        isUserRelevant(
          w,
          YouthReleased(date: d, clubId: rival.id, playerIds: [1]),
        ),
        isFalse,
      );
      expect(
        isUserRelevant(
          w,
          Promoted(
            date: d,
            clubId: c,
            fromLeagueId: league,
            toLeagueId: league,
          ),
        ),
        isTrue,
      );
      expect(
        isUserRelevant(
          w,
          Relegated(
            date: d,
            clubId: rival.id,
            fromLeagueId: league,
            toLeagueId: league,
          ),
        ),
        isFalse,
      );

      final unemployed = _world();
      expect(
        isUserRelevant(
          unemployed,
          LeagueChampion(date: d, leagueId: league, clubId: c),
        ),
        isFalse,
      );
    });
  });
}
