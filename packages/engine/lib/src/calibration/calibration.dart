import '../core/ids.dart';
import '../core/rng.dart';
import '../model/club.dart';
import '../model/fixture.dart';
import '../model/match_conditions.dart';
import '../model/match_rules.dart';
import '../model/player.dart';
import '../model/world.dart';
import '../sim/match/possession_match_simulator.dart';
import '../sim/match_simulator.dart';
import 'synthetic.dart';

/// The calibration harness of spec §9: single-match distributions between
/// synthetic sides, the §5.6 gap curve and the 20-club season check.
/// Every draw comes from a named fork of the seed, so the same seed gives
/// byte-identical reports.

const _sim = PossessionMatchSimulator();

String _pct(double v) => v.toStringAsFixed(1).padLeft(5);
String _num(double v) => v.toStringAsFixed(2).padLeft(5);

/// One match of [home] against [away] on [w] under league rules and
/// neutral conditions (home advantage 1.055), both clubs' stored lineups
/// and active tactics, fast mode.
MatchResult _play(World w, ClubId home, ClubId away, SeededRng rng) =>
    _sim.simulate(
      MatchContext(
        world: w,
        fixture: Fixture(
          id: 1,
          leagueId: 1,
          seasonYear: w.seasonYear,
          round: 1,
          date: w.date,
          homeId: home,
          awayId: away,
        ),
        home: w.clubs[home]!.lineup!,
        away: w.clubs[away]!.lineup!,
        rng: rng,
        rules: MatchRules.league,
        conditions: MatchConditions.neutral,
        detail: MatchDetail.result,
      ),
    );

/// Aggregates of [matches] matches between a home side of uniform
/// [homeAttr] and an away side of uniform [awayAttr] (CA = attr × 10).
/// Rates are per match unless named per side; `yellows` counts first
/// yellows, `reds` sendings-off (second yellows included).
class CalibrationReport {
  final int matches;
  final int seed;
  final int homeAttr;
  final int awayAttr;
  final double goalsPerMatch;
  final double homeWinPct;
  final double drawPct;
  final double awayWinPct;
  final double homeShots;
  final double awayShots;
  final double homeOnTarget;
  final double awayOnTarget;
  final double corners;
  final double fouls;
  final double yellows;
  final double reds;
  final double injuries;
  final double substitutions;

  /// The 12 most common scores, `'h-a'` → share in %, most common first.
  final Map<String, double> scorePct;
  final double fivePlusGoalsPct;
  final double homePossessionPct;
  final double homeXg;
  final double awayXg;
  final double addedTimePerHalf;

  CalibrationReport({
    required this.matches,
    required this.seed,
    required this.homeAttr,
    required this.awayAttr,
    required this.goalsPerMatch,
    required this.homeWinPct,
    required this.drawPct,
    required this.awayWinPct,
    required this.homeShots,
    required this.awayShots,
    required this.homeOnTarget,
    required this.awayOnTarget,
    required this.corners,
    required this.fouls,
    required this.yellows,
    required this.reds,
    required this.injuries,
    required this.substitutions,
    required this.scorePct,
    required this.fivePlusGoalsPct,
    required this.homePossessionPct,
    required this.homeXg,
    required this.awayXg,
    required this.addedTimePerHalf,
  });

  Map<String, Object?> toJson() => {
    'matches': matches,
    'seed': seed,
    'homeAttr': homeAttr,
    'awayAttr': awayAttr,
    'goalsPerMatch': goalsPerMatch,
    'homeWinPct': homeWinPct,
    'drawPct': drawPct,
    'awayWinPct': awayWinPct,
    'homeShots': homeShots,
    'awayShots': awayShots,
    'homeOnTarget': homeOnTarget,
    'awayOnTarget': awayOnTarget,
    'corners': corners,
    'fouls': fouls,
    'yellows': yellows,
    'reds': reds,
    'injuries': injuries,
    'substitutions': substitutions,
    'scorePct': scorePct,
    'fivePlusGoalsPct': fivePlusGoalsPct,
    'homePossessionPct': homePossessionPct,
    'homeXg': homeXg,
    'awayXg': awayXg,
    'addedTimePerHalf': addedTimePerHalf,
  };

