import 'package:engine/engine.dart';
import 'package:test/test.dart';

import 'match_helpers.dart';

/// Draw script for a home open-play chance: owner → home, duration 60 s,
/// centre lane, chance, through ball, shooter = first outfield player (2),
/// assister = next (3), then [outcome] and the trailing [tail] draws.
List<double> homeThroughBall(double outcome, [List<double> tail = const []]) =>
    [0.0, 0.5, 0.5, 0.0, 0.0, 0.0, 0.0, outcome, ...tail];

void main() {
  group('MatchState.start', () {
    test('seeds sides, conditions, profiles and ratings', () {
      final w = uniformWorld();
      w.players[7]!.state.condition = 80;
      final s = startMatch(w, cond: conditions(homeAdvantage: 1.06));
      expect(s.home.clubId, 1);
      expect(s.away.clubId, 2);
      expect(s.home.onPitch, homeIds);
      expect(s.away.onPitch, awayIds);
      expect(s.home.playing, homeIds);
      expect(s.home.condition[7], 80);
      expect(s.home.condition[1], 100);
      expect(
        s.home.profile.mid,
        closeTo(10 * 1.06 * (80 / 100 * 0.5 + 0.5 + 3) / 4, 1e-9),
      );
      expect(s.away.profile.mid, closeTo(10, 1e-9));
      expect(s.minute, 0);
      expect(s.half, 1);
      expect(s.clockSeconds, 0);
      expect(s.events, isEmpty);
      expect(s.log, isNull);
      expect(s.ratings.length, 22);
      expect(s.ratings[7]!.value, 6.0);
      expect(s.side(2), same(s.away));
      expect(s.opponent(2), same(s.home));
      expect(s.home.stats.shots, 0);
      expect(s.rules, MatchRules.league);
    });

    test('effectiveMid applies the opponent pressing to our mid', () {
      final w = uniformWorld();
      final s = startMatch(
        w,
        awayTactic: Tactic.preset(Formation.f442)..pressing = Pressing.high,
      );
      expect(s.effectiveMid(s.home), closeTo(9.2, 1e-9));
      expect(s.effectiveMid(s.away), closeTo(10, 1e-9));
    });

    test('rebuildProfile reads null slots as empty', () {
      final w = uniformWorld();
      final s = startMatch(w);
      s.home.onPitch[10] = null;
      s.rebuildProfile(w, 1);
      expect(s.home.profile.mid, closeTo(8.5, 1e-9));
      expect(s.home.profile.onPitch, homeIds.sublist(0, 10));
      expect(s.home.playing, homeIds.sublist(0, 10));
    });
  });

  group('resolvePossession', () {
    test('favours the side with the higher mid', () {
      final w = uniformWorld(homeAttr: 15);
      final s = startMatch(w);
      final rng = SeededRng(3);
      var home = 0;
      for (var i = 0; i < 2000; i++) {
        final step = resolvePossession(s, w, rng, detail: false);
        if (step.attackingId == 1) home++;
      }
      expect(home / 2000, greaterThan(0.6));
    });

    test('equal sides: open-play chance rate ≈ 0.20', () {
      final w = uniformWorld();
      final s = startMatch(w);
      final rng = SeededRng(11);
      var open = 0;
      var chances = 0;
      for (var i = 0; i < 10000; i++) {
        final step = resolvePossession(s, w, rng, detail: false);
        if (step.counter || step.chance == ChanceType.corner) continue;
        open++;
        if (step.chance != null) chances++;
      }
      expect(chances / open, closeTo(0.20, 0.02));
    });

    test('step fields, clock and possession seconds', () {
      final w = uniformWorld();
      final s = startMatch(w);
      final step = resolvePossession(
        s,
        w,
        ScriptedRng(homeThroughBall(0.99, [0.99])),
        detail: false,
      );
      expect(step.attackingId, 1);
      expect(step.lane, Lane.centre);
      expect(step.counter, isFalse);
      expect(step.seconds, 60);
      expect(step.minute, 1);
      expect(step.half, 1);
      expect(step.chance, ChanceType.throughBall);
      expect(step.shooter, 2);
      expect(step.assister, 3);
      expect(step.xg, closeTo(0.30, 1e-9));
      expect(step.outcome, ShotOutcome.off);
      expect(step.micro, isEmpty);
      expect(step.events, isEmpty);
      expect(s.clockSeconds, 60);
      expect(s.minute, 1);
      expect(s.home.possessionSeconds, 60);
      expect(s.away.possessionSeconds, 0);
      expect(s.lastPossession, 1);
      expect(s.home.stats.shots, 1);
      expect(s.home.stats.onTarget, 0);
      expect(s.home.stats.xg, closeTo(0.30, 1e-9));
    });

    test('fast tempo shortens the step', () {
      final w = uniformWorld();
      final s = startMatch(
        w,
        homeTactic: Tactic.preset(Formation.f442)..tempo = Tempo.fast,
      );
      // No chance (draw 0.99), no counter (0.99).
      resolvePossession(
        s,
        w,
        ScriptedRng([0.0, 0.5, 0.5, 0.99, 0.99]),
        detail: false,
      );
      expect(s.clockSeconds, closeTo(60 / 1.3, 1e-9));
      expect(s.minute, 0);
    });

    test('xG: finishing, composure and the keeper (spec 5.3 step 6)', () {
      final w = uniformWorld();
      w.players[2]!.attrs
        ..set(Attr.finishing, 15)
        ..set(Attr.composure, 15);
      final s = startMatch(w);
      final a = resolvePossession(
        s,
        w,
        ScriptedRng(homeThroughBall(0.99, [0.99])),
        detail: false,
      );
      expect(a.xg, closeTo(0.30 * 1.2, 1e-9));

      for (final attr in [
        Attr.reflexes,
        Attr.oneOnOnes,
        Attr.handling,
        Attr.positioning,
      ]) {
        w.players[101]!.attrs.set(attr, 15);
      }
      s.rebuildProfile(w, 2);
      final b = resolvePossession(
        s,
        w,
        ScriptedRng(homeThroughBall(0.99, [0.99])),
        detail: false,
      );
      expect(b.xg, closeTo(0.30 * 1.2 * (1 - 0.015 * 5), 1e-9));
    });

    test('xG uses the shooter condition and is capped', () {
      final w = uniformWorld();
      w.players[2]!.attrs
        ..set(Attr.finishing, 20)
        ..set(Attr.composure, 20);
      final s = startMatch(w);
      s.home.condition[2] = 50;
      final a = resolvePossession(
        s,
        w,
        ScriptedRng(homeThroughBall(0.99, [0.99])),
        detail: false,
      );
      // Effective 15 + 15 at condition 50.
      expect(a.xg, closeTo(0.30 * 1.2, 1e-9));

      s.pendingPenalty = 1;
      s.home.condition[2] = 100;
      // Penalty: no owner or chance draw; taker drawn (0.0 → 2).
      final b = resolvePossession(
        s,
        w,
        ScriptedRng([0.5, 0.5, 0.0, 0.99, 0.99, 0.99]),
        detail: false,
      );
      expect(b.chance, ChanceType.penalty);
      expect(b.shooter, 2);
      expect(b.xg, EngineTuning.xgMax);
    });

    test('outcome bands at xG 0.30', () {
      final expected = {
        0.29: ShotOutcome.goal,
        0.31: ShotOutcome.saved,
        0.54: ShotOutcome.saved,
        0.56: ShotOutcome.blocked,
        0.71: ShotOutcome.blocked,
        0.73: ShotOutcome.post,
        0.76: ShotOutcome.off,
      };
      for (final MapEntry(key: r, value: outcome) in expected.entries) {
        final w = uniformWorld();
        final s = startMatch(w);
        final tail = outcome == ShotOutcome.saved ? [0.99, 0.99] : [0.99];
        final step = resolvePossession(
          s,
          w,
          ScriptedRng(homeThroughBall(r, tail)),
          detail: false,
        );
        expect(step.outcome, outcome, reason: 'r = $r');
        expect(s.home.stats.shots, 1);
        expect(
          s.home.stats.onTarget,
          outcome == ShotOutcome.goal || outcome == ShotOutcome.saved ? 1 : 0,
        );
        expect(s.home.stats.blocked, outcome == ShotOutcome.blocked ? 1 : 0);
        expect(s.home.goals, outcome == ShotOutcome.goal ? 1 : 0);
      }
    });

    test('a goal appends a Goal event to the state and the step', () {
      final w = uniformWorld();
      final s = startMatch(w);
      final step = resolvePossession(
        s,
        w,
        ScriptedRng(homeThroughBall(0.1)),
        detail: false,
      );
      expect(s.events, hasLength(1));
      expect(step.events, hasLength(1));
      final g = s.events.single as Goal;
      expect(g.clubId, 1);
      expect(g.scorerId, 2);
      expect(g.assistId, 3);
      expect(g.type, ChanceType.throughBall);
      expect(g.isPenalty, isFalse);
      expect(g.minute, 1);
      expect(g.half, 1);
      expect(s.home.goals, 1);
      expect(s.pendingCounter, isNull);
    });

    test('a wet keeper turns part of the save band into goals', () {
      final w = uniformWorld();
      final s = startMatch(
        w,
        cond: const MatchConditions(
          weather: Weather.rainy,
          pitch: 8,
          attendance: 1,
          homeAdvantage: 1.0,
        ),
      );
      // Saved band shrinks by 0.25 × (1 − 1/1.3) ≈ 0.058 above xG; the
      // away keeper's error multiplier applies to home shots.
      final step = resolvePossession(
        s,
        w,
        ScriptedRng(homeThroughBall(0.34)),
        detail: false,
      );
      expect(step.outcome, ShotOutcome.goal);
    });

    test('a save gives a corner 30 % of the time; the corner follows', () {
      final w = uniformWorld();
      final s = startMatch(w);
      resolvePossession(
        s,
        w,
        ScriptedRng(homeThroughBall(0.4, [0.1])),
        detail: false,
      );
      expect(s.pendingCorner, 1);
      expect(s.home.stats.corners, 1);

      // Corner: no owner or chance draw; duration, lane, shooter, assister,
      // outcome, counter.
      final rng = ScriptedRng([0.5, 0.1, 0.0, 0.0, 0.99, 0.99]);
      final corner = resolvePossession(s, w, rng, detail: false);
      expect(corner.attackingId, 1);
      expect(corner.chance, ChanceType.corner);
      expect(corner.lane, Lane.left);
      expect(corner.xg, closeTo(0.08, 1e-9));
      expect(corner.shooter, 2);
      expect(corner.assister, 3);
      expect(s.pendingCorner, isNull);
      expect(s.home.stats.shots, 2);
      expect(rng.used, 6);

      final t = startMatch(w);
      resolvePossession(
        t,
        w,
        ScriptedRng(homeThroughBall(0.4, [0.5, 0.99])),
        detail: false,
      );
      expect(t.pendingCorner, isNull);
      expect(t.home.stats.corners, 0);
    });

    test('a lost possession gives the other side a counter 15 %', () {
      final w = uniformWorld();
      final s = startMatch(w);
      resolvePossession(
        s,
        w,
        ScriptedRng(homeThroughBall(0.99, [0.1])),
        detail: false,
      );
      expect(s.pendingCounter, 2);

      final counter = resolvePossession(
        s,
        w,
        ScriptedRng([0.5, 0.5, 0.99, 0.99]),
        detail: false,
      );
      expect(counter.attackingId, 2);
      expect(counter.counter, isTrue);
      expect(counter.chance, isNull);
      expect(s.pendingCounter, isNull);

      // A no-chance step also rolls the counter.
      final t = startMatch(w);
      resolvePossession(
        t,
        w,
        ScriptedRng([0.0, 0.5, 0.5, 0.99, 0.1]),
        detail: false,
      );
      expect(t.pendingCounter, 2);
    });

    test('a counter softens the defence ×0.8 (chance rate rises)', () {
      final w = uniformWorld();
      final s = startMatch(w);
      final rng = SeededRng(5);
      var counters = 0;
      var chances = 0;
      for (var i = 0; i < 20000; i++) {
        final step = resolvePossession(s, w, rng, detail: false);
        if (!step.counter) continue;
        counters++;
        if (step.chance != null) chances++;
      }
      // logistic(0.2 × (10 − 8) − 1.386) ≈ 0.27.
      expect(counters, greaterThan(1000));
      expect(chances / counters, closeTo(0.27, 0.03));
    });

    test('long ball bypasses the midfield contest', () {
      final w = uniformWorld(homeAttr: 15);
      Tactic style(PassingStyle p) =>
          Tactic.preset(Formation.f442)..passing = p;
      // Both long ball: 30 % of possessions are a coin flip; both short: none.
      final s = startMatch(
        w,
        homeTactic: style(PassingStyle.longBall),
        awayTactic: style(PassingStyle.longBall),
      );
      final t = startMatch(
        w,
        homeTactic: style(PassingStyle.short),
        awayTactic: style(PassingStyle.short),
      );
      final rngS = SeededRng(3);
      final rngT = SeededRng(4);
      var homeS = 0;
      var homeT = 0;
      for (var i = 0; i < 10000; i++) {
        if (resolvePossession(s, w, rngS, detail: false).attackingId == 1) {
          homeS++;
        }
        if (resolvePossession(t, w, rngT, detail: false).attackingId == 1) {
          homeT++;
        }
      }
      expect(homeS, lessThan(homeT - 500));
    });

    test('penalty: the designated taker shoots without a draw', () {
      final w = uniformWorld();
      final s = startMatch(
        w,
        homeTactic: Tactic.preset(Formation.f442)
          ..setPieces = SetPieceTakers(penalty: 10),
      );
      s.pendingPenalty = 1;
      // Duration, lane, outcome (0.76 + 0.25 covers every miss: saved),
      // corner, counter.
      final rng = ScriptedRng([0.5, 0.5, 0.99, 0.99, 0.99]);
      final step = resolvePossession(s, w, rng, detail: false);
      expect(step.chance, ChanceType.penalty);
      expect(step.shooter, 10);
      expect(step.assister, isNull);
      expect(step.xg, closeTo(0.76, 1e-9));
      expect(step.outcome, ShotOutcome.saved);
      expect(s.pendingPenalty, isNull);
      final missed = s.events.single as PenaltyMissed;
      expect(missed.playerId, 10);
      expect(missed.outcome, ShotOutcome.saved);
      expect(s.home.stats.onTarget, 1);
      expect(rng.used, 5);

      s.pendingPenalty = 1;
      final goal = resolvePossession(
        s,
        w,
        ScriptedRng([0.5, 0.5, 0.1]),
        detail: false,
      );
      expect(goal.outcome, ShotOutcome.goal);
      expect((s.events.last as Goal).isPenalty, isTrue);
    });

    test('free kick: the lane taker shoots, else a long-shots draw', () {
      final w = uniformWorld();
      final s = startMatch(
        w,
        homeTactic: Tactic.preset(Formation.f442)
          ..setPieces = SetPieceTakers(freeKickLeft: 7, freeKickRight: 8),
      );
      s.pendingFreeKick = 1;
      // Duration, lane 0.1 (left), outcome 0.99 (off), counter 0.99.
      final rng = ScriptedRng([0.5, 0.1, 0.99, 0.99]);
      final left = resolvePossession(s, w, rng, detail: false);
      expect(left.chance, ChanceType.freeKick);
      expect(left.lane, Lane.left);
      expect(left.shooter, 7);
      expect(left.assister, isNull);
      expect(left.xg, closeTo(0.07, 1e-9));
      expect(left.outcome, ShotOutcome.off);
      expect(s.pendingFreeKick, isNull);
      expect(s.home.stats.shots, 1);
      expect(rng.used, 4);

      s.pendingFreeKick = 1;
      final centre = resolvePossession(
        s,
        w,
        ScriptedRng([0.5, 0.5, 0.99, 0.99]),
        detail: false,
      );
      expect(centre.lane, Lane.centre);
      expect(centre.shooter, 8);

      // No taker on the pitch: shooter drawn (0.0 → 2).
      s.home.onPitch[7] = null;
      s.pendingFreeKick = 1;
      final drawn = resolvePossession(
        s,
        w,
        ScriptedRng([0.5, 0.5, 0.0, 0.99, 0.99]),
        detail: false,
      );
      expect(drawn.shooter, 2);
    });

    test('pending set pieces resolve penalty, corner, free kick, counter', () {
      final w = uniformWorld();
      final s = startMatch(w);
      s.pendingPenalty = 1;
      s.pendingCorner = 2;
      s.pendingFreeKick = 1;
      s.pendingCounter = 2;
      ChanceType? next() => resolvePossession(
        s,
        w,
        ScriptedRng([0.5, 0.5, 0.0, 0.99, 0.99, 0.99, 0.99]),
        detail: false,
      ).chance;
      expect(next(), ChanceType.penalty);
      expect(next(), ChanceType.corner);
      expect(next(), ChanceType.freeKick);
      final counter = resolvePossession(
        s,
        w,
        ScriptedRng([0.5, 0.5, 0.99, 0.99]),
        detail: false,
      );
      expect(counter.counter, isTrue);
      expect(counter.attackingId, 2);
    });

    test('offside trap: through-ball xG ×0.75, or ×1.6 when it fails', () {
      final w = uniformWorld();
      final s = startMatch(
        w,
        awayTactic: Tactic.preset(Formation.f442)..offsideTrap = true,
      );
      // Trap roll sits between the assister and outcome draws.
      final held = resolvePossession(
        s,
        w,
        ScriptedRng([0.0, 0.5, 0.5, 0.0, 0.0, 0.0, 0.0, 0.5, 0.99, 0.99]),
        detail: false,
      );
      expect(held.xg, closeTo(0.30 * 0.75, 1e-9));
      final beaten = resolvePossession(
        s,
        w,
        ScriptedRng([0.0, 0.5, 0.5, 0.0, 0.0, 0.0, 0.0, 0.05, 0.99, 0.99]),
        detail: false,
      );
      expect(beaten.xg, closeTo(0.30 * 1.6, 1e-9));
    });

    test('shooter and assister pools skip the keeper and empty slots', () {
      final w = uniformWorld();
      final s = startMatch(w);
      s.home.onPitch[1] = null;
      s.home.onPitch[2] = null;
      final step = resolvePossession(
        s,
        w,
        ScriptedRng(homeThroughBall(0.99, [0.99])),
        detail: false,
      );
      expect(step.shooter, 4);
      expect(step.assister, 5);
    });

    test('shooter weights: forwards ×3 on through balls', () {
      final w = uniformWorld();
      final s = startMatch(w);
      final rng = SeededRng(9);
      var forwards = 0;
      var shots = 0;
      for (var i = 0; i < 20000; i++) {
        final step = resolvePossession(s, w, rng, detail: false);
        if (step.chance != ChanceType.throughBall) continue;
        shots++;
        final id = step.shooter!;
        final slot = s.side(step.attackingId).profile.slotOf[id];
        if (slot == Position.st) forwards++;
      }
      // Two strikers at ×3 among ten outfield players: 6 / 14.
      expect(forwards / shots, closeTo(6 / 14, 0.04));
    });

    test('a dribble has no assister', () {
      final w = uniformWorld();
      final s = startMatch(w);
      // Centre weights: through 1.4, cross 0.5, long 1.3, dribble 0.9 → 0.95.
      final step = resolvePossession(
        s,
        w,
        ScriptedRng([0.0, 0.5, 0.5, 0.0, 0.95, 0.0, 0.99, 0.99]),
        detail: false,
      );
      expect(step.chance, ChanceType.dribble);
      expect(step.shooter, 2);
      expect(step.assister, isNull);
    });
  });
}
