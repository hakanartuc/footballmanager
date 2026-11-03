/// Shared fixtures for the match-loop tests: a scripted [Rng], a uniform
/// two-club world and a started [MatchState].
library;

import 'package:engine/engine.dart';

/// Replays [draws] as the `nextDouble` stream; every other draw derives
/// from it the way [SeededRng] does. Throws when the script runs out.
class ScriptedRng implements Rng {
  ScriptedRng(this.draws);

  final List<double> draws;
  int used = 0;

  @override
  double nextDouble() {
    if (used >= draws.length) {
      throw StateError('ScriptedRng exhausted after $used draws');
    }
    return draws[used++];
  }

  @override
  int nextUint32() => (nextDouble() * 4294967296.0).floor();

  @override
  int nextInt(int maxExclusive) => (nextDouble() * maxExclusive).floor();

  @override
  bool nextBool(double pTrue) => nextDouble() < pTrue;

  @override
  int weightedIndex(List<double> weights) {
    var sum = 0.0;
    for (final w in weights) {
      sum += w;
    }
    final r = nextDouble() * sum;
    var acc = 0.0;
    for (var i = 0; i < weights.length; i++) {
      acc += weights[i];
      if (r < acc) return i;
    }
    return weights.lastIndexWhere((w) => w > 0);
  }

  @override
  T pick<T>(List<T> items) => items[nextInt(items.length)];

  @override
  Rng fork(String name) => throw UnsupportedError('scripted rng has no forks');
}

/// Factors all 1.0: familiarity 20 in [slot], condition 100, sharpness 100,
/// morale 50, form 5.5; age 26 on the fixture date; proneness 10
/// (`syntheticPlayer`; ca is attr × 10).
Player uniformPlayer(PlayerId id, Position slot, {int attr = 10}) =>
    syntheticPlayer(id, slot, attr: attr);

/// Home club 1 with players 1..11 and away club 2 with 101..111, both in
/// [formation] with uniform attributes; no clubs in the world.
World uniformWorld({
  Formation formation = Formation.f442,
  int homeAttr = 10,
  int awayAttr = 10,
}) {
  final slots = formationSlots(formation);
  return syntheticWorld(
    players: {
      for (var i = 0; i < 11; i++)
        i + 1: uniformPlayer(i + 1, slots[i], attr: homeAttr),
      for (var i = 0; i < 11; i++)
        101 + i: uniformPlayer(101 + i, slots[i], attr: awayAttr),
    },
  );
}

const homeIds = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
const awayIds = [101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111];

MatchConditions conditions({double homeAdvantage = 1.0}) => MatchConditions(
  weather: Weather.sunny,
  pitch: 8,
  attendance: 1000,
  homeAdvantage: homeAdvantage,
);

Fixture fixture() => Fixture(
  id: 1,
  leagueId: 1,
  seasonYear: 2026,
  round: 1,
  date: GameDate.ymd(2026, 8, 1),
  homeId: 1,
  awayId: 2,
);

/// A started match of club 1 (home) against club 2 on [w]; no home
/// advantage unless [cond] says so. Benches are empty unless given.
MatchState startMatch(
  World w, {
  Tactic? homeTactic,
  Tactic? awayTactic,
  MatchConditions? cond,
  Formation formation = Formation.f442,
  List<PlayerId> homeBench = const [],
  List<PlayerId> awayBench = const [],
}) => MatchState.start(
  w: w,
  f: fixture(),
  homeLineup: Lineup(formation: formation, starters: homeIds, bench: homeBench),
  awayLineup: Lineup(formation: formation, starters: awayIds, bench: awayBench),
  homeTactic: homeTactic ?? Tactic.preset(formation),
  awayTactic: awayTactic ?? Tactic.preset(formation),
  rules: MatchRules.league,
  conditions: cond ?? conditions(),
);
