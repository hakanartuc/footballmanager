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
        if (step.counter) counters++;
        if (!step.counter &&
            step.chance != ChanceType.corner &&
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

    // Brief bands hold for the open-play chance rate (k2 / chanceBase),
    // fouls and injuries. The rest are sanity ranges around what the spec
    // constants produce before calibration (Task 12); the measured values
    // and their causes are in the task-5 report:
    // - shots ≈ 12 open-play + counters (+0.6), corners (+1.1), penalties
    //   (+0.5) per side, and ×1.06 home advantage on the home side;
    // - on-target share = mean xG (0.18) + saveBand 0.25 ≈ 0.43;
    // - yellows = 12 fouls × yellowPerFoul 0.12 / 2 sides ≈ 0.72;
    // - penalties = 12 fouls × boxFoulShare 0.08 ≈ 0.95 (spec 0.25).
    expect(openChances / openSteps, inInclusiveRange(0.17, 0.23));
    expect(chances / steps, inInclusiveRange(0.17, 0.27));
    expect(homeShots / perMatch, inInclusiveRange(10, 18));
    expect(awayShots / perMatch, inInclusiveRange(9, 16));
    expect(onTarget / shots, inInclusiveRange(0.30, 0.50));
    expect(fouls / perMatch, inInclusiveRange(9, 15));
    expect(yellows / perMatch / 2, inInclusiveRange(0.5, 2.2));
    expect(injuries / perMatch / 2, inInclusiveRange(0.1, 0.25));
    expect(penalties / perMatch, inInclusiveRange(0.4, 1.6));
  });
}