  @override
  String toString() {
    final b = StringBuffer()
      ..writeln(
        'calibration: $matches matches, seed $seed, '
        'home CA ${homeAttr * 10} vs away CA ${awayAttr * 10}',
      )
      ..writeln('  goals/match      ${_num(goalsPerMatch)}')
      ..writeln(
        '  home/draw/away   ${_pct(homeWinPct)} /${_pct(drawPct)} /'
        '${_pct(awayWinPct)} %',
      )
      ..writeln('  shots h/a        ${_num(homeShots)} /${_num(awayShots)}')
      ..writeln(
        '  on target h/a    ${_num(homeOnTarget)} /${_num(awayOnTarget)}',
      )
      ..writeln('  xG h/a           ${_num(homeXg)} /${_num(awayXg)}')
      ..writeln('  possession home  ${_pct(homePossessionPct)} %')
      ..writeln('  corners          ${_num(corners)}')
      ..writeln('  fouls            ${_num(fouls)}')
      ..writeln('  yellows          ${_num(yellows)}')
      ..writeln('  reds             ${_num(reds)}')
      ..writeln('  injuries         ${_num(injuries)}')
      ..writeln('  substitutions    ${_num(substitutions)}')
      ..writeln('  added time/half  ${_num(addedTimePerHalf)}')
      ..writeln('  5+ goals         ${_pct(fivePlusGoalsPct)} %')
      ..write('  scores          ');
    for (final MapEntry(key: score, value: pct) in scorePct.entries) {
      b.write(' $score ${pct.toStringAsFixed(1)}%');
    }
    return b.toString();
  }
}

/// Plays [matches] matches of `syntheticPair(homeAttr, awayAttr)` with
/// the possession engine, match `i` on `SeededRng(seed).fork('calib:$i')`.
CalibrationReport runCalibration({
  required int matches,
  required int seed,
  int homeAttr = 12,
  int awayAttr = 12,
}) {
  final w = syntheticPair(homeAttr: homeAttr, awayAttr: awayAttr, seed: seed);
  final root = SeededRng(seed);
  var goals = 0;
  var homeWins = 0;
  var draws = 0;
  var homeShots = 0;
  var awayShots = 0;
  var homeOnTarget = 0;
  var awayOnTarget = 0;
  var corners = 0;
  var fouls = 0;
  var yellows = 0;
  var reds = 0;
  var injuries = 0;
  var subs = 0;
  var fivePlus = 0;
  var possession = 0;
  var homeXg = 0.0;
  var awayXg = 0.0;
  var addedTime = 0;
  var halves = 0;
  final scores = <String, int>{};
  for (var i = 0; i < matches; i++) {
    final r = _play(w, 1, 2, root.fork('calib:$i'));
    final total = r.homeGoals + r.awayGoals;
    goals += total;
    if (r.homeGoals > r.awayGoals) {
      homeWins++;
    } else if (r.homeGoals == r.awayGoals) {
      draws++;
    }
    if (total >= 5) fivePlus++;
    final key = '${r.homeGoals}-${r.awayGoals}';
    scores[key] = (scores[key] ?? 0) + 1;
    final h = r.homeStats!;
    final a = r.awayStats!;
    homeShots += h.shots;
    awayShots += a.shots;
    homeOnTarget += h.onTarget;
    awayOnTarget += a.onTarget;
    corners += h.corners + a.corners;
    fouls += h.fouls + a.fouls;
    possession += h.possessionPct;
    homeXg += h.xg;
    awayXg += a.xg;
    for (final e in r.events) {
      switch (e) {
        case Booking(kind: CardKind.yellow):
          yellows++;
        case Booking():
          reds++;
        case Injury():
          injuries++;
        case Substitution():
          subs++;
        case HalfTime(half: 1, :final minute):
          addedTime += minute - 45;
          halves++;
        case FullTime(half: 2, :final minute):
          addedTime += minute - 90;
          halves++;
        default:
          break;
      }
    }
  }
  final n = matches.toDouble();
  final ranked = scores.entries.toList()
    ..sort((x, y) {
      final c = y.value.compareTo(x.value);
      return c != 0 ? c : x.key.compareTo(y.key);
    });
  return CalibrationReport(
    matches: matches,
    seed: seed,
    homeAttr: homeAttr,
    awayAttr: awayAttr,
    goalsPerMatch: goals / n,
    homeWinPct: 100 * homeWins / n,
    drawPct: 100 * draws / n,
    awayWinPct: 100 * (matches - homeWins - draws) / n,
    homeShots: homeShots / n,
    awayShots: awayShots / n,
    homeOnTarget: homeOnTarget / n,
    awayOnTarget: awayOnTarget / n,
    corners: corners / n,
    fouls: fouls / n,
    yellows: yellows / n,
    reds: reds / n,
    injuries: injuries / n,
    substitutions: subs / n,
    scorePct: {for (final e in ranked.take(12)) e.key: 100 * e.value / n},
    fivePlusGoalsPct: 100 * fivePlus / n,
    homePossessionPct: possession / n,
    homeXg: homeXg / n,
    awayXg: awayXg / n,
    addedTimePerHalf: halves == 0 ? 0 : addedTime / halves,
  );
}

