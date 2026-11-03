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

/// The first fixture of the season with both clubs' lineups stored.
Fixture _fixture(World w) {
  final ids = w.fixtures.keys.toList()..sort();
  final f = w.fixtures[ids.first]!;
  w.clubs[f.homeId]!.lineup = autoLineup(w, f.homeId);
  w.clubs[f.awayId]!.lineup = autoLineup(w, f.awayId);
  return f;
}

TeamStats _stats() => TeamStats(
  shots: 0,
  onTarget: 0,
  blocked: 0,
  corners: 0,
  fouls: 0,
  yellows: 0,
  reds: 0,
  offsides: 0,
  possessionPct: 50,
  xg: 0,
);

MatchResult _result(
  Fixture f, {
  List<MatchEvent> events = const [],
  Map<PlayerId, double> ratings = const {},
  Map<PlayerId, double> finalCondition = const {},
  bool abandoned = false,
}) => MatchResult(
  homeGoals: 0,
  awayGoals: 0,
  goals: [],
  matchSeed: 1,
  homeStats: _stats(),
  awayStats: _stats(),
  events: [
    ...events,
    FullTime(minute: 90, half: 2, clubId: f.homeId),
  ],
  ratings: ratings,
  finalCondition: finalCondition,
  abandoned: abandoned,
);

Booking _booking(
  Fixture f,
  PlayerId id,
  CardKind kind, {
  FoulKind reason = FoulKind.normal,
}) => Booking(
  minute: 30,
  half: 1,
  clubId: f.homeId,
  playerId: id,
  kind: kind,
  reason: reason,
);

Injury _injury(Fixture f, PlayerId id, int days) => Injury(
  minute: 40,
  half: 1,
  clubId: f.homeId,
  playerId: id,
  injury: InjuryStub(daysLeft: days, type: 'hamstring'),
);

