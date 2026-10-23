import 'dart:math' as math;

import '../../core/ids.dart';
import '../../core/rng.dart';
import '../../model/enums.dart';
import '../../model/match_log.dart';
import '../../model/match_result.dart';
import '../../model/tactic.dart';
import '../../model/world.dart';
import 'match_state.dart';
import 'team_profile.dart';
import 'tuning.dart';

double _logistic(double x) => 1 / (1 + math.exp(-x));

const _openPlayTypes = [
  ChanceType.throughBall,
  ChanceType.cross,
  ChanceType.longShot,
  ChanceType.dribble,
];

/// One possession step (spec 5.3 steps 1–7). Mutates the clock, possession
/// seconds, stats, goals, events and the pending flags of [s]; returns the
/// step with `micro` empty (Task 10 fills it in detailed mode). [detail] is
/// kept for that; it gates nothing here.
///
/// Draw order on [rng] (fixed; the session's equivalence relies on it):
///  1. owner      — one `nextDouble` against
///                  `bypass / 2 + (1 − bypass) × logistic(k1 × Δ effectiveMid)`
///                  where `bypass` is the mean of both sides' `midBypass`;
///                  skipped when a penalty, corner, free kick or counter is
///                  pending (that side attacks; priority in that order).
///  2. duration   — `nextDouble`: `[stepSecondsMin, stepSecondsMax] / tempoMul`.
///  3. lane       — `weightedIndex` over the attacker's lane weights, always.
///  4. chance     — `nextDouble` against `logistic(k2 × (att − def) + base)`;
///                  on a counter att × `counterAttMul`, def × `counterDefMul`;
///                  skipped (chance certain) for a corner, free kick or
///                  penalty.
///  5. type       — `weightedIndex` over through ball, cross, long shot,
///                  dribble (lane weights × profile weights); none for a set
///                  piece.
///  6. shooter    — `weightedIndex` over the outfield players; none when a
///                  penalty or free kick (`freeKickLeft` for the left lane,
///                  else `freeKickRight`) has a designated taker on the
///                  pitch.
///  7. assister   — `weightedIndex` over the other outfield players for the
///                  types in `assistAttr`; none when a corner has a
///                  designated taker on the pitch.
///  8. trap       — `nextDouble` against `offsideTrapFailProb`, only for a
///                  through ball against an offside trap.
///  9. outcome    — `nextDouble` against the goal / save / block bands.
/// 10. corner     — `nextDouble` against `cornerAfterSave`, only after a save.
/// 11. counter    — `nextDouble` against the defender's `counterProb`, unless
///                  the step ended in a goal or a corner.
PossessionStep resolvePossession(
  MatchState s,
  World w,
  Rng rng, {
  required bool detail,
}) {
  // 1. Owner.
  final SideState att;
  var counter = false;
  ChanceType? setPiece;
  if (s.pendingPenalty != null) {
    att = s.side(s.pendingPenalty!);
    s.pendingPenalty = null;
    setPiece = ChanceType.penalty;
  } else if (s.pendingCorner != null) {
    att = s.side(s.pendingCorner!);
    s.pendingCorner = null;
    setPiece = ChanceType.corner;
  } else if (s.pendingFreeKick != null) {
    att = s.side(s.pendingFreeKick!);
    s.pendingFreeKick = null;
    setPiece = ChanceType.freeKick;
  } else if (s.pendingCounter != null) {
    att = s.side(s.pendingCounter!);
    s.pendingCounter = null;
    counter = true;
  } else {
    final pMid = _logistic(
      EngineTuning.possessionK1 *
          (s.effectiveMid(s.home) - s.effectiveMid(s.away)),
    );
    final bypass = (s.home.profile.midBypass + s.away.profile.midBypass) / 2;
    final pHome = bypass / 2 + (1 - bypass) * pMid;
    att = rng.nextDouble() < pHome ? s.home : s.away;
  }
  final def = s.opponent(att.clubId);

  // 2. Duration.
  final seconds =
      (EngineTuning.stepSecondsMin +
          rng.nextDouble() *
              (EngineTuning.stepSecondsMax - EngineTuning.stepSecondsMin)) /
      att.profile.tempoMul;
  s.clockSeconds += seconds;
  s.minute = s.clockSeconds ~/ 60;
  att.possessionSeconds += seconds;
  s.lastPossession = att.clubId;

  // 3. Lane.
  final lane =
      Lane.values[rng.weightedIndex([
        for (final l in Lane.values) att.profile.laneWeights[l]!,
      ])];
  final step = PossessionStep(
    minute: s.minute,
    half: s.half,
    attackingId: att.clubId,
    lane: lane,
    counter: counter,
    seconds: seconds,
  );

  // 4. Chance.
  final bool chance;
  if (setPiece != null) {
    chance = true;
  } else {
    final a = att.profile.att(lane) * (counter ? att.profile.counterAttMul : 1);
    final d =
        def.profile.def(lane) * (counter ? EngineTuning.counterDefMul : 1);
    chance =
        rng.nextDouble() <
        _logistic(EngineTuning.chanceK2 * (a - d) + EngineTuning.chanceBase);
  }

  var cornerAwarded = false;
  if (chance) {
    // 5. Type.
    final type =
        setPiece ??
        _openPlayTypes[rng.weightedIndex([
          for (final t in _openPlayTypes)
            EngineTuning.laneChanceWeights[lane]![t]! *
                att.profile.chanceWeights[t]!,
        ])];

    // 6. Shooter.
    final outfield = [
      for (final id in att.playing)
        if (att.profile.slotOf[id] != Position.gk) id,
    ];
    final pool = outfield.isEmpty ? att.playing : outfield;
    final takers = att.tactic.setPieces;
    final taker = switch (type) {
      ChanceType.penalty => takers.penalty,
      ChanceType.freeKick =>
        lane == Lane.left ? takers.freeKickLeft : takers.freeKickRight,
      _ => null,
    };
    final PlayerId shooter;
    if (taker != null && pool.contains(taker)) {
      shooter = taker;
    } else {
      final forwardMul = EngineTuning.shooterForwardMul[type] ?? 1.0;
      shooter =
          pool[rng.weightedIndex([
            for (final id in pool)
              _eff(w, att, id, EngineTuning.shooterAttr[type]!) *
                  (att.profile.slotOf[id]?.group == PositionGroup.att
                      ? forwardMul
                      : 1.0) *
                  (att.profile.selectionBoost[id] ?? 1.0),
          ])];
    }

    // 7. Assister.
    PlayerId? assister;
    final assistAttr = EngineTuning.assistAttr[type];
    if (assistAttr != null) {
      final others = [
        for (final id in pool)
          if (id != shooter) id,
      ];
      final cornerTaker = lane == Lane.left
          ? att.tactic.setPieces.cornerLeft
          : att.tactic.setPieces.cornerRight;
      if (type == ChanceType.corner &&
          cornerTaker != null &&
          others.contains(cornerTaker)) {
        assister = cornerTaker;
      } else if (others.isNotEmpty) {
        assister =
            others[rng.weightedIndex([
              for (final id in others)
                _eff(w, att, id, assistAttr) *
                    (att.profile.selectionBoost[id] ?? 1.0),
            ])];
      }
    }

    // xG (5.3 step 6) and 8. the offside trap.
    var xg =
        EngineTuning.xgBase[type]! *
        (1 +
            EngineTuning.finishingCoef *
                (_eff(w, att, shooter, Attr.finishing) +
                    _eff(w, att, shooter, Attr.composure) -
                    20)) *
        (1 - EngineTuning.keeperCoef * (def.profile.gk - 10));
    if (type == ChanceType.throughBall && def.profile.throughBallXgMul < 1) {
      xg *= rng.nextDouble() < EngineTuning.offsideTrapFailProb
          ? EngineTuning.offsideTrapFailMul
          : def.profile.throughBallXgMul;
    }
    xg = xg.clamp(0.0, EngineTuning.xgMax);

    // 9. Outcome: keeper errors move the bottom of the save band into goals.
    final r = rng.nextDouble();
    final goalBand =
        xg + EngineTuning.saveBand * (1 - 1 / def.profile.keeperErrorMul);
    final savedBand = xg + EngineTuning.saveBand;
    final blockedBand = savedBand + EngineTuning.blockBand;
    final postFrom =
        blockedBand - EngineTuning.blockBand * EngineTuning.postShare;
    final outcome = r < goalBand
        ? ShotOutcome.goal
        : r < savedBand
        ? ShotOutcome.saved
        : r < postFrom
        ? ShotOutcome.blocked
        : r < blockedBand
        ? ShotOutcome.post
        : ShotOutcome.off;

    step
      ..chance = type
      ..shooter = shooter
      ..assister = assister
      ..xg = xg
      ..outcome = outcome;
    final stats = att.stats;
    stats.shots++;
    stats.xg += xg;
    switch (outcome) {
      case ShotOutcome.goal:
        stats.onTarget++;
        att.goals++;
        _emit(
          s,
          step,
          Goal(
            minute: s.minute,
            half: s.half,
            clubId: att.clubId,
            scorerId: shooter,
            assistId: assister,
            type: type,
            isPenalty: type == ChanceType.penalty,
          ),
        );
      case ShotOutcome.saved:
        stats.onTarget++;
        // 10. Corner.
        if (rng.nextDouble() < EngineTuning.cornerAfterSave) {
          s.pendingCorner = att.clubId;
          stats.corners++;
          cornerAwarded = true;
        }
      case ShotOutcome.blocked:
        stats.blocked++;
      case ShotOutcome.post || ShotOutcome.off:
        break;
    }
    if (type == ChanceType.penalty && outcome != ShotOutcome.goal) {
      _emit(
        s,
        step,
        PenaltyMissed(
          minute: s.minute,
          half: s.half,
          clubId: att.clubId,
          playerId: shooter,
          outcome: outcome,
        ),
      );
    }
  }

  // 11. Counter.
  if (step.outcome != ShotOutcome.goal &&
      !cornerAwarded &&
      rng.nextDouble() < def.profile.counterProb) {
    s.pendingCounter = def.clubId;
  }
  return step;
}

/// [id]'s effective [a] in its slot at its match condition.
double _eff(World w, SideState side, PlayerId id, Attr a) {
  final p = w.players[id]!;
  return playerEffectiveness(
    p,
    a,
    side.profile.slotOf[id] ?? p.mainPosition,
    condition: side.condition[id],
  );
}

void _emit(MatchState s, PossessionStep step, MatchEvent e) {
  s.events.add(e);
  step.events.add(e);
}
