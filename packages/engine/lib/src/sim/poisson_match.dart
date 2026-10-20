/// Faz 0 placeholder match engine: independent Poisson goal counts.
///
/// `λ_home = baseHome × exp(strengthSlope × d) × homeAdvantage`,
/// `λ_away = baseAway × exp(−strengthSlope × d)`, where
/// `d = (strength_home − strength_away) / 20`.
///
/// Calibration (seed 1, 20k matches per case, test/slow/poisson_stats_test.dart)
/// with baseHome 1.45, baseAway 1.20, homeAdvantage 1.06, strengthSlope 0.33
/// (the brief's 0.55 gave 94% for the +40 gap, so the slope was lowered):
/// equal 120 v 120: mean goals 2.746, home 45.5%, draw 25.5%, away 29.1%;
/// strength gap +40: stronger side wins 77.9% (84.4% at home, 71.4% away).
library;

import 'dart:math' as math;

import '../model/enums.dart';
import '../model/fixture.dart';
import 'match_simulator.dart';

/// Expected home goals between equal sides, before [homeAdvantage].
const double baseHome = 1.45;

/// Expected away goals between equal sides.
const double baseAway = 1.20;

/// Multiplier on the home side's expected goals.
const double homeAdvantage = 1.06;

/// Exponent per 20 points of lineup-strength difference.
const double strengthSlope = 0.33;

/// Relative likelihood of scoring by slot position.
const Map<Position, double> positionWeight = {
  Position.st: 6,
  Position.amc: 3,
  Position.aml: 3,
  Position.amr: 3,
  Position.mc: 1.5,
  Position.ml: 1.5,
  Position.mr: 1.5,
  Position.dm: 0.7,
  Position.dc: 0.4,
  Position.dl: 0.4,
  Position.dr: 0.4,
  Position.gk: 0.02,
};

class PoissonMatchSimulator implements MatchSimulator {
  const PoissonMatchSimulator();

  /// Draw order: match seed, home goals, away goals, then per goal
  /// (home first) scorer and minute.
  @override
  MatchResult simulate(MatchContext ctx) {
    final rng = ctx.rng;
    final matchSeed = rng.nextUint32();

    final d =
        (lineupStrength(ctx.world, ctx.home) -
            lineupStrength(ctx.world, ctx.away)) /
        20;
    final lambdaHome = ctx.home.starters.isEmpty
        ? 0.0
        : baseHome * math.exp(strengthSlope * d) * homeAdvantage;
    final lambdaAway = ctx.away.starters.isEmpty
        ? 0.0
        : baseAway * math.exp(-strengthSlope * d);
    final homeGoals = rng.nextPoisson(lambdaHome);
    final awayGoals = rng.nextPoisson(lambdaAway);

    final drawn = <GoalEvent>[];
    for (final (lineup, clubId, count) in [
      (ctx.home, ctx.fixture.homeId, homeGoals),
      (ctx.away, ctx.fixture.awayId, awayGoals),
    ]) {
      final slots = formationSlots(lineup.formation);
      final weights = [
        for (var i = 0; i < lineup.starters.length; i++)
          positionWeight[slots[i]]! *
              ctx.world.players[lineup.starters[i]]!.attrs[Attr.finishing] /
              10,
      ];
      for (var g = 0; g < count; g++) {
        final scorer = lineup.starters[rng.weightedIndex(weights)];
        drawn.add(
          GoalEvent(
            minute: 1 + rng.nextInt(90),
            scorerId: scorer,
            clubId: clubId,
          ),
        );
      }
    }
    // Stable order: minute, then draw order (home goals before away goals).
    final order = List.generate(drawn.length, (i) => i)
      ..sort((a, b) {
        final c = drawn[a].minute.compareTo(drawn[b].minute);
        return c != 0 ? c : a.compareTo(b);
      });

    return MatchResult(
      homeGoals: homeGoals,
      awayGoals: awayGoals,
      goals: [for (final i in order) drawn[i]],
      matchSeed: matchSeed,
    );
  }
}
