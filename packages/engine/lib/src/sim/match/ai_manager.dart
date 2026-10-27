import '../../core/ids.dart';
import '../../model/enums.dart';
import '../../model/match_result.dart';
import '../../model/match_rules.dart';
import '../../model/player.dart';
import '../../model/tactic.dart';
import '../../model/world.dart';
import 'match_state.dart';
import 'tuning.dart';

/// An in-match order for one side. The AI issues them from [aiDecide], the
/// user through the session; [applyCommand] validates and applies them.
sealed class MatchCommand {
  final ClubId clubId;

  const MatchCommand(this.clubId);
}

/// Bring [inId] on from the bench in the slot [outId] holds — or held, when
/// [outId] was injured off and its slot is still empty. A slot emptied by a
/// sending-off cannot be refilled.
final class Substitute extends MatchCommand {
  final PlayerId outId;
  final PlayerId inId;

  /// Recorded on the event; `injury` is used whenever [outId] was injured
  /// off, whatever is given here.
  final SubReason reason;

  const Substitute(
    super.clubId, {
    required this.outId,
    required this.inId,
    this.reason = SubReason.tactical,
  });
}

final class SetMentality extends MatchCommand {
  final Mentality mentality;

  const SetMentality(super.clubId, this.mentality);
}

/// Replace the side's tactic, slots included; `onPitch[i]` keeps playing
/// slot `i` of the new tactic.
final class SetTactic extends MatchCommand {
  final Tactic tactic;

  const SetTactic(super.clubId, this.tactic);
}

enum CommandErrorKind {
  notOnPitch,
  notOnBench,
  noSubsLeft,
  ineligible,
  sameSide,
  invalidTactic,
}

class CommandError implements Exception {
  final CommandErrorKind kind;
  final String message;

  CommandError(this.kind, this.message);

  @override
  String toString() => 'CommandError($kind): $message';
}

/// Validates [c] (throws [CommandError], leaving [s] untouched) and applies
/// it: mutates the side, appends a [Substitution] or [TacticChange] event
/// and rebuilds the side's profile.
void applyCommand(MatchState s, World w, MatchRules rules, MatchCommand c) {
  final side = s.side(c.clubId);
  switch (c) {
    case Substitute():
      _substitute(s, side, w, rules, c);
    case SetMentality():
      side.tactic = _withMentality(side.tactic, c.mentality);
      _logTactic(s, side);
      s.rebuildProfile(w, side.clubId);
    case SetTactic():
      final t = c.tactic;
      if (t.slots.length != 11 || t.slots[0] != Position.gk) {
        throw CommandError(
          CommandErrorKind.invalidTactic,
          'a tactic needs 11 slots with the goalkeeper first',
        );
      }
      side.tactic = t;
      _logTactic(s, side);
      s.rebuildProfile(w, side.clubId);
      // The opponent's man-marking targets come from this tactic.
      s.rebuildProfile(w, s.opponent(side.clubId).clubId);
  }
}

void _substitute(
  MatchState s,
  SideState side,
  World w,
  MatchRules rules,
  Substitute c,
) {
  if (c.outId == c.inId) {
    throw CommandError(CommandErrorKind.sameSide, '${c.outId} out and in');
  }
  var slot = side.onPitch.indexOf(c.outId);
  final injured = side.injuredOff.contains(c.outId);
  if (slot == -1 && injured) {
    final former = side.formerSlot[c.outId];
    if (former != null && _injuredAt(side, former) == c.outId) slot = former;
  }
  if (slot == -1) {
    throw CommandError(CommandErrorKind.notOnPitch, '${c.outId} not on pitch');
  }
  if (!side.bench.contains(c.inId)) {
    throw CommandError(CommandErrorKind.notOnBench, '${c.inId} not on bench');
  }
  if (side.subsUsed >= rules.substitutions) {
    throw CommandError(CommandErrorKind.noSubsLeft, 'no substitutions left');
  }
  if (w.players[c.inId]!.state.injury != null) {
    throw CommandError(CommandErrorKind.ineligible, '${c.inId} is injured');
  }
  side.onPitch[slot] = c.inId;
  side.bench.remove(c.inId);
  side.subsUsed++;
  s.ratings.putIfAbsent(c.inId, RatingAcc.new);
  s.events.add(
    Substitution(
      minute: s.minute,
      half: s.half,
      clubId: side.clubId,
      outId: c.outId,
      inId: c.inId,
      reason: injured ? SubReason.injury : c.reason,
    ),
  );
  s.rebuildProfile(w, side.clubId);
}

void _logTactic(MatchState s, SideState side) => s.events.add(
  TacticChange(
    minute: s.minute,
    half: s.half,
    clubId: side.clubId,
    mentality: side.tactic.mentality,
  ),
);

