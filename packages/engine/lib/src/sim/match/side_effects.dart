import 'dart:math' as math;

import '../../core/ids.dart';
import '../../core/rng.dart';
import '../../model/enums.dart';
import '../../model/match_log.dart';
import '../../model/match_result.dart';
import '../../model/tactic.dart';
import '../../model/world.dart';
import 'injury_table.dart';
import 'match_state.dart';
import 'ratings.dart';
import 'tuning.dart';

/// Spec 5.3 step 8 after [step]: foul and cards (with their rating
/// deltas), one injury exposure, and condition drain (× `extraTimeDrainMul`
/// in extra time). Events go to both `s.events` and `step.events`; a foul
/// sets `step.fouler` and `step.fouled`; a sent-off or injured player
/// leaves the pitch (slot nulled) but the profile is not rebuilt here —
/// the session does that.
///
/// Draw order on [rng]:
///  1. foul      — `nextDouble` against `foulPerStep × foulMul` (defender).
///     2. fouler — `weightedIndex` by aggression over the defenders.
///     3. victim — `pick` over the attackers.
///     4. card   — `nextDouble`: red below `redPerFoul × cardMul`, yellow
///                 below `(redPerFoul + yellowPerFoul) × cardMul`.
///     5. reason — straight red only: violent / last man / normal shares.
///     6. box    — `nextDouble` against `boxFoulShare` → pending penalty.
///     7. free kick — only when not in the box: `nextDouble` against
///                 `freeKickShare` → pending free kick. Either set piece
///                 clears a pending counter.
///  8. injury    — `nextDouble` against `injuryPerStep × mean(weights)` over
///                 everyone on the pitch (home first, slot order).
///     9. victim — `weightedIndex` over those weights.
///    10. table  — `rollInjury` (band, days, type).
void applySideEffects(MatchState s, PossessionStep step, World w, Rng rng) {
  final att = s.side(step.attackingId);
  final def = s.opponent(step.attackingId);

  PlayerId? fouled;
  final pFoul = EngineTuning.foulPerStep * def.profile.foulMul;
  assert(pFoul >= 0 && pFoul <= 1, 'pFoul $pFoul');
  if (rng.nextDouble() < pFoul) {
    final defenders = def.playing;
    final fouler =
        defenders[rng.weightedIndex([
          for (final id in defenders)
            w.players[id]!.attrs[Attr.aggression].toDouble(),
        ])];
    fouled = rng.pick(att.playing);
    step
      ..fouler = fouler
      ..fouled = fouled;
    def.stats.fouls++;

    final r = rng.nextDouble();
    final cardMul = def.profile.cardMul;
    assert(
      EngineTuning.redPerFoul * cardMul >= 0 &&
          (EngineTuning.redPerFoul + EngineTuning.yellowPerFoul) * cardMul <= 1,
      'card bands at cardMul $cardMul',
    );
    if (r < EngineTuning.redPerFoul * cardMul) {
      final q = rng.nextDouble();
      final reason = q < EngineTuning.redViolentShare
          ? FoulKind.violent
          : q < EngineTuning.redViolentShare + EngineTuning.redLastManShare
          ? FoulKind.lastMan
          : FoulKind.normal;
      _book(s, step, def, fouler, CardKind.red, reason);
      _sendOff(def, fouler);
    } else if (r <
        (EngineTuning.redPerFoul + EngineTuning.yellowPerFoul) * cardMul) {
      final n = (def.yellows[fouler] ?? 0) + 1;
      def.yellows[fouler] = n;
      def.stats.yellows++;
      if (n >= 2) {
        _book(s, step, def, fouler, CardKind.secondYellow, FoulKind.normal);
        _sendOff(def, fouler);
      } else {
        _book(s, step, def, fouler, CardKind.yellow, FoulKind.normal);
      }
    }
    assert(
      EngineTuning.boxFoulShare >= 0 &&
          EngineTuning.boxFoulShare <= 1 &&
          EngineTuning.freeKickShare >= 0 &&
          EngineTuning.freeKickShare <= 1,
    );
    if (rng.nextDouble() < EngineTuning.boxFoulShare) {
      s.pendingPenalty = att.clubId;
      s.pendingCounter = null;
    } else if (rng.nextDouble() < EngineTuning.freeKickShare) {
      s.pendingFreeKick = att.clubId;
      s.pendingCounter = null;
    }
  }

  // One injury exposure per step, shared by everyone on the pitch.
  final ids = <PlayerId>[];
  final sides = <SideState>[];
  final weights = <double>[];
  for (final side in [s.home, s.away]) {
    final opp = s.opponent(side.clubId);
    for (final id in side.onPitch) {
      if (id == null) continue;
      ids.add(id);
      sides.add(side);
      weights.add(_injuryWeight(w, side, opp, id, fouled: id == fouled));
    }
  }
  if (ids.isNotEmpty) {
    final mean = weights.fold(0.0, (a, b) => a + b) / weights.length;
    final pInjury = EngineTuning.injuryPerStep * mean;
    assert(pInjury >= 0 && pInjury <= 1, 'pInjury $pInjury');
    if (rng.nextDouble() < pInjury) {
      final i = rng.weightedIndex(weights);
      final id = ids[i];
      final side = sides[i];
      final inj = rollInjury(rng, fromFoul: id == fouled);
      _emit(
        s,
        step,
        Injury(
          minute: s.minute,
          half: s.half,
          clubId: side.clubId,
          playerId: id,
          injury: inj,
        ),
      );
      side.injuredOff.add(id);
      side.removeFromPitch(id);
    }
  }

  final minutes = step.seconds / 60;
  final extraTimeMul = s.extraTime ? EngineTuning.extraTimeDrainMul : 1.0;
  for (final side in [s.home, s.away]) {
    for (final id in side.onPitch) {
      if (id == null) continue;
      final drop =
          minutes *
          _consts(w, side, id).drain *
          side.profile.conditionDrain *
          extraTimeMul;
      side.condition[id] = math.max(0.0, (side.condition[id] ?? 100) - drop);
    }
  }
}