void main() {
  const rules = MatchRules.league;

  group('applyPostMatch', () {
    test('credits apps, goals, assists, cards, ratings, form, sharpness', () {
      final w = _world();
      final f = _fixture(w);
      final home = w.clubs[f.homeId]!.lineup!;
      final away = w.clubs[f.awayId]!.lineup!;
      final scorer = home.starters[10];
      final assister = home.starters[9];
      final ownGoal = away.starters[3];
      final sub = home.bench[0];
      final subbed = home.starters[8];
      final yellow = away.starters[5];
      final red = home.starters[2];
      for (final p in w.players.values) {
        p.state.sharpness = 80;
      }

      final events = applyPostMatch(
        w,
        f,
        _result(
          f,
          events: [
            Goal(
              minute: 10,
              half: 1,
              clubId: f.homeId,
              scorerId: scorer,
              assistId: assister,
              type: ChanceType.cross,
              isPenalty: false,
            ),
            Goal(
              minute: 20,
              half: 1,
              clubId: f.homeId,
              scorerId: ownGoal,
              assistId: null,
              type: ChanceType.cross,
              isPenalty: false,
              isOwnGoal: true,
            ),
            Booking(
              minute: 30,
              half: 1,
              clubId: f.awayId,
              playerId: yellow,
              kind: CardKind.yellow,
              reason: FoulKind.normal,
            ),
            _booking(f, red, CardKind.red, reason: FoulKind.lastMan),
            Substitution(
              minute: 60,
              half: 2,
              clubId: f.homeId,
              outId: subbed,
              inId: sub,
              reason: SubReason.tactical,
            ),
          ],
          ratings: {scorer: 8.0, sub: 6.5},
          finalCondition: {scorer: 61.5, sub: 90.0},
        ),
        rules,
      );

      for (final id in [...home.starters, ...away.starters, sub]) {
        expect(w.players[id]!.season.apps, 1, reason: 'apps of $id');
        expect(w.players[id]!.state.sharpness, 85, reason: 'sharpness $id');
      }
      for (final id in [...home.bench.skip(1), ...away.bench]) {
        expect(w.players[id]!.season.apps, 0);
        expect(w.players[id]!.state.sharpness, 80);
      }
      expect(w.players[scorer]!.season.goals, 1);
      expect(w.players[assister]!.season.assists, 1);
      expect(w.players[ownGoal]!.season.goals, 0);
      expect(w.players[yellow]!.season.yellows, 1);
      expect(w.players[yellow]!.state.yellowCards, 1);
      expect(w.players[red]!.season.reds, 1);
      expect(w.players[scorer]!.season.ratingSum, 8.0);
      expect(w.players[scorer]!.state.form, closeTo(6.4, 1e-9));
      expect(w.players[sub]!.season.ratingSum, 6.5);
      expect(w.players[sub]!.state.form, closeTo(6.1, 1e-9));
      expect(w.players[assister]!.season.ratingSum, 0);
      expect(w.players[assister]!.state.form, 6.0);
      expect(w.players[scorer]!.state.condition, 61.5);
      expect(w.players[sub]!.state.condition, 90.0);
      expect(w.players[assister]!.state.condition, 100);

      // Only the red card produced day events, in event order.
      expect(events.map((e) => e.runtimeType), [
        PlayerSentOff,
        PlayerSuspended,
      ]);
      final off = events[0] as PlayerSentOff;
      expect((off.playerId, off.clubId, off.fixtureId), (red, f.homeId, f.id));
      expect((events[1] as PlayerSuspended).matches, rules.redBanFoul);
      expect(w.players[red]!.state.suspensionMatches, rules.redBanFoul);
    });

    test('the fifth yellow bans for one match; the fourth does not', () {
      final w = _world();
      final f = _fixture(w);
      final id = w.clubs[f.homeId]!.lineup!.starters[4];
      w.players[id]!.state.yellowCards = 3;

      expect(
        applyPostMatch(
          w,
          f,
          _result(f, events: [_booking(f, id, CardKind.yellow)]),
          rules,
        ),
        isEmpty,
      );
      expect(w.players[id]!.state.yellowCards, 4);
      expect(w.players[id]!.state.suspensionMatches, 0);

      final events = applyPostMatch(
        w,
        f,
        _result(f, events: [_booking(f, id, CardKind.yellow)]),
        rules,
      );
      expect(w.players[id]!.state.yellowCards, 5);
      expect(w.players[id]!.state.suspensionMatches, 1);
      expect(w.players[id]!.season.yellows, 2);
      final e = events.single as PlayerSuspended;
      expect((e.playerId, e.clubId, e.matches), (id, f.homeId, 1));
    });

    test('the tenth yellow bans for two matches', () {
      final w = _world();
      final f = _fixture(w);
      final id = w.clubs[f.homeId]!.lineup!.starters[4];
      w.players[id]!.state.yellowCards = 9;
      final events = applyPostMatch(
        w,
        f,
        _result(f, events: [_booking(f, id, CardKind.yellow)]),
        rules,
      );
      expect((events.single as PlayerSuspended).matches, 2);
      expect(w.players[id]!.state.suspensionMatches, 2);
    });

    test('a second yellow bans by redBanSecondYellow, adding to a ban', () {
      final w = _world();
      final f = _fixture(w);
      final id = w.clubs[f.homeId]!.lineup!.starters[4];
      w.players[id]!.state
        ..yellowCards = 2
        ..suspensionMatches = 2;
      final events = applyPostMatch(
        w,
        f,
        _result(
          f,
          events: [
            _booking(f, id, CardKind.yellow),
            _booking(f, id, CardKind.secondYellow),
          ],
        ),
        rules,
      );
      final s = w.players[id]!;
      expect(s.state.yellowCards, 3);
      expect(s.season.yellows, 1);
      expect(s.season.reds, 1);
      expect(s.state.suspensionMatches, 2 + rules.redBanSecondYellow);
      expect(events.map((e) => e.runtimeType), [
        PlayerSentOff,
        PlayerSuspended,
      ]);
      expect((events[1] as PlayerSuspended).matches, rules.redBanSecondYellow);
    });

    test('a straight red bans by its reason', () {
      for (final (reason, ban) in [
        (FoulKind.violent, rules.redBanViolent),
        (FoulKind.lastMan, rules.redBanFoul),
        (FoulKind.normal, rules.redBanFoul),
      ]) {
        final w = _world();
        final f = _fixture(w);
        final id = w.clubs[f.homeId]!.lineup!.starters[4];
        final events = applyPostMatch(
          w,
          f,
          _result(f, events: [_booking(f, id, CardKind.red, reason: reason)]),
          rules,
        );
        expect(w.players[id]!.state.suspensionMatches, ban, reason: '$reason');
        expect(w.players[id]!.state.yellowCards, 0);
        expect(w.players[id]!.season.reds, 1);
        expect((events[1] as PlayerSuspended).matches, ban);
      }
    });

    test('an injury lands in the state, longer for players over 30', () {
      final w = _world();
      final f = _fixture(w);
      final young = w.clubs[f.homeId]!.lineup!.starters[4];
      final old = w.clubs[f.homeId]!.lineup!.starters[5];
      final d = w.date;
      w.players[young]!.birth = GameDate.ymd(d.year - 30, d.month, d.day);
      w.players[old]!.birth = GameDate.ymd(d.year - 31, d.month, d.day);
      expect(w.players[young]!.ageAt(w.date), 30);
      expect(w.players[old]!.ageAt(w.date), 31);

      final events = applyPostMatch(
        w,
        f,
        _result(f, events: [_injury(f, young, 10), _injury(f, old, 10)]),
        rules,
      );
      expect(w.players[young]!.state.injury!.daysLeft, 10);
      expect(w.players[young]!.state.injury!.type, 'hamstring');
      expect(w.players[old]!.state.injury!.daysLeft, 12); // ceil(11.5)
      expect(events.map((e) => e.runtimeType), [PlayerInjured, PlayerInjured]);
      expect((events[0] as PlayerInjured).days, 10);
      final e = events[1] as PlayerInjured;
      expect((e.playerId, e.clubId, e.days), (old, f.homeId, 12));
    });

    test('an abandoned result credits no stats but writes conditions', () {
      final w = _world();
      final f = _fixture(w);
      final home = w.clubs[f.homeId]!.lineup!;
      final scorer = home.starters[10];
      final red = home.starters[2];
      final hurt = home.starters[3];
      final events = applyPostMatch(
        w,
        f,
        _result(
          f,
          events: [
            Goal(
              minute: 10,
              half: 1,
              clubId: f.homeId,
              scorerId: scorer,
              assistId: null,
              type: ChanceType.cross,
              isPenalty: false,
            ),
            _booking(f, red, CardKind.red, reason: FoulKind.violent),
            _injury(f, hurt, 5),
          ],
          ratings: {scorer: 8.0},
          finalCondition: {scorer: 55.0},
          abandoned: true,
        ),
        rules,
      );
      for (final id in home.starters) {
        final p = w.players[id]!;
        expect(p.season.apps, 0);
        expect(p.season.goals, 0);
        expect(p.season.reds, 0);
        expect(p.season.ratingSum, 0);
        expect(p.state.form, 6.0);
        expect(p.state.sharpness, 100);
      }
      expect(w.players[scorer]!.state.condition, 55.0);
      // What happened on the pitch still happened.
      expect(w.players[red]!.state.suspensionMatches, rules.redBanViolent);
      expect(w.players[hurt]!.state.injury!.daysLeft, 5);
      expect(events.map((e) => e.runtimeType), [
        PlayerSentOff,
        PlayerSuspended,
        PlayerInjured,
      ]);
    });
  });

  group('dailyRecovery', () {
    test(
      'heals at zero days with sharpness 40, otherwise raises sharpness',
      () {
        final w = _world();
        final ids = w.players.keys.toList()..sort();
        final healing = w.players[ids[0]]!;
        final hurt = w.players[ids[1]]!;
        final fit = w.players[ids[2]]!;
        final full = w.players[ids[3]]!;
        healing.state
          ..injury = InjuryStub(daysLeft: 1, type: 'sprain')
          ..sharpness = 90;
        hurt.state
          ..injury = InjuryStub(daysLeft: 2, type: 'sprain')
          ..sharpness = 90;
        fit.state.sharpness = 90;
        full.state.sharpness = 100;

        dailyRecovery(w);

        expect(healing.state.injury, isNull);
        expect(healing.state.sharpness, DisciplineTuning.returnSharpness);
        expect(hurt.state.injury!.daysLeft, 1);
        expect(hurt.state.sharpness, 91);
        expect(fit.state.sharpness, 91);
        expect(full.state.sharpness, 100);
      },
    );
  });
}
