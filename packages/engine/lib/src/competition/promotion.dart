import '../core/ids.dart';
import '../model/world.dart';
import 'standings.dart';

/// One club changing league at the season's end.
class PromotionMove {
  PromotionMove({required this.clubId, required this.from, required this.to});

  final ClubId clubId;
  final LeagueId from;
  final LeagueId to;
}

/// Swaps, for every adjacent tier pair of country [c], the bottom
/// `relegatedCount` clubs of the upper tier with the top `promotedCount`
/// clubs of the lower tier (the data guarantees the counts match), reading
/// the final standings from [tables]. Updates `club.leagueId` and both
/// leagues' `clubIds` (kept sorted by id). Returns the moves in tier order,
/// relegations before promotions.
List<PromotionMove> applyPromotionRelegation(
  World w,
  CountryId c,
  Map<LeagueId, List<TableRow>> tables,
) {
  final tiers = w.countries[c]!.tiers;
  final moves = <PromotionMove>[];
  for (var k = 0; k + 1 < tiers.length; k++) {
    final upper = w.leagues[tiers[k]]!;
    final lower = w.leagues[tiers[k + 1]]!;
    final upperOrder = tables[upper.id]!.map((r) => r.clubId).toList();
    final lowerOrder = tables[lower.id]!.map((r) => r.clubId).toList();
    for (final id in upperOrder.sublist(
      upperOrder.length - upper.relegatedCount,
    )) {
      moves.add(PromotionMove(clubId: id, from: upper.id, to: lower.id));
    }
    for (final id in lowerOrder.sublist(0, lower.promotedCount)) {
      moves.add(PromotionMove(clubId: id, from: lower.id, to: upper.id));
    }
  }
  for (final m in moves) {
    w.clubs[m.clubId]!.leagueId = m.to;
    w.leagues[m.from]!.clubIds.remove(m.clubId);
    w.leagues[m.to]!.clubIds.add(m.clubId);
  }
  for (final id in tiers) {
    w.leagues[id]!.clubIds.sort();
  }
  return moves;
}