/// [id]'s match constants, computed on the spot for a player who was in
/// neither the starters nor the bench.
PlayerMatchConsts _consts(World w, SideState side, PlayerId id) =>
    side.consts[id] ?? playerMatchConsts(w, w.players[id]!);

/// Spec 6.1 multipliers for [id] of [side] against [opp].
double _injuryWeight(
  World w,
  SideState side,
  SideState opp,
  PlayerId id, {
  required bool fouled,
}) {
  final c = _consts(w, side, id);
  final condition = side.condition[id] ?? w.players[id]!.state.condition;
  final conditionMul = condition < EngineTuning.injuryVeryLowCondition
      ? EngineTuning.injuryVeryLowConditionMul
      : condition < EngineTuning.injuryLowCondition
      ? EngineTuning.injuryLowConditionMul
      : 1.0;
  return c.proneness *
      conditionMul *
      (c.old ? EngineTuning.injuryOldAgeMul : 1.0) *
      (side.tactic.tempo == Tempo.fast
          ? EngineTuning.injuryFastTempoMul
          : 1.0) *
      side.profile.injuryMul *
      opp.profile.injuryToOpponentMul *
      (fouled ? EngineTuning.injuryFoulVictimMul : 1.0);
}

/// Emits the [Booking] and credits [id] a yellow, or a red for a second
/// yellow or a straight red.
void _book(
  MatchState s,
  PossessionStep step,
  SideState side,
  PlayerId id,
  CardKind kind,
  FoulKind reason,
) {
  _emit(
    s,
    step,
    Booking(
      minute: s.minute,
      half: s.half,
      clubId: side.clubId,
      playerId: id,
      kind: kind,
      reason: reason,
    ),
  );
  creditRating(
    s,
    id,
    kind == CardKind.yellow ? RatingEvent.yellow : RatingEvent.red,
  );
}

void _sendOff(SideState side, PlayerId id) {
  side.stats.reds++;
  side.sentOff.add(id);
  side.removeFromPitch(id);
}

void _emit(MatchState s, PossessionStep step, MatchEvent e) {
  s.events.add(e);
  step.events.add(e);
}
