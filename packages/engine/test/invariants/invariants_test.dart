import 'package:engine/engine.dart';
import 'package:test/test.dart';

World _world() => createNewGame(
  NewGameSpec(
    seed: 1,
    size: WorldSize.small,
    managerFirstName: 'Test',
    managerLastName: 'Manager',
    managerCountryCode: 'TR',
    startClubId: null,
  ),
);

List<String> _rules(World w) => checkInvariants(w).map((v) => v.rule).toList();

Club _firstClub(World w) =>
    w.clubs[w.clubs.keys.reduce((a, b) => a < b ? a : b)]!;

/// A fixture of the current season, by id order.
Fixture _fixtureAt(World w, int n) {
  final ids =
      w.fixtures.keys
          .where((id) => w.fixtures[id]!.seasonYear == w.seasonYear)
          .toList()
        ..sort();
  return w.fixtures[ids[n]]!;
}

/// Per league, where the season's [computeTable] disagrees with its played
/// fixtures: sum of gf, sum of ga and sum of fixture goals must be equal,
/// and sum of played must be twice the played fixtures.
List<String> _tableMismatches(World w) {
  final out = <String>[];
  for (final l in w.leagues.keys) {
    final rows = computeTable(w, l, w.seasonYear);
    final gf = rows.fold(0, (n, r) => n + r.gf);
    final ga = rows.fold(0, (n, r) => n + r.ga);
    final played = rows.fold(0, (n, r) => n + r.played);
    var goals = 0, fixtures = 0;
    for (final f in w.fixtures.values) {
      final r = f.result;
      if (f.leagueId != l || f.seasonYear != w.seasonYear || r == null) {
        continue;
      }
      goals += r.homeGoals + r.awayGoals;
      fixtures++;
    }
    if (gf != ga || ga != goals || played != 2 * fixtures) {
      out.add(
        'league $l: gf $gf ga $ga goals $goals played $played of $fixtures',
      );
    }
  }
  return out;
}