/// The §5.6 curve at one CA [gap]: the stronger side's result shares
/// averaged over it playing at home ([homeStronger]) and away
/// ([awayStronger]).
class GapReport {
  final int gap;
  final CalibrationReport homeStronger;
  final CalibrationReport awayStronger;

  GapReport({
    required this.gap,
    required this.homeStronger,
    required this.awayStronger,
  });

  int get matches => homeStronger.matches + awayStronger.matches;
  double get strongWinPct =>
      (homeStronger.homeWinPct + awayStronger.awayWinPct) / 2;
  double get drawPct => (homeStronger.drawPct + awayStronger.drawPct) / 2;
  double get weakWinPct =>
      (homeStronger.awayWinPct + awayStronger.homeWinPct) / 2;

  Map<String, Object?> toJson() => {
    'gap': gap,
    'matches': matches,
    'strongWinPct': strongWinPct,
    'drawPct': drawPct,
    'weakWinPct': weakWinPct,
    'homeStronger': homeStronger.toJson(),
    'awayStronger': awayStronger.toJson(),
  };

  @override
  String toString() =>
      'gap +$gap CA: $matches matches, stronger side win/draw/loss '
      '${_pct(strongWinPct)} /${_pct(drawPct)} /${_pct(weakWinPct)} % '
      '(at home ${_pct(homeStronger.homeWinPct)} /'
      '${_pct(homeStronger.drawPct)} /${_pct(homeStronger.awayWinPct)}, '
      'away ${_pct(awayStronger.awayWinPct)} /${_pct(awayStronger.drawPct)} /'
      '${_pct(awayStronger.homeWinPct)}); '
      'goals ${_num(homeStronger.goalsPerMatch)} /'
      '${_num(awayStronger.goalsPerMatch)}';
}

/// [matches] / 2 matches with the home side [gap] CA stronger (seed
/// `seed`) and as many with the away side stronger (seed `seed + 1`).
/// [gap] must be a multiple of 10 (one attribute point per 10 CA).
GapReport runGapCurve({
  required int matches,
  required int seed,
  required int gap,
}) {
  if (gap % 10 != 0) {
    throw ArgumentError.value(gap, 'gap', 'must be a multiple of 10');
  }
  final step = gap ~/ 10;
  return GapReport(
    gap: gap,
    homeStronger: runCalibration(
      matches: matches ~/ 2,
      seed: seed,
      homeAttr: 12 + step,
      awayAttr: 12,
    ),
    awayStronger: runCalibration(
      matches: matches ~/ 2,
      seed: seed + 1,
      homeAttr: 12,
      awayAttr: 12 + step,
    ),
  );
}

