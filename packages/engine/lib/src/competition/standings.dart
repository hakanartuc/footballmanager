import '../core/ids.dart';
import '../model/world.dart';

/// One club's line in a league table.
class TableRow {
  final ClubId clubId;
  int played = 0, won = 0, drawn = 0, lost = 0, gf = 0, ga = 0, points = 0;

  TableRow(this.clubId);

  int get gd => gf - ga;

  void _record(int scored, int conceded) {
    played++;
    gf += scored;
    ga += conceded;
    if (scored > conceded) {
      won++;
      points += 3;
    } else if (scored == conceded) {
      drawn++;
      points += 1;
    } else {
      lost++;
    }
  }
}

/// The table of league [l] in [seasonYear], computed from played fixtures
/// (read through [World.fixturesOfLeagueSeason], so the world's indexes
/// must be current).
///
/// Has a row for every club in the league, including clubs yet to play.
/// Ordered by points, goal difference and goals for (all descending), then
/// club name and club id (ascending).
List<TableRow> computeTable(World w, LeagueId l, int seasonYear) {
  final rows = {for (final c in w.leagues[l]!.clubIds) c: TableRow(c)};
  for (final id in w.fixturesOfLeagueSeason(l, seasonYear)) {
    final f = w.fixtures[id]!;
    final r = f.result;
    if (r == null) continue;
    rows[f.homeId]!._record(r.homeGoals, r.awayGoals);
    rows[f.awayId]!._record(r.awayGoals, r.homeGoals);
  }
  return rows.values.toList()..sort((a, b) {
    var c = b.points.compareTo(a.points);
    if (c != 0) return c;
    c = b.gd.compareTo(a.gd);
    if (c != 0) return c;
    c = b.gf.compareTo(a.gf);
    if (c != 0) return c;
    c = w.clubs[a.clubId]!.name.compareTo(w.clubs[b.clubId]!.name);
    return c != 0 ? c : a.clubId.compareTo(b.clubId);
  });
}
