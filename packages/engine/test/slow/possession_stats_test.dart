@Tags(['slow'])
library;

import 'package:engine/engine.dart';
import 'package:test/test.dart';

import '../sim/match/match_helpers.dart';

const _matches = 167;
const _stepsPerMatch = 120;
const _homeAdvantage = 1.06;

void main() {
  test('20k steps between equal CA-120 sides land in the sanity bands', () {
    // Uniform 12s: CA 120 for every position group.
    final w = uniformWorld(homeAttr: 12, awayAttr: 12);
    final rng = SeededRng(2026);
    var steps = 0;
    var chances = 0;
    var shots = 0;
    var onTarget = 0;
    var fouls = 0;
    var yellows = 0;
    var injuries = 0;
    var homeShots = 0;
    var awayShots = 0;
    var homeGoals = 0;
    var awayGoals = 0;
    var penalties = 0;
    var openSteps = 0;
    var openChances = 0;
    var counters = 0;
    var corners = 0;
    var freeKicks = 0;
    var xg = 0.0;
    for (var m = 0; m < _matches; m++) {
      final s = startMatch(w, cond: conditions(homeAdvantage: _homeAdvantage));
      for (var i = 0; i < _stepsPerMatch; i++) {
        final step = resolvePossession(s, w, rng, detail: false);
        applySideEffects(s, step, w, rng);
        steps++;
        if (step.chance != null) chances++;
        if (step.chance == ChanceType.penalty) penalties++;
        if (step.chance == ChanceType.corner) corners++;
        if (step.chance == ChanceType.freeKick) freeKicks++;
        if (step.counter) counters++;
        if (!step.counter &&
            step.chance != ChanceType.corner &&
            step.chance != ChanceType.freeKick &&
            step.chance != ChanceType.penalty) {
          openSteps++;
          if (step.chance != null) openChances++;
        }
        xg += step.xg ?? 0;
      }
      for (final side in [s.home, s.away]) {
        shots += side.stats.shots;
        onTarget += side.stats.onTarget;
        fouls += side.stats.fouls;
        yellows += side.stats.yellows;
      }
      homeShots += s.home.stats.shots;
      awayShots += s.away.stats.shots;
      homeGoals += s.home.goals;
      awayGoals += s.away.goals;
      injuries += s.events.whereType<Injury>().length;
      expect(s.minute, inInclusiveRange(60, 150));
    }
    final perMatch = _matches.toDouble();
    final report = {
      'steps': steps,
      'chance rate': chances / steps,
      'open-play chance rate': openChances / openSteps,
      'counter share of steps': counters / steps,
      'corners per match': corners / perMatch,
      'free kicks per match': freeKicks / perMatch,
      'xg per shot': xg / shots,
      'shots per side per match': shots / perMatch / 2,
      'home shots': homeShots / perMatch,
      'away shots': awayShots / perMatch,
      'on-target share': onTarget / shots,
      'goals per side per match': (homeGoals + awayGoals) / perMatch / 2,
      'home goals': homeGoals / perMatch,
      'away goals': awayGoals / perMatch,
      'fouls per match': fouls / perMatch,
      'yellows per side per match': yellows / perMatch / 2,
      'injuries per side per match': injuries / perMatch / 2,
      'penalties per match': penalties / perMatch,
    };
    printOnFailure(report.toString());
    // ignore: avoid_print
    print(report);

    // Sanity bands around the Task 13 constants on 120 fixed steps per
    // match (a real match has ~97, so the per-match counts run ~25 % above
    // `cm calibrate`'s); measured on seed 2026:
    // - open-play chance rate 0.19 = logistic(chanceBase); 0.24 with set
    //   pieces and counters (k2 0.14, counterDefMul 0.8);
    // - shots 16.3 home / 12.1 away: possession 55/45 from homeLogOdds
    //   0.7 × 1.09 (homeAdvantage 1.06) on the contested 0.405 of the
    //   possessions, plus corners (2.2), free kicks (3.2), penalties (0.3)
    //   per match;
    // - xG per shot 0.105; on-target share = xG + saveBand 0.25 ≈ 0.35;
    // - fouls 14.6 (foulPerStep 0.12), yellows 1.9 per side
    //   (yellowPerFoul 0.28, booked players × bookedYellowMul 0.5),
    //   injuries 0.19 per side (injuryPerStep 0.0025 × mean weight 1.21
    //   × 120 steps / 2).
    expect(openChances / openSteps, inInclusiveRange(0.17, 0.21));
    expect(chances / steps, inInclusiveRange(0.21, 0.27));
    expect(homeShots / perMatch, inInclusiveRange(15, 19));
    expect(awayShots / perMatch, inInclusiveRange(10, 14));
    expect(xg / shots, inInclusiveRange(0.09, 0.12));
    expect(onTarget / shots, inInclusiveRange(0.30, 0.40));
    expect(fouls / perMatch, inInclusiveRange(12, 17));
    expect(yellows / perMatch / 2, inInclusiveRange(1.7, 2.4));
    expect(injuries / perMatch / 2, inInclusiveRange(0.12, 0.25));
    expect(penalties / perMatch, inInclusiveRange(0.2, 0.4));
  });
}
