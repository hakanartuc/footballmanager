@Tags(['slow'])
library;

import 'package:engine/engine.dart';
import 'package:test/test.dart';

const _seasons = 100;
const _seed = 1;

/// Spec §9's season check on the synthetic 20-club league
/// (`cm calibrate --season`): 100 seasons, club strengths drawn with sd 13
/// CA around 120, every match at condition 100 (no fatigue, injuries or
/// bans carried).
///
/// "The strongest three clubs finish in the top four" is gated per club
/// (share of the 300 club-seasons ≥ 80 %), not per season: with sd 13 the
/// third and fourth strongest clubs are typically 2..5 CA apart, worth 1..3
/// points over 38 matches against a points noise of ~8, so all three
/// finishing top four at once happens in about half the seasons at the
/// spec's own gap curve (Task 12 report).
void main() {
  late SeasonCalibration s;

  setUpAll(() {
    final watch = Stopwatch()..start();
    s = runSeasonCalibration(seasons: _seasons, seed: _seed);
    print('season calibration: ${watch.elapsedMilliseconds} ms');
    print(s);
  });

  test('champion 78..95 points, last 18..32, median 45..55', () {
    expect(s.championPoints, inInclusiveRange(78, 95));
    expect(s.lastPoints, inInclusiveRange(18, 32));
    expect(s.medianPoints, inInclusiveRange(45, 55));
  });

  test('the strongest three clubs finish top four in ≥ 80 % of their '
      'seasons', () {
    expect(s.top3InTop4Pct, greaterThanOrEqualTo(80));
  });

  test('the strongest club is champion in at most 70 seasons', () {
    expect(s.top1ChampionSeasons, lessThanOrEqualTo(70));
  });

  test('top scorer 20..32 goals', () {
    expect(s.topScorerGoals, inInclusiveRange(20, 32));
  });
}