/// One synthetic season.
class SeasonSummary {
  final int championPoints;
  final int lastPoints;
  final double medianPoints;

  /// How many of the three strongest clubs by CA finished in the top four.
  final int top3InTop4Count;

  /// All three did.
  bool get top3InTop4 => top3InTop4Count == 3;

  /// The strongest club by CA won the league.
  final bool top1Champion;
  final int topScorerGoals;

  SeasonSummary({
    required this.championPoints,
    required this.lastPoints,
    required this.medianPoints,
    required this.top3InTop4Count,
    required this.top1Champion,
    required this.topScorerGoals,
  });

  Map<String, Object?> toJson() => {
    'championPoints': championPoints,
    'lastPoints': lastPoints,
    'medianPoints': medianPoints,
    'top3InTop4Count': top3InTop4Count,
    'top1Champion': top1Champion,
    'topScorerGoals': topScorerGoals,
  };
}

/// Spec §9's season check over [seasons] synthetic seasons.
class SeasonCalibration {
  final int seed;
  final List<SeasonSummary> seasons;

  SeasonCalibration({required this.seed, required this.seasons});

  double _mean(num Function(SeasonSummary s) f) =>
      seasons.fold(0.0, (a, s) => a + f(s)) / seasons.length;

  double get championPoints => _mean((s) => s.championPoints);
  double get lastPoints => _mean((s) => s.lastPoints);
  double get medianPoints => _mean((s) => s.medianPoints);
  int get top3InTop4Seasons => seasons.where((s) => s.top3InTop4).length;

  /// Share in % of the (season, top-3 club) pairs that finished top four.
  double get top3InTop4Pct =>
      100 *
      seasons.fold(0, (a, s) => a + s.top3InTop4Count) /
      (3 * seasons.length);
  int get top1ChampionSeasons => seasons.where((s) => s.top1Champion).length;
  double get topScorerGoals => _mean((s) => s.topScorerGoals);
  int get minChampionPoints =>
      seasons.map((s) => s.championPoints).reduce((a, b) => a < b ? a : b);
  int get maxChampionPoints =>
      seasons.map((s) => s.championPoints).reduce((a, b) => a > b ? a : b);
  int get minLastPoints =>
      seasons.map((s) => s.lastPoints).reduce((a, b) => a < b ? a : b);
  int get maxLastPoints =>
      seasons.map((s) => s.lastPoints).reduce((a, b) => a > b ? a : b);

  Map<String, Object?> toJson() => {
    'seed': seed,
    'seasons': seasons.length,
    'championPoints': championPoints,
    'lastPoints': lastPoints,
    'medianPoints': medianPoints,
    'top3InTop4Seasons': top3InTop4Seasons,
    'top3InTop4Pct': top3InTop4Pct,
    'top1ChampionSeasons': top1ChampionSeasons,
    'topScorerGoals': topScorerGoals,
    'perSeason': [for (final s in seasons) s.toJson()],
  };

  @override
  String toString() =>
      'season calibration: ${seasons.length} seasons, seed $seed\n'
      '  champion points  ${_num(championPoints)} '
      '(min $minChampionPoints, max $maxChampionPoints)\n'
      '  last points      ${_num(lastPoints)} '
      '(min $minLastPoints, max $maxLastPoints)\n'
      '  median points    ${_num(medianPoints)}\n'
      '  top-3 by CA in top 4   $top3InTop4Seasons / ${seasons.length} '
      '(${_pct(top3InTop4Pct)} % of the clubs)\n'
      '  top-1 by CA champion   $top1ChampionSeasons / ${seasons.length}\n'
      '  top scorer goals ${_num(topScorerGoals)}';
}