/// A copy of [t] with [mentality]; the club's own tactic object is left
/// as it was.
Tactic _withMentality(Tactic t, Mentality mentality) => Tactic(
  name: t.name,
  formation: t.formation,
  slots: t.slots,
  mentality: mentality,
  passing: t.passing,
  tempo: t.tempo,
  width: t.width,
  pressing: t.pressing,
  tackling: t.tackling,
  marking: t.marking,
  offsideTrap: t.offsideTrap,
  counterAttack: t.counterAttack,
  playmaker: t.playmaker,
  targetMan: t.targetMan,
  captain: t.captain,
  viceCaptain: t.viceCaptain,
  setPieces: t.setPieces,
  instructions: t.instructions,
  arrows: t.arrows,
);

/// The injured-off player whose empty slot [i] may be refilled, or null when
/// the slot is occupied or its last occupant was sent off.
PlayerId? _injuredAt(SideState side, int i) {
  if (side.onPitch[i] != null) return null;
  if (side.sentOff.any((id) => side.formerSlot[id] == i)) return null;
  // Latest occupant wins; injuredOff is insertion-ordered.
  PlayerId? found;
  for (final id in side.injuredOff) {
    if (side.formerSlot[id] == i) found = id;
  }
  return found;
}

/// Spec 5.3 step 9 for [side]; the session calls it every
/// [EngineTuning.aiCheckInterval] minutes and after an injury, then applies
/// each command in order. Deterministic: reads state and draws nothing.
///
/// In order: forced substitutes for injured players' empty slots; one
/// mentality step up when behind from [EngineTuning.aiBehindMinute] or down
/// when ahead from [EngineTuning.aiAheadMinute] (each once per match, never
/// for a user-managed side); substitutes for outfield players below
/// [EngineTuning.aiFatigueCondition], most tired first. Substitutes stop
/// when the budget or the bench runs out — the side then plays short.
List<MatchCommand> aiDecide(
  MatchState s,
  SideState side,
  World w,
  MatchRules rules,
) {
  final out = <MatchCommand>[];
  var subsLeft = rules.substitutions - side.subsUsed;
  final bench = [
    for (final id in side.bench)
      if (w.players[id]!.state.injury == null) id,
  ];

  Substitute? sub(PlayerId outId, int slot, SubReason reason) {
    if (subsLeft <= 0) return null;
    final inId = _bestCandidate(w, bench, side.tactic.slots[slot]);
    if (inId == null) return null;
    bench.remove(inId);
    subsLeft--;
    return Substitute(side.clubId, outId: outId, inId: inId, reason: reason);
  }

  for (var i = 0; i < side.onPitch.length; i++) {
    final injured = _injuredAt(side, i);
    if (injured == null) continue;
    final c = sub(injured, i, SubReason.injury);
    if (c != null) out.add(c);
  }

  if (!side.userManaged) {
    final oppGoals = s.opponent(side.clubId).goals;
    final m = side.tactic.mentality;
    if (s.minute >= EngineTuning.aiBehindMinute &&
        side.goals < oppGoals &&
        !side.aiShiftedUp &&
        m != Mentality.veryAttacking) {
      side.aiShiftedUp = true;
      out.add(SetMentality(side.clubId, Mentality.values[m.index + 1]));
    } else if (s.minute >= EngineTuning.aiAheadMinute &&
        side.goals > oppGoals &&
        !side.aiShiftedDown &&
        m != Mentality.veryDefensive) {
      side.aiShiftedDown = true;
      out.add(SetMentality(side.clubId, Mentality.values[m.index - 1]));
    }
  }

  final tired = <(double, int, PlayerId)>[];
  for (var i = 0; i < side.onPitch.length; i++) {
    final id = side.onPitch[i];
    if (id == null || side.tactic.slots[i] == Position.gk) continue;
    final condition = side.condition[id] ?? w.players[id]!.state.condition;
    if (condition < EngineTuning.aiFatigueCondition) {
      tired.add((condition, i, id));
    }
  }
  tired.sort((a, b) {
    final c = a.$1.compareTo(b.$1);
    return c != 0 ? c : a.$2.compareTo(b.$2);
  });
  for (final (_, slot, id) in tired) {
    final c = sub(id, slot, SubReason.fatigue);
    if (c == null) break;
    out.add(c);
  }
  return out;
}

/// The best of [bench] for [pos]: the highest CA among those whose main
/// position is [pos], else among those with familiarity ≥
/// [EngineTuning.aiFamiliarityMin] in it, else of all; null for an empty
/// bench. Ties keep bench order.
PlayerId? _bestCandidate(World w, List<PlayerId> bench, Position pos) {
  PlayerId? best(bool Function(Player) fits) {
    PlayerId? found;
    var ca = -1;
    for (final id in bench) {
      final p = w.players[id]!;
      if (fits(p) && p.ca > ca) {
        found = id;
        ca = p.ca;
      }
    }
    return found;
  }

  return best((p) => p.mainPosition == pos) ??
      best((p) => (p.familiarity[pos] ?? 1) >= EngineTuning.aiFamiliarityMin) ??
      best((_) => true);
}
