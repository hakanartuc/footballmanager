import 'dart:convert';

import 'package:engine/engine.dart';
import 'package:test/test.dart';

void main() {
  group('syntheticPair', () {
    test('two clubs of 18 uniform players, CA = attr × 10, stored lineups', () {
      final w = syntheticPair(homeAttr: 12, awayAttr: 14);
      expect(w.clubs.keys, [1, 2]);
      expect(w.players, hasLength(36));
      for (final (club, attr) in [(1, 12), (2, 14)]) {
        final c = w.clubs[club]!;
        final lineup = c.lineup!;
        expect(lineup.starters, hasLength(11));
        expect(lineup.bench, hasLength(7));
        expect(lineup.formation, Formation.f442);
        expect(c.tactic.formation, Formation.f442);
        expect(c.tactic.mentality, Mentality.balanced);
        for (final id in [...lineup.starters, ...lineup.bench]) {
          final p = w.players[id]!;
          expect(p.ca, attr * 10);
          expect(p.attrs[Attr.finishing], attr);
          expect(p.state.condition, 100);
          expect(p.contract!.clubId, club);
        }
        expect(w.squadOf(club), hasLength(18));
      }
      expect(w.clubs[2]!.lineup!.starters.first, 101);
    });

    test('plusOne lifts the first players one point', () {
      final players = <PlayerId, Player>{};
      syntheticClub(id: 3, attr: 12, plusOne: 5, players: players);
      final cas = [
        for (final id in players.keys.toList()..sort()) players[id]!.ca,
      ];
      expect(cas, [130, 130, 130, 130, 130, ...List.filled(13, 120)]);
    });
  });

  group('runCalibration', () {
    final a = runCalibration(matches: 20, seed: 3);

    test('is byte-identical on the same seed', () {
      final b = runCalibration(matches: 20, seed: 3);
      expect(jsonEncode(b.toJson()), jsonEncode(a.toJson()));
      expect(b.toString(), a.toString());
      final c = runCalibration(matches: 20, seed: 4);
      expect(jsonEncode(c.toJson()), isNot(jsonEncode(a.toJson())));
    });

    test('reports consistent per-match rates and shares', () {
      expect(a.matches, 20);
      expect(a.homeWinPct + a.drawPct + a.awayWinPct, closeTo(100, 1e-9));
      expect(a.scorePct.length, lessThanOrEqualTo(12));
      expect(
        a.scorePct.values.fold(0.0, (s, v) => s + v),
        lessThanOrEqualTo(100 + 1e-9),
      );
      expect(a.homeShots, greaterThanOrEqualTo(a.homeOnTarget));
      expect(a.homePossessionPct, inInclusiveRange(0, 100));
      expect(a.addedTimePerHalf, inInclusiveRange(1, 6));
      expect(a.toString(), contains('goals/match'));
    });
  });

  test('runGapCurve averages the two venues', () {
    final g = runGapCurve(matches: 20, seed: 5, gap: 20);
    expect(g.gap, 20);
    expect(g.matches, 20);
    expect(g.homeStronger.homeAttr, 14);
    expect(g.homeStronger.awayAttr, 12);
    expect(g.awayStronger.homeAttr, 12);
    expect(g.awayStronger.awayAttr, 14);
    expect(g.strongWinPct + g.drawPct + g.weakWinPct, closeTo(100, 1e-9));
    expect(
      jsonEncode(runGapCurve(matches: 20, seed: 5, gap: 20).toJson()),
      jsonEncode(g.toJson()),
    );
    expect(
      () => runGapCurve(matches: 20, seed: 5, gap: 15),
      throwsArgumentError,
    );
  });

  test('runSeasonCalibration plays a 20-club double round robin', () {
    final s = runSeasonCalibration(seasons: 1, seed: 6);
    final season = s.seasons.single;
    expect(season.championPoints, inInclusiveRange(season.medianPoints, 114));
    expect(season.lastPoints, inInclusiveRange(0, season.medianPoints));
    expect(season.top3InTop4Count, inInclusiveRange(0, 3));
    expect(season.topScorerGoals, greaterThan(0));
    expect(s.top3InTop4Seasons, season.top3InTop4 ? 1 : 0);
    expect(
      jsonEncode(runSeasonCalibration(seasons: 1, seed: 6).toJson()),
      jsonEncode(s.toJson()),
    );
    expect(s.toString(), contains('champion points'));
  });
}
