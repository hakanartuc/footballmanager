import '../../core/ids.dart';
import '../../core/rng.dart';
import '../../model/enums.dart';
import '../../model/match_result.dart';
import '../../model/match_rules.dart';
import '../../model/world.dart';
import 'match_state.dart';
import 'team_profile.dart';
import 'tuning.dart';

/// Kicks each side takes before sudden death.
const _shootoutRounds = 5;

/// Whether a level match goes to extra time under [r].
bool needsExtraTime(MatchState s, MatchRules r) =>
    r.extraTime && s.home.goals == s.away.goals;

/// Whether a level match goes to penalties under [r]; asked after extra
/// time, or after 90 minutes when [r] has no extra time.
bool needsShootout(MatchState s, MatchRules r) =>
    r.penalties && s.home.goals == s.away.goals;

/// Starts extra time: half 3 from minute 90 with no added time, and an
/// [ExtraTimeStart] event. A second call changes nothing.
void startExtraTime(MatchState s) {
  if (s.extraTime) return;
  s.extraTime = true;
  s.half = 3;
  s.minute = 90;
  s.clockSeconds = 90 * 60;
  s.addedTime = 0;
  s.events.add(ExtraTimeStart(minute: 90, half: 3, clubId: s.home.clubId));
}

/// The minute [half] (1..4) ends at before added time.
int halfEnd(int half) => switch (half) {
  1 => 45,
  2 => 90,
  3 => 105,
  4 => 120,
  _ => throw ArgumentError.value(half, 'half', 'must be 1..4'),
};

/// Substitutions a side may make: the rules' number, one more in extra time.
int subsAllowed(MatchState s, MatchRules r) =>
    r.substitutions + (s.extraTime ? 1 : 0);

/// Plays the penalty shootout of a level match: sets `half` to 5, appends a
/// [ShootoutStart] and one [ShootoutKick] per kick, and writes
/// `homeShootout` / `awayShootout`. Goals, stats and ratings are untouched.
///
/// Home kicks first, then the sides alternate: five kicks each, stopping as
/// soon as one side cannot be caught, then sudden death a round at a time
/// until one side leads after a round. Each side's kickers are the
/// tactic's penalty taker when on the pitch, then the rest of the pitch by
/// effective composure + finishing descending (tie: lower id), cycling
/// from the start when exhausted.
///
/// A kick scores with
/// `xgBase[penalty] × (1 + finishingCoef × (finishing + composure − 20)) ×
/// (1 − keeperCoef × (gk − 10))`, clamped to `shootoutMin..shootoutMax`;
/// attributes are effective (slot and match condition), `gk` is the
/// opposing keeper slot's effective reflexes, `missingGroupValue` when the
/// slot is empty.
///
/// Draw order on [rng]: one `nextDouble` per kick, in kick order; the kick
/// scores when it is below the probability.
void playShootout(MatchState s, World w, Rng rng) {
  s.half = 5;
  s.events.add(ShootoutStart(minute: s.minute, half: 5, clubId: s.home.clubId));
  final sides = [s.home, s.away];
  final orders = [for (final side in sides) _kickOrder(w, side)];
  final keepers = [for (final side in sides) _keeperValue(w, side)];
  final scored = [0, 0];
  final taken = [0, 0];

  bool decided() {
    if (taken[0] < _shootoutRounds || taken[1] < _shootoutRounds) {
      return scored[0] + _shootoutRounds - taken[0] < scored[1] ||
          scored[1] + _shootoutRounds - taken[1] < scored[0];
    }
    return taken[0] == taken[1] && scored[0] != scored[1];
  }

  var i = 0;
  while (!decided()) {
    final side = sides[i];
    final order = orders[i];
    final id = order[taken[i] % order.length];
    final p =
        (EngineTuning.xgBase[ChanceType.penalty]! *
                (1 +
                    EngineTuning.finishingCoef *
                        (_eff(w, side, id, Attr.finishing) +
                            _eff(w, side, id, Attr.composure) -
                            20)) *
                (1 - EngineTuning.keeperCoef * (keepers[1 - i] - 10)))
            .clamp(EngineTuning.shootoutMin, EngineTuning.shootoutMax);
    final goal = rng.nextDouble() < p;
    taken[i]++;
    if (goal) scored[i]++;
    s.events.add(
      ShootoutKick(
        minute: s.minute,
        half: 5,
        clubId: side.clubId,
        playerId: id,
        scored: goal,
      ),
    );
    i = 1 - i;
  }
  s.homeShootout = scored[0];
  s.awayShootout = scored[1];
}

/// [side]'s kickers in order: the penalty taker when on the pitch, then the
/// others by effective composure + finishing descending, tie lower id.
List<PlayerId> _kickOrder(World w, SideState side) {
  final taker = side.tactic.setPieces.penalty;
  final playing = side.playing;
  double value(PlayerId id) =>
      _eff(w, side, id, Attr.composure) + _eff(w, side, id, Attr.finishing);
  final rest = [
    for (final id in playing)
      if (id != taker) id,
  ];
  rest.sort((a, b) {
    final c = value(b).compareTo(value(a));
    return c != 0 ? c : a.compareTo(b);
  });
  return [if (taker != null && playing.contains(taker)) taker, ...rest];
}

/// The effective reflexes of [side]'s keeper slot, or
/// [EngineTuning.missingGroupValue] when the slot is empty.
double _keeperValue(World w, SideState side) {
  final i = side.tactic.slots.indexOf(Position.gk);
  final id = i == -1 ? null : side.onPitch[i];
  return id == null
      ? EngineTuning.missingGroupValue
      : _eff(w, side, id, Attr.reflexes);
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
