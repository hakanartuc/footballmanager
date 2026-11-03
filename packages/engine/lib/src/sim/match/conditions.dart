import '../../core/rng.dart';
import '../../model/fixture.dart';
import '../../model/match_conditions.dart';
import '../../model/world.dart';

/// Weather weights per climate, one row per month (January first), columns
/// in [Weather] order: sunny, cloudy, rainy, heavyRain, snow, windy, hot.
const Map<String, List<List<int>>> weatherWeights = {
  'temperate': [
    [10, 35, 25, 8, 10, 12, 0],
    [12, 33, 25, 8, 10, 12, 0],
    [18, 32, 25, 7, 4, 14, 0],
    [25, 30, 28, 6, 1, 10, 0],
    [35, 28, 22, 5, 0, 8, 2],
    [42, 22, 18, 4, 0, 6, 8],
    [45, 20, 12, 3, 0, 6, 14],
    [43, 20, 14, 4, 0, 6, 13],
    [32, 28, 22, 5, 0, 9, 4],
    [18, 32, 28, 8, 0, 14, 0],
    [10, 35, 30, 10, 3, 12, 0],
    [8, 35, 27, 9, 9, 12, 0],
  ],
  'mediterranean': [
    [30, 30, 20, 6, 3, 11, 0],
    [32, 28, 20, 6, 3, 11, 0],
    [40, 26, 18, 4, 1, 11, 0],
    [45, 25, 17, 3, 0, 9, 1],
    [52, 20, 12, 2, 0, 7, 7],
    [50, 12, 5, 1, 0, 6, 26],
    [48, 8, 2, 1, 0, 6, 35],
    [48, 8, 3, 1, 0, 5, 35],
    [52, 15, 8, 2, 0, 7, 16],
    [42, 25, 18, 4, 0, 9, 2],
    [32, 28, 24, 6, 1, 9, 0],
    [28, 30, 22, 6, 3, 11, 0],
  ],
  'continental': [
    [12, 32, 10, 3, 30, 13, 0],
    [14, 30, 12, 3, 27, 14, 0],
    [20, 30, 20, 4, 12, 14, 0],
    [28, 28, 24, 5, 3, 12, 0],
    [38, 25, 22, 5, 0, 8, 2],
    [42, 20, 20, 6, 0, 5, 7],
    [44, 16, 18, 6, 0, 4, 12],
    [44, 17, 18, 6, 0, 4, 11],
    [38, 26, 20, 5, 0, 8, 3],
    [26, 32, 24, 5, 2, 11, 0],
    [14, 36, 22, 4, 12, 12, 0],
    [10, 34, 12, 3, 28, 13, 0],
  ],
  'tropical': [
    [30, 20, 18, 10, 0, 4, 18],
    [30, 20, 18, 10, 0, 4, 18],
    [30, 22, 20, 10, 0, 4, 14],
    [30, 24, 20, 10, 0, 4, 12],
    [34, 24, 18, 8, 0, 4, 12],
    [36, 26, 16, 6, 0, 6, 10],
    [38, 26, 14, 5, 0, 7, 10],
    [38, 26, 14, 5, 0, 7, 10],
    [36, 24, 16, 6, 0, 6, 12],
    [32, 22, 18, 8, 0, 5, 15],
    [30, 20, 18, 10, 0, 4, 18],
    [30, 20, 18, 10, 0, 4, 18],
  ],
  'arid': [
    [55, 18, 5, 1, 0, 13, 8],
    [55, 17, 5, 1, 0, 12, 10],
    [55, 15, 4, 1, 0, 12, 13],
    [52, 12, 3, 1, 0, 12, 20],
    [48, 10, 3, 1, 0, 10, 28],
    [45, 10, 5, 2, 0, 8, 30],
    [45, 12, 6, 2, 0, 7, 28],
    [45, 12, 6, 2, 0, 7, 28],
    [48, 12, 5, 2, 0, 8, 25],
    [52, 14, 4, 1, 0, 10, 19],
    [55, 16, 4, 1, 0, 12, 12],
    [55, 18, 5, 1, 0, 13, 8],
  ],
};

/// The northern-hemisphere month whose season [month] corresponds to:
/// [month] itself in the north, six months on in the south.
int seasonMonth(int month, {required bool south}) =>
    south ? ((month + 5) % 12) + 1 : month;

/// Samples the conditions of [f] from [rng], which the caller forks as
/// `SeededRng(w.seed).fork('conditions:${f.id}:${f.seasonYear}')`.
MatchConditions sampleConditions({
  required World w,
  required Fixture f,
  required SeededRng rng,
}) {
  final home = w.clubs[f.homeId]!;
  final away = w.clubs[f.awayId]!;
  final country = w.countries[w.leagues[f.leagueId]!.countryId]!;
  final month = seasonMonth(f.date.month, south: country.southernHemisphere);

  final weights = weatherWeights[country.climate]![month - 1];
  final weather = Weather
      .values[rng.weightedIndex([for (final x in weights) x.toDouble()])];

  final wear = switch (month) {
    12 || 1 || 2 => 2,
    11 || 3 => 1,
    _ => 0,
  };
  final rain = switch (weather) {
    Weather.heavyRain => 2,
    Weather.rainy => 1,
    _ => 0,
  };
  final pitch = ((home.reputation / 10).round() - wear - rain).clamp(1, 10);

  final weatherPenalty = switch (weather) {
    Weather.heavyRain || Weather.snow => 0.10,
    Weather.rainy => 0.05,
    _ => 0.0,
  };
  final fill =
      (0.35 +
              0.45 * home.reputation / 100 +
              0.10 * away.reputation / 100 +
              0.10 * _homeFormFactor(w, f) -
              weatherPenalty)
          .clamp(0.2, 1.0);

  return MatchConditions(
    weather: weather,
    pitch: pitch,
    attendance: (home.stadiumCapacity * fill).round(),
    homeAdvantage: 1.03 + 0.05 * fill,
  );
}

/// Wins among the home club's last 5 played fixtures of [f]'s season, over
/// 5; 0.5 when it has played none.
double _homeFormFactor(World w, Fixture f) {
  final club = f.homeId;
  final played = [
    for (final id in w.fixturesOfClub(club, f.seasonYear))
      if (id != f.id && w.fixtures[id]!.result != null) w.fixtures[id]!,
  ]..sort((a, b) => a.date.dayIndex.compareTo(b.date.dayIndex));
  if (played.isEmpty) return 0.5;
  var wins = 0;
  for (final p in played.skip(played.length > 5 ? played.length - 5 : 0)) {
    final r = p.result!;
    final (mine, theirs) = p.homeId == club
        ? (r.homeGoals, r.awayGoals)
        : (r.awayGoals, r.homeGoals);
    if (mine > theirs) wins++;
  }
  return wins / 5;
}
