import 'package:engine/engine.dart';
import 'package:test/test.dart';

World _world() => createNewGame(
  NewGameSpec(
    seed: 11,
    size: WorldSize.small,
    managerFirstName: 'A',
    managerLastName: 'B',
    managerCountryCode: 'TR',
    startClubId: null,
  ),
);

/// A copy of [f] dated in [month] of its season.
Fixture _inMonth(Fixture f, int month) => Fixture(
  id: f.id,
  leagueId: f.leagueId,
  seasonYear: f.seasonYear,
  round: f.round,
  date: GameDate.ymd(month >= 7 ? f.seasonYear : f.seasonYear + 1, month, 15),
  homeId: f.homeId,
  awayId: f.awayId,
);

void main() {
  final w = _world();
  final f0 = w.fixtures.values.first;
  final country = w.countries[w.leagues[f0.leagueId]!.countryId]!;

  Map<Weather, int> draws(String climate, int month, {int n = 2000}) {
    country.climate = climate;
    final f = _inMonth(f0, month);
    final rng = SeededRng(99);
    final counts = {for (final x in Weather.values) x: 0};
    for (var i = 0; i < n; i++) {
      final c = sampleConditions(w: w, f: f, rng: rng);
      counts[c.weather] = counts[c.weather]! + 1;
    }
    return counts;
  }

  test('countries carry their template climate', () {
    final byCode = {for (final c in w.countries.values) c.code: c.climate};
    expect(byCode['TR'], 'mediterranean');
    expect(byCode['ENG'], 'temperate');
  });

  test('temperate July is mostly sunny or hot and never snowy', () {
    final c = draws('temperate', 7);
    expect(c[Weather.sunny]! + c[Weather.hot]!, greaterThanOrEqualTo(1000));
    expect(c[Weather.snow], 0);
  });

  test('continental December snows at least 10 % of the time', () {
    expect(draws('continental', 12)[Weather.snow], greaterThanOrEqualTo(200));
  });

  test('tropical never snows; arid is mostly sunny or hot', () {
    for (var m = 1; m <= 12; m++) {
      expect(draws('tropical', m, n: 300)[Weather.snow], 0, reason: 'm$m');
      final a = draws('arid', m, n: 300);
      expect(a[Weather.sunny]! + a[Weather.hot]!, greaterThan(150));
    }
  });

  test('pitch, attendance and home advantage stay in bounds', () {
    final home = w.clubs[f0.homeId]!;
    final rep = home.reputation;
    for (final climate in [
      'temperate',
      'mediterranean',
      'continental',
      'tropical',
      'arid',
    ]) {
      country.climate = climate;
      for (final r in [1, 50, 100]) {
        home.reputation = r;
        for (var m = 1; m <= 12; m++) {
          final f = _inMonth(f0, m);
          final rng = SeededRng(m * 31 + r);
          for (var i = 0; i < 50; i++) {
            final c = sampleConditions(w: w, f: f, rng: rng);
            expect(c.pitch, inInclusiveRange(1, 10));
            expect(c.attendance, inInclusiveRange(0, home.stadiumCapacity));
            expect(c.homeAdvantage, inInclusiveRange(1.03, 1.08));
          }
        }
      }
    }
    home.reputation = rep;
  });

  test('pitch follows reputation, season wear and rain', () {
    final home = w.clubs[f0.homeId]!;
    home.reputation = 80;
    country.climate = 'temperate';
    final seen = <(int, Weather), int>{};
    for (final m in [1, 3, 7]) {
      final f = _inMonth(f0, m);
      final rng = SeededRng(m);
      for (var i = 0; i < 300; i++) {
        final c = sampleConditions(w: w, f: f, rng: rng);
        seen[(m, c.weather)] = c.pitch;
      }
    }
    expect(seen[(7, Weather.sunny)], 8);
    expect(seen[(7, Weather.rainy)], 7);
    expect(seen[(3, Weather.cloudy)], 7);
    expect(seen[(1, Weather.heavyRain)], 4);
  });

  test('same rng seed gives the same conditions', () {
    country.climate = 'temperate';
    final f = _inMonth(f0, 11);
    String run(int seed) {
      final rng = SeededRng(seed).fork('conditions:${f.id}:${f.seasonYear}');
      final c = sampleConditions(w: w, f: f, rng: rng);
      return '${c.weather} ${c.pitch} ${c.attendance} ${c.homeAdvantage}';
    }

    expect(run(7), run(7));
    final distinct = {for (var s = 0; s < 40; s++) run(s)};
    expect(distinct.length, greaterThan(1));
  });

  test('attendance follows the fill formula with neutral form', () {
    country.climate = 'arid';
    final home = w.clubs[f0.homeId]!;
    final away = w.clubs[f0.awayId]!;
    final f = _inMonth(f0, 7);
    final rng = SeededRng(3);
    for (var i = 0; i < 100; i++) {
      final c = sampleConditions(w: w, f: f, rng: rng);
      final penalty = switch (c.weather) {
        Weather.heavyRain || Weather.snow => 0.10,
        Weather.rainy => 0.05,
        _ => 0.0,
      };
      final fill =
          (0.35 +
                  0.45 * home.reputation / 100 +
                  0.10 * away.reputation / 100 +
                  0.10 * 0.5 -
                  penalty)
              .clamp(0.2, 1.0);
      expect(c.attendance, (home.stadiumCapacity * fill).round());
      expect(c.homeAdvantage, closeTo(1.03 + 0.05 * fill, 1e-12));
    }
  });

  test('home form counts wins in the last 5 played fixtures', () {
    country.climate = 'arid';
    final home = w.clubs[f0.homeId]!;
    final away = w.clubs[f0.awayId]!;
    final f = _inMonth(f0, 7);
    final others = [
      for (final id in w.fixturesOfClub(home.id, f0.seasonYear))
        if (id != f0.id) w.fixtures[id]!,
    ]..sort((a, b) => a.date.dayIndex.compareTo(b.date.dayIndex));
    // Oldest of six played is a loss, the latest five: 3 wins, 1 draw, 1 loss.
    final scores = [(0, 3), (2, 0), (1, 0), (1, 1), (0, 1), (4, 2)];
    for (var i = 0; i < scores.length; i++) {
      final o = others[i];
      final (forGoals, against) = scores[i];
      final atHome = o.homeId == home.id;
      o.result = MatchResult(
        homeGoals: atHome ? forGoals : against,
        awayGoals: atHome ? against : forGoals,
        goals: [],
        matchSeed: 0,
      );
    }
    try {
      final rng = SeededRng(5);
      for (var i = 0; i < 50; i++) {
        final c = sampleConditions(w: w, f: f, rng: rng);
        final penalty = switch (c.weather) {
          Weather.heavyRain || Weather.snow => 0.10,
          Weather.rainy => 0.05,
          _ => 0.0,
        };
        final fill =
            (0.35 +
                    0.45 * home.reputation / 100 +
                    0.10 * away.reputation / 100 +
                    0.10 * 3 / 5 -
                    penalty)
                .clamp(0.2, 1.0);
        expect(c.attendance, (home.stadiumCapacity * fill).round());
      }
    } finally {
      for (final o in others) {
        o.result = null;
      }
    }
  });
}