void main() {
  test('fresh small world has no violations', () {
    expect(checkInvariants(_world()), isEmpty);
  });

  group('player.oneClub', () {
    test('contract pointing at a missing club', () {
      final w = _world();
      final p = w.players[w.squadOf(_firstClub(w).id).first]!;
      p.contract!.clubId = 999999;
      expect(_rules(w), contains('player.oneClub'));
    });

    test('contracted player missing from the squad index', () {
      final w = _world();
      final club = _firstClub(w);
      final p = w.players[w.squadOf(club.id).first]!;
      final contract = p.contract!;
      p.contract = null;
      w.rebuildIndexes();
      expect(
        checkInvariants(w).where((v) => v.rule == 'player.oneClub'),
        isEmpty,
      );
      p.contract = contract;
      expect(_rules(w), contains('player.oneClub'));
    });

    test('free agent still in a squad index', () {
      final w = _world();
      final p = w.players[w.squadOf(_firstClub(w).id).first]!;
      p.contract = null;
      expect(_rules(w), contains('player.oneClub'));
    });
  });

  test('squad.size', () {
    final w = _world();
    final clubs = w.clubs.keys.toList()..sort();
    final from = clubs[0], to = clubs[1];
    for (final id in w.squadOf(from).take(10)) {
      w.players[id]!.contract!.clubId = to;
    }
    w.rebuildIndexes();
    final sizes = checkInvariants(w).where((v) => v.rule == 'squad.size');
    expect(sizes, hasLength(2));
  });

  test('lineup.valid', () {
    final w = _world();
    _firstClub(w).lineup = Lineup(
      formation: Formation.f442,
      starters: [],
      bench: [],
    );
    expect(_rules(w), contains('lineup.valid'));
  });

  test('player.ranges', () {
    final w = _world();
    final p = w.players[w.squadOf(_firstClub(w).id).first]!;
    p.ca = p.pa + 1;
    expect(_rules(w), contains('player.ranges'));
    p.ca = p.pa;
    p.state.condition = -1;
    expect(_rules(w), contains('player.ranges'));
  });

  test('contract.dates', () {
    final w = _world();
    final c = w.players[w.squadOf(_firstClub(w).id).first]!.contract!;
    c.end = c.start;
    expect(_rules(w), contains('contract.dates'));
    c.end = c.start.addDays(1);
    c.start = w.date.addDays(-30);
    c.end = w.date.addDays(-2);
    expect(_rules(w), contains('contract.dates'));
  });

  group('league.fixtures', () {
    test('a missing fixture', () {
      final w = _world();
      w.fixtures.remove(_fixtureAt(w, 0).id);
      w.rebuildIndexes();
      expect(_rules(w), contains('league.fixtures'));
    });

    test('a league with no fixtures this season', () {
      final w = _world();
      final l = w.leagues.keys.first;
      w.fixtures.removeWhere(
        (_, f) => f.leagueId == l && f.seasonYear == w.seasonYear,
      );
      w.rebuildIndexes();
      expect(_rules(w), contains('league.fixtures'));
    });
  });

  group('fixture.goals', () {
    late World w;
    late Fixture f;

    setUp(() {
      w = _world();
      f = _fixtureAt(w, 0);
      w.date = f.date.addDays(1);
      final scorer = w.squadOf(f.homeId).first;
      f.result = MatchResult(
        homeGoals: 1,
        awayGoals: 0,
        goals: [GoalEvent(minute: 10, scorerId: scorer, clubId: f.homeId)],
        matchSeed: 0,
      );
      expect(_rules(w), isNot(contains('fixture.goals')));
    });

    test('a dropped goal event', () {
      f.result!.goals.clear();
      expect(_rules(w), contains('fixture.goals'));
    });

    test('a goal credited to the wrong club', () {
      f.result!.goals.single.clubId = f.awayId;
      expect(_rules(w), contains('fixture.goals'));
    });

    test('a goal by a club outside the fixture', () {
      f.result!.goals.single.clubId = 999999;
      expect(_rules(w), contains('fixture.goals'));
    });

    test('a scorer who does not exist', () {
      f.result!.goals.single.scorerId = 999999;
      expect(_rules(w), contains('fixture.goals'));
    });

    Goal goal(ClubId club) => Goal(
      minute: 10,
      half: 1,
      clubId: club,
      scorerId: w.squadOf(f.homeId).first,
      assistId: null,
      type: ChanceType.dribble,
      isPenalty: false,
    );

    test('consistent match events pass', () {
      f.result!.events.addAll([
        goal(f.homeId),
        HalfTime(minute: 45, half: 1, clubId: f.homeId),
        FullTime(minute: 90, half: 2, clubId: f.homeId),
      ]);
      expect(_rules(w), isNot(contains('fixture.goals')));
    });

    test('an own goal counts for the club it is credited to', () {
      f.result!.events.add(
        Goal(
          minute: 10,
          half: 1,
          clubId: f.homeId,
          scorerId: w.squadOf(f.awayId).first,
          assistId: null,
          type: ChanceType.cross,
          isPenalty: false,
          isOwnGoal: true,
        ),
      );
      expect(_rules(w), isNot(contains('fixture.goals')));
    });

    test('Goal events disagreeing with the score', () {
      f.result!.events.addAll([goal(f.homeId), goal(f.awayId)]);
      expect(_rules(w), contains('fixture.goals'));
    });

    test('Goal events credited to the wrong club', () {
      f.result!.events.add(goal(f.awayId));
      expect(_rules(w), contains('fixture.goals'));
    });
  });

  test('calendar.noDoubleBooking', () {
    final w = _world();
    final club = _firstClub(w);
    final own = w.fixturesOfClub(club.id, w.seasonYear);
    w.fixtures[own[1]]!.date = w.fixtures[own[0]]!.date;
    w.rebuildIndexes();
    expect(_rules(w), contains('calendar.noDoubleBooking'));
  });

  test('ids.unique', () {
    final w = _world();
    w.players[-1] = w.players[w.players.keys.first]!;
    expect(_rules(w), contains('ids.unique'));
  });

  test('manager.seat', () {
    final w = _world();
    _firstClub(w).managerId = null;
    expect(_rules(w), contains('manager.seat'));
  });

  test('inbox.size', () {
    final w = _world();
    for (var i = 0; i < 301; i++) {
      w.inbox.add(
        InboxMessage(
          id: w.ids.next('inbox'),
          date: w.date,
          event: SeasonEnded(date: w.date, seasonYear: 2025),
        ),
      );
    }
    expect(_rules(w), contains('inbox.size'));
  });

  group('inbox.ids', () {
    test('a duplicate id', () {
      final w = _world();
      w.inbox.add(
        InboxMessage(
          id: w.inbox.first.id,
          date: w.date,
          event: SeasonEnded(date: w.date, seasonYear: 2025),
        ),
      );
      expect(_rules(w), contains('inbox.ids'));
    });

    test('id 0', () {
      final w = _world();
      w.inbox.add(
        InboxMessage(
          id: 0,
          date: w.date,
          event: SeasonEnded(date: w.date, seasonYear: 2025),
        ),
      );
      expect(_rules(w), contains('inbox.ids'));
    });

    test('allocated ids pass', () {
      final w = _world();
      w.inbox.add(
        InboxMessage(
          id: w.ids.next('inbox'),
          date: w.date,
          event: SeasonEnded(date: w.date, seasonYear: 2025),
        ),
      );
      expect(_rules(w), isNot(contains('inbox.ids')));
    });
  });

  group('inbox.refs', () {
    test('a missing fixture', () {
      final w = _world();
      w.inbox.add(
        InboxMessage(
          id: w.ids.next('inbox'),
          date: w.date,
          event: MatchPlayed(date: w.date, fixtureId: 999999),
        ),
      );
      expect(_rules(w), contains('inbox.refs'));
    });

    test('youth intake and release player ids are exempt', () {
      // The players may have been released or retired since.
      final w = _world();
      final club = _firstClub(w).id;
      w.inbox.addAll([
        InboxMessage(
          id: w.ids.next('inbox'),
          date: w.date,
          event: YouthIntake(date: w.date, clubId: club, playerIds: [999999]),
        ),
        InboxMessage(
          id: w.ids.next('inbox'),
          date: w.date,
          event: YouthReleased(date: w.date, clubId: club, playerIds: [999998]),
        ),
      ]);
      expect(_rules(w), isNot(contains('inbox.refs')));
    });

    test('injury, sending-off and suspension refs pass', () {
      final w = _world();
      final club = _firstClub(w).id;
      final player = w.squadOf(club).first;
      final fixture = w.fixturesOfClub(club, w.seasonYear).first;
      w.inbox.addAll([
        for (final e in <GameEvent>[
          PlayerInjured(date: w.date, playerId: player, clubId: club, days: 9),
          PlayerSentOff(
            date: w.date,
            playerId: player,
            clubId: club,
            fixtureId: fixture,
          ),
          PlayerSuspended(
            date: w.date,
            playerId: player,
            clubId: club,
            matches: 1,
          ),
        ])
          InboxMessage(id: w.ids.next('inbox'), date: w.date, event: e),
      ]);
      expect(_rules(w), isNot(contains('inbox.refs')));
    });

    group('injury, sending-off and suspension', () {
      late World w;
      late ClubId club;
      late PlayerId player;
      late FixtureId fixture;

      setUp(() {
        w = _world();
        club = _firstClub(w).id;
        player = w.squadOf(club).first;
        fixture = w.fixturesOfClub(club, w.seasonYear).first;
      });

      void add(GameEvent e) => w.inbox.add(
        InboxMessage(id: w.ids.next('inbox'), date: w.date, event: e),
      );

      test('an injury at a missing club', () {
        add(
          PlayerInjured(
            date: w.date,
            playerId: player,
            clubId: 999999,
            days: 3,
          ),
        );
        expect(_rules(w), contains('inbox.refs'));
      });

      test('an injured player who does not exist', () {
        add(
          PlayerInjured(date: w.date, playerId: 999999, clubId: club, days: 3),
        );
        expect(_rules(w), contains('inbox.refs'));
      });

      test('a sending-off in a missing fixture', () {
        add(
          PlayerSentOff(
            date: w.date,
            playerId: player,
            clubId: club,
            fixtureId: 999999,
          ),
        );
        expect(_rules(w), contains('inbox.refs'));
      });

      test('a sending-off at a missing club', () {
        add(
          PlayerSentOff(
            date: w.date,
            playerId: player,
            clubId: 999999,
            fixtureId: fixture,
          ),
        );
        expect(_rules(w), contains('inbox.refs'));
      });

      test('a suspension at a missing club', () {
        add(
          PlayerSuspended(
            date: w.date,
            playerId: player,
            clubId: 999999,
            matches: 1,
          ),
        );
        expect(_rules(w), contains('inbox.refs'));
      });
    });

    test('a youth release at a missing club', () {
      final w = _world();
      w.inbox.add(
        InboxMessage(
          id: w.ids.next('inbox'),
          date: w.date,
          event: YouthReleased(date: w.date, clubId: 999999, playerIds: []),
        ),
      );
      expect(_rules(w), contains('inbox.refs'));
    });
  });

  test('history.champion', () {
    final w = _world();
    final l = w.leagues.values.first;
    w.history.add(
      SeasonArchive(
        seasonYear: 2025,
        champions: {l.id: l.clubIds[0]},
        finalOrder: {
          l.id: [l.clubIds[1], l.clubIds[0]],
        },
      ),
    );
    expect(_rules(w), contains('history.champion'));
  });

  test('fixture.result', () {
    final w = _world();
    final f = _fixtureAt(w, 0);
    f.result = MatchResult(homeGoals: 1, awayGoals: 1, goals: [], matchSeed: 0);
    expect(_rules(w), contains('fixture.result'));
    f.result = null;
    w.date = f.date.addDays(1);
    expect(_rules(w), contains('fixture.result'));
  });

  group('full season', () {
    late World w;
    late GameDate seasonEnd;
    late List<String> daily;
    late List<String> tableMismatches;

    setUpAll(() {
      w = _world();
      daily = [];
      tableMismatches = [];
      final runner = DayRunner(
        const PoissonMatchSimulator(),
        rollover: (w, rng) {
          tableMismatches = _tableMismatches(w);
          return rolloverSeason(w, rng);
        },
      );
      seasonEnd = w.calendar.seasonEnd;
      while (!w.date.isAfter(seasonEnd)) {
        runner.advanceDay(w, const []);
        for (final v in checkInvariants(w)) {
          daily.add('${w.date.iso}: $v');
        }
      }
    });

    test('every day of the season is violation-free', () {
      expect(daily, isEmpty);
    });

    test('final tables agree with the fixtures', () {
      expect(tableMismatches, isEmpty);
    });

    test('seasonEnd + 1 is violation-free', () {
      expect(w.date, seasonEnd.addDays(1));
      expect(w.history, hasLength(1));
      expect(checkInvariants(w), isEmpty);
    });
  });
}
