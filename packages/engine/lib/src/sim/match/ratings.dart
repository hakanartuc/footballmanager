import '../../core/ids.dart';
import '../../model/enums.dart';
import '../../model/match_result.dart';
import 'match_state.dart';
import 'tuning.dart';

/// Something a player did that moves their match rating (spec 5.3).
enum RatingEvent {
  goal(EngineTuning.ratingGoal),
  assist(EngineTuning.ratingAssist),

  /// A save by the keeper.
  save(EngineTuning.ratingSave),

  /// A possession step lost; no producer yet (no step names the player
  /// who lost the ball).
  possessionLost(EngineTuning.ratingPossessionLost),

  /// A keeper error that turned a save into a goal.
  criticalError(EngineTuning.ratingCriticalError),
  yellow(EngineTuning.ratingYellow),

  /// A straight red or a second yellow.
  red(EngineTuning.ratingRed);

  const RatingEvent(this.delta);

  final double delta;
}

/// Adds [e]'s delta to [id]'s running rating.
void creditRating(MatchState s, PlayerId id, RatingEvent e) =>
    s.ratings.putIfAbsent(id, RatingAcc.new).value += e.delta;

/// Full-time pass over [s.ratings], once (later calls do nothing):
/// [EngineTuning.ratingWinBonus] to everyone of the winning side who
/// played, sent-off and injured players included;
/// [EngineTuning.ratingCleanSheetBonus] to the players of keeper and
/// defence slots (the current tactic's slots) of a side that conceded
/// nothing; players with fewer than [EngineTuning.ratingMinMinutes] are
/// removed; the rest are clamped to 1..10 and rounded to one decimal.
///
/// Minutes come from `s.events`: a substitute starts at its
/// [Substitution]; a player stops at the first of being substituted, a
/// red [Booking] or an [Injury] that took them off; otherwise at
/// `s.minute`.
void finaliseRatings(MatchState s) {
  if (s.ratingsFinalised) return;
  s.ratingsFinalised = true;

  final on = <PlayerId, int>{};
  final off = <PlayerId, int>{};
  for (final e in s.events) {
    switch (e) {
      case Substitution():
        on.putIfAbsent(e.inId, () => e.minute);
        off.putIfAbsent(e.outId, () => e.minute);
      case Booking(kind: CardKind.red || CardKind.secondYellow):
        off.putIfAbsent(e.playerId, () => e.minute);
      case Injury() when s.side(e.clubId).injuredOff.contains(e.playerId):
        off.putIfAbsent(e.playerId, () => e.minute);
      default:
        break;
    }
  }

  for (final side in [s.home, s.away]) {
    final opp = s.opponent(side.clubId);
    final won = side.goals > opp.goals;
    final cleanSheet = opp.goals == 0;
    final slots = _slots(s, side);
    for (final MapEntry(key: id, value: acc) in s.ratings.entries) {
      if (!side.condition.containsKey(id)) continue;
      if (won) acc.value += EngineTuning.ratingWinBonus;
      final slot = slots[id];
      final group = slot == null ? null : side.tactic.slots[slot].group;
      if (cleanSheet &&
          (group == PositionGroup.gk || group == PositionGroup.def)) {
        acc.value += EngineTuning.ratingCleanSheetBonus;
      }
    }
  }

  s.ratings.removeWhere(
    (id, _) =>
        (off[id] ?? s.minute) - (on[id] ?? 0) < EngineTuning.ratingMinMinutes,
  );
  for (final acc in s.ratings.values) {
    final v = acc.value.clamp(EngineTuning.ratingMin, EngineTuning.ratingMax);
    acc.value = (v * 10).round() / 10;
  }
}

/// The slot index each player of [side] last held: the pitch, then
/// [SideState.formerSlot], then (walking substitutions backwards) the
/// slot of whoever replaced a substituted player.
Map<PlayerId, int> _slots(MatchState s, SideState side) {
  final slot = <PlayerId, int>{
    ...side.formerSlot,
    for (var i = 0; i < side.onPitch.length; i++) ?side.onPitch[i]: i,
  };
  for (final e in s.events.reversed) {
    if (e is Substitution && e.clubId == side.clubId) {
      final i = slot[e.inId];
      if (i != null) slot.putIfAbsent(e.outId, () => i);
    }
  }
  return slot;
}

/// The player of the match over the finalised [s.ratings]: highest
/// rating, then more goals (own goals do not count), then the lower id;
/// null when nobody has a rating.
PlayerId? manOfTheMatch(MatchState s) {
  final goals = <PlayerId, int>{};
  for (final e in s.events) {
    if (e is Goal && !e.isOwnGoal) {
      goals[e.scorerId] = (goals[e.scorerId] ?? 0) + 1;
    }
  }
  final ids = s.ratings.keys.toList()
    ..sort((a, b) {
      final byRating = s.ratings[b]!.value.compareTo(s.ratings[a]!.value);
      if (byRating != 0) return byRating;
      final byGoals = (goals[b] ?? 0).compareTo(goals[a] ?? 0);
      return byGoals != 0 ? byGoals : a.compareTo(b);
    });
  return ids.isEmpty ? null : ids.first;
}