/// [seasons] double round robins of 20 synthetic clubs played with the
/// simulator directly: condition 100 in every match, no injuries, bans or
/// fatigue carried between matches, no day loop. Season `s` draws each
/// club's strength from `SeededRng(seed).fork('season:$s')` as
/// `12 + N(0, 1.3)` attribute points clamped to 8..17 (CA 80..170, sd ≈ 13
/// around 120); the fractional part is realised by giving that share of
/// the 18 players one attribute point more (`syntheticClub(plusOne:)`),
/// so club strengths are distinct. The match of home `h` against away `a`
/// plays on `fork('season:$s:match:$h:$a')`. "Top by CA" ranks by the
/// drawn strength then club id.
SeasonCalibration runSeasonCalibration({
  required int seasons,
  required int seed,
}) {
  const clubCount = 20;
  final root = SeededRng(seed);
  final out = <SeasonSummary>[];
  for (var s = 0; s < seasons; s++) {
    final draw = root.fork('season:$s');
    final players = <PlayerId, Player>{};
    final attrs = <ClubId, double>{};
    final clubs = <ClubId, Club>{};
    for (var c = 1; c <= clubCount; c++) {
      final level = (12 + draw.nextGaussian(sd: 1.3)).clamp(8.0, 17.0);
      attrs[c] = level;
      final attr = level.floor();
      clubs[c] = syntheticClub(
        id: c,
        attr: attr,
        plusOne: ((level - attr) * 18).round(),
        players: players,
      );
    }
    final w = syntheticWorld(players: players, clubs: clubs, seed: seed);

    final points = {for (final c in clubs.keys) c: 0};
    final gf = {for (final c in clubs.keys) c: 0};
    final ga = {for (final c in clubs.keys) c: 0};
    final scorerGoals = <PlayerId, int>{};
    for (var h = 1; h <= clubCount; h++) {
      for (var a = 1; a <= clubCount; a++) {
        if (h == a) continue;
        final r = _play(w, h, a, root.fork('season:$s:match:$h:$a'));
        gf[h] = gf[h]! + r.homeGoals;
        ga[h] = ga[h]! + r.awayGoals;
        gf[a] = gf[a]! + r.awayGoals;
        ga[a] = ga[a]! + r.homeGoals;
        if (r.homeGoals > r.awayGoals) {
          points[h] = points[h]! + 3;
        } else if (r.homeGoals < r.awayGoals) {
          points[a] = points[a]! + 3;
        } else {
          points[h] = points[h]! + 1;
          points[a] = points[a]! + 1;
        }
        for (final g in r.goals) {
          scorerGoals[g.scorerId] = (scorerGoals[g.scorerId] ?? 0) + 1;
        }
      }
    }
    final table = clubs.keys.toList()
      ..sort((x, y) {
        var c = points[y]!.compareTo(points[x]!);
        if (c != 0) return c;
        c = (gf[y]! - ga[y]!).compareTo(gf[x]! - ga[x]!);
        if (c != 0) return c;
        c = gf[y]!.compareTo(gf[x]!);
        return c != 0 ? c : x.compareTo(y);
      });
    final byCa = clubs.keys.toList()
      ..sort((x, y) {
        final c = attrs[y]!.compareTo(attrs[x]!);
        return c != 0 ? c : x.compareTo(y);
      });
    final top4 = table.take(4).toSet();
    out.add(
      SeasonSummary(
        championPoints: points[table.first]!,
        lastPoints: points[table.last]!,
        medianPoints: (points[table[9]]! + points[table[10]]!) / 2,
        top3InTop4Count: byCa.take(3).where(top4.contains).length,
        top1Champion: table.first == byCa.first,
        topScorerGoals: scorerGoals.values.fold(0, (a, b) => a > b ? a : b),
      ),
    );
  }
  return SeasonCalibration(seed: seed, seasons: out);
}
