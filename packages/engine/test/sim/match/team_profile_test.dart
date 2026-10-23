import 'dart:math' as math;

import 'package:engine/engine.dart';
import 'package:test/test.dart';

/// Factors all 1.0: familiarity 20 in [slot], condition 100, sharpness 100,
/// morale 50, form 5.5.
Player _player(PlayerId id, Position slot, {int attr = 10}) => Player(
  id: id,
  firstName: 'P',
  lastName: '$id',
  nationality: 1,
  birth: GameDate.ymd(2000, 1, 1),
  heightCm: 180,
  mainPosition: slot,
  familiarity: {slot: 20},
  attrs: Attributes.filled(attr),
  ca: 100,
  pa: 100,
  hidden: HiddenAttrs(
    injuryProneness: 10,
    consistency: 10,
    bigMatches: 10,
    professionalism: 10,
  ),
  state: PlayerState(condition: 100, sharpness: 100, morale: 50, form: 5.5),
);

World _world(Map<PlayerId, Player> players) => World(
  schemaVersion: currentSchemaVersion,
  seed: 1,
  date: GameDate.ymd(2026, 8, 1),
  seasonYear: 2026,
  countries: {},
  leagues: {},
  clubs: {},
  players: players,
  managers: {},
  fixtures: {},
  calendar: buildSeasonCalendar(2026),
  userManagerId: 1,
  ids: IdAllocator(),
);

const _dry = MatchConditions(
  weather: Weather.sunny,
  pitch: 8,
  attendance: 1000,
  homeAdvantage: 1.06,
);

MatchConditions _cond({Weather weather = Weather.sunny, int pitch = 8}) =>
    MatchConditions(
      weather: weather,
      pitch: pitch,
      attendance: 1000,
      homeAdvantage: 1.06,
    );

/// Ids 1..11 on [slots] (uniform 10s) plus 101..111 for an opponent.
World _worldOn(List<Position> slots) => _world({
  for (var i = 0; i < slots.length; i++) i + 1: _player(i + 1, slots[i]),
  for (var i = 0; i < slots.length; i++) 101 + i: _player(101 + i, slots[i]),
});

final _ids = [for (var i = 1; i <= 11; i++) i];

TeamProfile _build(
  World w,
  Tactic t, {
  List<PlayerId>? onPitch,
  Map<PlayerId, double>? condition,
  bool home = false,
  MatchConditions cond = _dry,
  Tactic? opponent,
}) => buildProfile(
  w: w,
  tactic: t,
  onPitch: onPitch ?? _ids,
  condition: condition ?? {for (final id in onPitch ?? _ids) id: 100.0},
  home: home,
  cond: cond,
  opponentTactic: opponent,
);

void _expectStrengths(
  TeamProfile p, {
  double mid = 10,
  double attL = 10,
  double attC = 10,
  double attR = 10,
  double defL = 10,
  double defC = 10,
  double defR = 10,
  double gk = 10,
  double setPieceAtt = 10,
  double setPieceDef = 10,
}) {
  expect(p.mid, closeTo(mid, 0.01), reason: 'mid');
  expect(p.attL, closeTo(attL, 0.01), reason: 'attL');
  expect(p.attC, closeTo(attC, 0.01), reason: 'attC');
  expect(p.attR, closeTo(attR, 0.01), reason: 'attR');
  expect(p.defL, closeTo(defL, 0.01), reason: 'defL');
  expect(p.defC, closeTo(defC, 0.01), reason: 'defC');
  expect(p.defR, closeTo(defR, 0.01), reason: 'defR');
  expect(p.gk, closeTo(gk, 0.01), reason: 'gk');
  expect(p.setPieceAtt, closeTo(setPieceAtt, 0.01), reason: 'setPieceAtt');
  expect(p.setPieceDef, closeTo(setPieceDef, 0.01), reason: 'setPieceDef');
}

void _expectBalancedKnobs(TeamProfile p) {
  expect(p.tempoMul, 1.0);
  expect(p.pressMul, 1.0);
  expect(p.conditionDrain, 1.0);
  expect(p.foulMul, 1.0);
  expect(p.cardMul, 1.0);
  expect(p.injuryToOpponentMul, 1.0);
  expect(p.injuryMul, 1.0);
  expect(p.keeperErrorMul, 1.0);
  expect(p.throughBallXgMul, 1.0);
  expect(p.counterProb, 0.15);
  expect(p.counterAttMul, 1.0);
  expect(p.midBypass, 0.1);
  expect(p.laneWeights, {Lane.left: 0.3, Lane.centre: 0.4, Lane.right: 0.3});
  expect(p.chanceWeights, {for (final t in ChanceType.values) t: 1.0});
  expect(p.selectionBoost, isEmpty);
  expect(p.markedOpponents, isEmpty);
}

