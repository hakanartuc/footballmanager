import '../core/rng.dart';
import '../model/club.dart';
import '../model/enums.dart';
import '../model/fixture.dart';
import '../model/match_conditions.dart';
import '../model/match_rules.dart';
import '../model/tactic.dart';
import '../model/world.dart';
import 'lineup.dart';

/// How much of a match the engine keeps (spec 5.4): [result] and [events]
/// give the [MatchResult] with its events and statistics; [full] also
/// keeps every possession step (the `MatchLog`) for live viewing. The
/// result is identical in all three.
enum MatchDetail { result, events, full }

/// Everything a [MatchSimulator] needs for one match.
///
/// [rng] is the per-match stream (the caller forks
/// `'match:<fixtureId>:<seasonYear>'`); simulators must not fork it again
/// (`fork('visual')` is reserved for the detailed mode's coordinates).
/// [rules], [conditions], [homeTactic] and [awayTactic] are optional: the
/// possession engine resolves null to league rules, neutral conditions
/// and the club's tactic (see `MatchSession`); the Poisson engine ignores
/// them.
class MatchContext {
  const MatchContext({
    required this.world,
    required this.fixture,
    required this.home,
    required this.away,
    required this.rng,
    this.rules,
    this.conditions,
    this.homeTactic,
    this.awayTactic,
    this.detail = MatchDetail.result,
  });

  final World world;
  final Fixture fixture;
  final Lineup home;
  final Lineup away;
  final SeededRng rng;
  final MatchRules? rules;
  final MatchConditions? conditions;
  final Tactic? homeTactic;
  final Tactic? awayTactic;
  final MatchDetail detail;
}

abstract interface class MatchSimulator {
  MatchResult simulate(MatchContext ctx);
}

/// Mean over [l]'s starters of `ca × familiarity(slot) / 20 ×
/// conditionFactor(condition)`, scaled by `starters / 11` when short-handed.
/// Zero for an empty lineup.
double lineupStrength(World w, Lineup l) {
  if (l.starters.isEmpty) return 0;
  final slots = formationSlots(l.formation);
  var sum = 0.0;
  for (var i = 0; i < l.starters.length; i++) {
    final p = w.players[l.starters[i]]!;
    sum +=
        p.ca *
        (p.familiarity[slots[i]] ?? 1) /
        20 *
        conditionFactor(p.state.condition);
  }
  return sum / l.starters.length * (l.starters.length / 11);
}
