import '../core/ids.dart';
import '../model/club.dart';
import '../model/enums.dart';
import '../model/player.dart';
import '../model/world.dart';

enum LineupError { notEleven, duplicate, notInClub, noGoalkeeper, ineligible }

/// Scales a player's contribution by [condition] (0..100): 0.75 at 0,
/// 1.0 at 100.
double conditionFactor(double condition) => 0.75 + 0.25 * condition / 100;

bool _available(Player p) =>
    p.state.injury == null && p.state.suspensionMatches == 0;

/// Orders by [key] descending, then id ascending.
int Function(Player, Player) _byDesc(num Function(Player) key) => (a, b) {
  final c = key(b).compareTo(key(a));
  return c != 0 ? c : a.id.compareTo(b.id);
};

/// Picks [c]'s best lineup for [formation] (default: the club's formation).
///
/// Each slot in turn takes the unused candidate with the highest
/// `ca × familiarity / 20 × conditionFactor`. Candidates are the available
/// (not injured or suspended) seniors; when fewer than 11, available youth
/// join, then any remaining club player; a fit candidate always beats an
/// unavailable one. The bench is the next up to 7
/// available candidates by CA, with the best unused goalkeeper swapped in
/// for the last place when none made it.
Lineup autoLineup(World w, ClubId c, {Formation? formation}) {
  final f = formation ?? w.clubs[c]!.formation;
  final seniors = [for (final id in w.squadOf(c)) w.players[id]!];
  final youth = [for (final id in w.youthOf(c)) w.players[id]!];

  final pool = seniors.where(_available).toList();
  if (pool.length < 11) pool.addAll(youth.where(_available));
  if (pool.length < 11) {
    pool.addAll([...seniors, ...youth].where((p) => !_available(p)));
  }

  final starters = <PlayerId>[];
  for (final slot in formationSlots(f)) {
    final unused = pool.where((p) => !starters.contains(p.id));
    final fit = unused.where(_available);
    final ranked = (fit.isNotEmpty ? fit : unused).toList()
      ..sort(
        _byDesc(
          (p) =>
              p.ca *
              (p.familiarity[slot] ?? 1) /
              20 *
              conditionFactor(p.state.condition),
        ),
      );
    if (ranked.isEmpty) break;
    starters.add(ranked.first.id);
  }

  final unused =
      pool.where((p) => _available(p) && !starters.contains(p.id)).toList()
        ..sort(_byDesc((p) => p.ca));
  final bench = unused.take(7).toList();
  bool isGk(Player p) => p.mainPosition == Position.gk;
  if (!bench.any(isGk)) {
    final gk = unused.where(isGk).firstOrNull;
    if (gk != null) bench.last = gk;
  }

  return Lineup(
    formation: f,
    starters: starters,
    bench: [for (final p in bench) p.id],
  );
}

/// Everything wrong with [l] as [c]'s lineup, in [LineupError] order.
List<LineupError> validateLineup(World w, ClubId c, Lineup l) {
  final all = [...l.starters, ...l.bench];
  final club = {...w.squadOf(c), ...w.youthOf(c)};
  final starters = [for (final id in l.starters) w.players[id]];
  return [
    if (l.starters.length != 11) LineupError.notEleven,
    if (all.toSet().length != all.length) LineupError.duplicate,
    if (!club.containsAll(all)) LineupError.notInClub,
    if (!starters.any((p) => p?.mainPosition == Position.gk))
      LineupError.noGoalkeeper,
    if (starters.any((p) => p != null && !_available(p)))
      LineupError.ineligible,
  ];
}
