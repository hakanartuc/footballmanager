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
/// deltas), one injury exposure, and condition drain. Events go to both `s.events` and `step.events`; a
/// sent-off or injured player leaves the pitch (slot nulled) but the
/// profile is not rebuilt here — the session does that.
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
  if (rng.nextDouble() < EngineTuning.foulPerStep * def.profile.foulMul) {
    final defenders = def.playing;
    final fouler =
        defenders[rng.weightedIndex([
          for (final id in defenders)
            w.players[id]!.attrs[Attr.aggression].toDouble(),
        ])];
    fouled = rng.pick(att.playing);
    def.stats.fouls++;

    final r = rng.nextDouble();
    final cardMul = def.profile.cardMul;
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
    for (final id in side.playing) {
      ids.add(id);
      sides.add(side);
      weights.add(_injuryWeight(w, side, opp, id, fouled: id == fouled));
    }
  }
  if (ids.isNotEmpty) {
    final mean = weights.fold(0.0, (a, b) => a + b) / weights.length;
    if (rng.nextDouble() < EngineTuning.injuryPerStep * mean) {
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
  for (final side in [s.home, s.away]) {
    for (final id in side.playing) {
      final drop =
          minutes *
          EngineTuning.drainPerMinute(w.players[id]!.attrs[Attr.stamina]) *
          side.profile.conditionDrain;
      side.condition[id] = math.max(0.0, (side.condition[id] ?? 100) - drop);
    }
  }
}

/// Spec 6.1 multipliers for [id] of [side] against [opp].
double _injuryWeight(
  World w,
  SideState side,
  SideState opp,
  PlayerId id, {
  required bool fouled,
}) {
  final p = w.players[id]!;
  final condition = side.condition[id] ?? p.state.condition;
  final proneness =
      EngineTuning.injuryPronenessMin +
      (EngineTuning.injuryPronenessMax - EngineTuning.injuryPronenessMin) *
          (p.hidden.injuryProneness - 1) /
          19;
  final conditionMul = condition < EngineTuning.injuryVeryLowCondition
      ? EngineTuning.injuryVeryLowConditionMul
      : condition < EngineTuning.injuryLowCondition
      ? EngineTuning.injuryLowConditionMul
      : 1.0;
  return proneness *
      conditionMul *
      (p.ageAt(w.date) > EngineTuning.injuryOldAge
          ? EngineTuning.injuryOldAgeMul
          : 1.0) *
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
