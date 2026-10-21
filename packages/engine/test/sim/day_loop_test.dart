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

void main() {
  final runner = DayRunner(const PoissonMatchSimulator());

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

      expect(w.clubs[c]!.lineup!.starters, custom.starters);
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

      final used = w.clubs[c]!.lineup!;
      expect(used.starters, hasLength(11));
      expect(validateLineup(w, c, used), isEmpty);
    });

    test('match results update appearances and goals', () {
      final w = _world();
      final first = w.fixtures.values
          .map((f) => f.date)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      _advanceThrough(runner, w, first);

      var goals = 0;
      for (final id in w.fixturesOn(first)) {
        final f = w.fixtures[id]!;
        for (final clubId in [f.homeId, f.awayId]) {
          for (final p in w.clubs[clubId]!.lineup!.starters) {
            expect(w.players[p]!.season.apps, 1);
          }
        }
        goals += f.result!.goals.length;
      }
      expect(goals, greaterThan(0));
      final tallied = w.players.values.fold(0, (n, p) => n + p.season.goals);
      expect(tallied, goals);
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
        const PoissonMatchSimulator(),
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