void main() {
  final w442 = _worldOn(formationSlots(Formation.f442));
  Tactic t442() => Tactic.preset(Formation.f442);

  group('playerEffectiveness', () {
    final p = _player(1, Position.mc);

    test('familiarity maps 1..20 to 0.6..1.0; missing counts as 1', () {
      p.familiarity = {Position.mc: 20, Position.st: 1, Position.dc: 10};
      expect(playerEffectiveness(p, Attr.passing, Position.mc), 10.0);
      expect(playerEffectiveness(p, Attr.passing, Position.st), 6.0);
      expect(
        playerEffectiveness(p, Attr.passing, Position.dc),
        closeTo(10 * (0.6 + 0.4 * 9 / 19), 1e-9),
      );
      expect(playerEffectiveness(p, Attr.passing, Position.gk), 6.0);
      p.familiarity = {Position.mc: 20};
    });

    test('condition: 0.5 at 0, 0.75 at 50, 1.0 at 100 (spec 5.2)', () {
      p.state.condition = 0;
      expect(playerEffectiveness(p, Attr.passing, Position.mc), 5.0);
      p.state.condition = 50;
      expect(playerEffectiveness(p, Attr.passing, Position.mc), 7.5);
      p.state.condition = 100;
      expect(playerEffectiveness(p, Attr.passing, Position.mc), 10.0);
      expect(
        playerEffectiveness(p, Attr.passing, Position.mc, condition: 0),
        5.0,
      );
    });

    test('sharpness 0.9..1.0, morale 0.95..1.05, form 0.95..1.05', () {
      p.state.sharpness = 0;
      expect(playerEffectiveness(p, Attr.passing, Position.mc), 9.0);
      p.state.sharpness = 100;
      p.state.morale = 0;
      expect(playerEffectiveness(p, Attr.passing, Position.mc), 9.5);
      p.state.morale = 100;
      expect(playerEffectiveness(p, Attr.passing, Position.mc), 10.5);
      p.state.morale = 50;
      p.state.form = 1;
      expect(playerEffectiveness(p, Attr.passing, Position.mc), 9.5);
      p.state.form = 10;
      expect(playerEffectiveness(p, Attr.passing, Position.mc), 10.5);
      p.state.form = 0;
      expect(playerEffectiveness(p, Attr.passing, Position.mc), 9.5);
      p.state.form = 5.5;
      expect(playerEffectiveness(p, Attr.passing, Position.mc), 10.0);
    });

    test('reads the requested attribute', () {
      p.attrs.set(Attr.finishing, 4);
      expect(playerEffectiveness(p, Attr.finishing, Position.mc), 4.0);
      p.attrs.set(Attr.finishing, 10);
    });
  });

  group('balanced baseline', () {
    test('uniform 10s give 10 everywhere and neutral knobs', () {
      final p = _build(w442, t442());
      _expectStrengths(p);
      _expectBalancedKnobs(p);
      expect(p.onPitch, _ids);
      expect(p.bySlot[Position.gk], 1);
      expect(p.bySlot[Position.dc], 3);
      expect(p.slotOf[4], Position.dc);
      expect(p.slotOf[10], Position.st);
      expect(p.att(Lane.left), p.attL);
      expect(p.def(Lane.right), p.defR);
    });

    test('every preset: att/def/gk 10, mid shifted by midfielder count', () {
      const midCount = {
        Formation.f442: 4.0,
        Formation.f433: 4.0,
        Formation.f451: 5.0,
        Formation.f352: 5.0,
        Formation.f4231: 3.5,
        Formation.f532: 3.0,
      };
      for (final f in midCount.keys) {
        final w = _worldOn(formationSlots(f));
        final p = _build(w, Tactic.preset(f));
        _expectStrengths(p, mid: 10 + 0.3 * (midCount[f]! - 4));
      }
    });

    test('condition map overrides state; missing entry reads state', () {
      final cond = {for (final id in _ids) id: 100.0}..[7] = 0.0;
      final p = _build(w442, t442(), condition: cond);
      // mc 7 at ×0.5: mid (30 + 5) / 4, attC the same, set-piece
      // defence (100 + 5) / 11.
      _expectStrengths(p, mid: 8.75, attC: 8.75, setPieceDef: 105 / 11);

      w442.players[8]!.state.condition = 0;
      final q = _build(w442, t442(), condition: cond..remove(8));
      _expectStrengths(q, mid: 7.5, attC: 7.5, setPieceDef: 100 / 11);
      w442.players[8]!.state.condition = 100;
    });
  });

  group('tactic settings', () {
    test('mentality scales att and def in opposite directions', () {
      const table = {
        Mentality.veryDefensive: (0.85, 1.15),
        Mentality.defensive: (0.92, 1.08),
        Mentality.balanced: (1.0, 1.0),
        Mentality.attacking: (1.08, 0.92),
        Mentality.veryAttacking: (1.15, 0.85),
      };
      for (final MapEntry(key: m, value: (a, d)) in table.entries) {
        final p = _build(w442, t442()..mentality = m);
        _expectStrengths(
          p,
          attL: 10 * a,
          attC: 10 * a,
          attR: 10 * a,
          defL: 10 * d,
          defC: 10 * d,
          defR: 10 * d,
        );
        _expectBalancedKnobs(p);
      }
    });

    test('passing: short boosts mid; bypass grows; long ball shifts types', () {
      final short = _build(w442, t442()..passing = PassingStyle.short);
      _expectStrengths(short, mid: 11);
      expect(short.midBypass, 0.0);
      expect(short.chanceWeights, {for (final t in ChanceType.values) t: 1.0});

      expect(
        _build(w442, t442()..passing = PassingStyle.direct).midBypass,
        0.2,
      );

      final long = _build(w442, t442()..passing = PassingStyle.longBall);
      _expectStrengths(long);
      expect(long.midBypass, 0.3);
      expect(long.chanceWeights[ChanceType.cross], 1.5);
      expect(long.chanceWeights[ChanceType.throughBall], 0.7);
      expect(long.chanceWeights[ChanceType.longShot], 1.0);
      expect(long.chanceWeights[ChanceType.dribble], 1.0);
    });

    test('tempo sets tempoMul and drain', () {
      final slow = _build(w442, t442()..tempo = Tempo.slow);
      _expectStrengths(slow);
      expect(slow.tempoMul, 0.85);
      expect(slow.conditionDrain, 0.85);
      final fast = _build(w442, t442()..tempo = Tempo.fast);
      _expectStrengths(fast);
      expect(fast.tempoMul, 1.3);
      expect(fast.conditionDrain, 1.3);
    });

    test('width sets lane weights', () {
      expect(_build(w442, t442()..width = Width.narrow).laneWeights, {
        Lane.left: 0.25,
        Lane.centre: 0.5,
        Lane.right: 0.25,
      });
      expect(_build(w442, t442()..width = Width.wide).laneWeights, {
        Lane.left: 0.4,
        Lane.centre: 0.2,
        Lane.right: 0.4,
      });
    });

    test('pressing sets pressMul for the opponent and own drain', () {
      final high = _build(w442, t442()..pressing = Pressing.high);
      _expectStrengths(high);
      expect(high.pressMul, 0.92);
      expect(high.conditionDrain, 1.25);
      final low = _build(w442, t442()..pressing = Pressing.low);
      _expectStrengths(low);
      expect(low.pressMul, 1.0);
      expect(low.conditionDrain, 0.9);
    });

    test('pressing and tempo drains multiply', () {
      final p = _build(
        w442,
        t442()
          ..pressing = Pressing.high
          ..tempo = Tempo.fast,
      );
      expect(p.conditionDrain, closeTo(1.3 * 1.25, 1e-12));
    });

    test('tackling sets foul, card, injury and ball-winning multipliers', () {
      final soft = _build(w442, t442()..tackling = Tackling.soft);
      _expectStrengths(soft, defL: 9.5, defC: 9.5, defR: 9.5);
      expect(soft.foulMul, 0.8);
      expect(soft.cardMul, 0.8);
      expect(soft.injuryToOpponentMul, 0.9);
      final hard = _build(w442, t442()..tackling = Tackling.hard);
      _expectStrengths(hard, defL: 11, defC: 11, defR: 11);
      expect(hard.foulMul, 1.3);
      expect(hard.cardMul, 1.4);
      expect(hard.injuryToOpponentMul, 1.4);
    });

    test('man marking lists marked opponents and costs ×0.8 att each', () {
      final opp = Tactic.preset(Formation.f442)
        ..playmaker = 106
        ..targetMan = 110;
      final two = _build(w442, t442()..marking = Marking.man, opponent: opp);
      expect(two.markedOpponents, {106, 110});
      _expectStrengths(two, attL: 6.4, attC: 6.4, attR: 6.4);

      opp.targetMan = null;
      final one = _build(w442, t442()..marking = Marking.man, opponent: opp);
      expect(one.markedOpponents, {106});
      _expectStrengths(one, attL: 8, attC: 8, attR: 8);

      final zonal = _build(w442, t442(), opponent: opp);
      expect(zonal.markedOpponents, isEmpty);
      _expectStrengths(zonal);

      final noOpp = _build(w442, t442()..marking = Marking.man);
      expect(noOpp.markedOpponents, isEmpty);
      _expectStrengths(noOpp);

      opp.playmaker = 999;
      final dangling = _build(
        w442,
        t442()..marking = Marking.man,
        opponent: opp,
      );
      expect(dangling.markedOpponents, isEmpty);
      _expectStrengths(dangling);
    });

    test('opponent man marking scales our marked players ×0.85', () {
      final opp = Tactic.preset(Formation.f442)..marking = Marking.man;
      final p = _build(w442, t442()..playmaker = 10, opponent: opp);
      // st 10 at ×0.85: attC (10 + 10 + 8.5 + 10) / 4; attL (10 + 4.25 + 5) / 2;
      // set-piece defence (100 + 8.5) / 11.
      _expectStrengths(
        p,
        attC: 9.625,
        attL: 9.625,
        attR: 9.625,
        setPieceDef: 108.5 / 11,
      );
      final q = _build(w442, t442()..playmaker = 10);
      _expectStrengths(q);
    });

    test('offside trap sets the through-ball xG multiplier', () {
      final p = _build(w442, t442()..offsideTrap = true);
      _expectStrengths(p);
      expect(p.throughBallXgMul, 0.75);
    });

    test('counter attack raises counterProb and counter att', () {
      final p = _build(w442, t442()..counterAttack = true);
      _expectStrengths(p);
      expect(p.counterProb, 0.28);
      expect(p.counterAttMul, 1.15);
    });

    test('arrows scale that player: forward att ×1.25 / def ×0.85', () {
      final fwd = _build(w442, t442()..arrows = {6: Arrow.forward});
      // ml 6: attL (12.5 + 5 + 5) / 2; defL (10 + 0.3 × 8.5) / 1.3.
      _expectStrengths(fwd, attL: 11.25, defL: 12.55 / 1.3);
      final back = _build(w442, t442()..arrows = {6: Arrow.back});
      _expectStrengths(back, attL: 9.25, defL: 13.75 / 1.3);
      final none = _build(
        w442,
        t442()..arrows = {6: Arrow.none, 999: Arrow.forward},
      );
      _expectStrengths(none);
    });

    test('playmaker, target man and instructions boost selection', () {
      final p = _build(
        w442,
        t442()
          ..playmaker = 7
          ..targetMan = 10
          ..instructions = {
            8: PlayerInstructions(longShots: true, throughBalls: true),
            10: PlayerInstructions(forwardRuns: true, runWithBall: true),
            999: PlayerInstructions(longShots: true),
          },
      );
      _expectStrengths(p);
      expect(p.selectionBoost, {7: 2.0, 8: 2.25, 10: 3.0});
    });

    test('dangling playmaker, target man, captain and takers are ignored', () {
      final p = _build(
        w442,
        t442()
          ..playmaker = 999
          ..targetMan = 998
          ..captain = 997
          ..viceCaptain = 996
          ..setPieces = SetPieceTakers(penalty: 995, cornerLeft: 994),
      );
      _expectStrengths(p);
      _expectBalancedKnobs(p);
    });
  });

  group('conditions', () {
    test('home scales att and mid by cond.homeAdvantage', () {
      final p = _build(w442, t442(), home: true, cond: _dry);
      _expectStrengths(p, mid: 10.6, attL: 10.6, attC: 10.6, attR: 10.6);
      final c = MatchConditions(
        weather: Weather.sunny,
        pitch: 8,
        attendance: 1,
        homeAdvantage: 1.04,
      );
      final q = _build(w442, t442(), home: true, cond: c);
      _expectStrengths(q, mid: 10.4, attL: 10.4, attC: 10.4, attR: 10.4);
    });

    test('rain or a bad pitch: short pass ×0.92, long ball ×1.05', () {
      for (final c in [
        _cond(weather: Weather.rainy),
        _cond(weather: Weather.heavyRain),
        _cond(pitch: 4),
      ]) {
        final p = _build(w442, t442(), cond: c);
        _expectStrengths(p, mid: 9.2);
        expect(p.keeperErrorMul, 1.3);
        expect(p.injuryMul, 1.15);
        expect(p.conditionDrain, 1.0);
        final s = _build(w442, t442()..passing = PassingStyle.short, cond: c);
        _expectStrengths(s, mid: 11 * 0.92);
        for (final style in [PassingStyle.direct, PassingStyle.longBall]) {
          final l = _build(w442, t442()..passing = style, cond: c);
          _expectStrengths(l, mid: 10.5);
        }
      }
      final dry = _build(w442, t442(), cond: _cond(pitch: 5));
      _expectStrengths(dry);
      expect(dry.keeperErrorMul, 1.0);
      expect(dry.injuryMul, 1.0);
    });

    test('hot weather raises drain only', () {
      final p = _build(w442, t442(), cond: _cond(weather: Weather.hot));
      _expectStrengths(p);
      expect(p.conditionDrain, 1.15);
      expect(p.keeperErrorMul, 1.0);
      final q = _build(
        w442,
        t442()..tempo = Tempo.fast,
        cond: _cond(weather: Weather.hot),
      );
      expect(q.conditionDrain, closeTo(1.3 * 1.15, 1e-12));
    });
  });

  group('short-handed', () {
    test('ten men: mid and def ×0.85, the missing slot is absent', () {
      final ten = _ids.sublist(0, 10);
      final p = _build(w442, t442(), onPitch: ten);
      _expectStrengths(p, mid: 8.5, defL: 8.5, defC: 8.5, defR: 8.5);
      expect(p.onPitch, ten);
      expect(p.slotOf.containsKey(11), isFalse);
    });

    test('nine men: ×0.85² on mid/def and att ×0.9', () {
      final nine = _ids.sublist(0, 9);
      final p = _build(w442, t442(), onPitch: nine);
      // No st left: attC is the two mc, attL/attR the wide mid; all ×0.9.
      _expectStrengths(
        p,
        mid: 10 * 0.85 * 0.85,
        defL: 10 * 0.85 * 0.85,
        defC: 10 * 0.85 * 0.85,
        defR: 10 * 0.85 * 0.85,
        attL: 9,
        attC: 9,
        attR: 9,
      );
    });

    test('no goalkeeper on pitch gives gk 5', () {
      final slots = [...formationSlots(Formation.f442).skip(1), Position.gk];
      final w = _worldOn(slots);
      final t = Tactic(name: 'x', formation: Formation.custom, slots: slots);
      final p = _build(w, t, onPitch: _ids.sublist(0, 10));
      expect(p.gk, 5.0);
      expect(p.mid.isNaN, isFalse);
    });
  });

  group('empty lanes', () {
    test('an empty attack or defence lane is 0.8 × the mean of the others', () {
      const slots = [
        Position.gk,
        Position.dc,
        Position.dc,
        Position.dc,
        Position.dr,
        Position.dm,
        Position.mc,
        Position.mc,
        Position.mc,
        Position.amc,
        Position.amr,
      ];
      final w = _worldOn(slots);
      final p = _build(w, Tactic.custom(slots));
      // Midfielders: dm + 3 mc + amc/amr at 0.5 = 5.
      _expectStrengths(p, attL: 8, defL: 8, mid: 10.3);
    });

    test('all attack lanes empty never gives NaN', () {
      final w = _worldOn(formationSlots(Formation.f442));
      final p = _build(w, t442(), onPitch: _ids.sublist(0, 5));
      for (final v in [p.mid, p.attL, p.attC, p.attR, p.defL, p.defC, p.defR]) {
        expect(v.isNaN, isFalse);
        expect(v, greaterThan(0));
      }
    });
  });

  test('buildProfile 1000× under 50 ms', () {
    final t = t442()
      ..playmaker = 7
      ..marking = Marking.man
      ..arrows = {6: Arrow.forward};
    final opp = Tactic.preset(Formation.f442)..playmaker = 106;
    _build(w442, t, opponent: opp);
    final sw = Stopwatch()..start();
    var sum = 0.0;
    for (var i = 0; i < 1000; i++) {
      sum += _build(w442, t, opponent: opp).mid;
    }
    sw.stop();
    expect(sum, greaterThan(0));
    expect(sw.elapsedMilliseconds, lessThan(50));
  });

  test('tuning constants match the spec values', () {
    expect(EngineTuning.possessionK1, 0.25);
    expect(EngineTuning.chanceK2, 0.20);
    expect(EngineTuning.chanceBase, closeTo(math.log(0.2 / 0.8), 1e-12));
    expect(EngineTuning.xgBase[ChanceType.penalty], 0.76);
    expect(EngineTuning.xgBase.length, ChanceType.values.length);
    expect(EngineTuning.tenMenMul, 0.85);
    expect(EngineTuning.laneChanceWeights.length, Lane.values.length);
  });
}
