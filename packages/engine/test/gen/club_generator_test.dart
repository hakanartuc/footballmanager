import 'dart:convert';

import 'package:engine/engine.dart';
import 'package:test/test.dart';

/// Relative luminance without gamma, as used by the generator.
double _lum(int argb) {
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
}

void main() {
  final pool = CountryData.load().pools['tr']!;

  /// 60 clubs: three tiers of 20 in a country of reputation 70.
  List<Club> sample({int seed = 1}) {
    final gen = ClubGenerator(pool, SeededRng(seed), IdAllocator());
    final used = <String>{};
    return [
      for (var tier = 1; tier <= 3; tier++)
        for (var i = 0; i < 20; i++)
          gen.generate(
            countryId: 1,
            leagueId: tier,
            tier: tier,
            countryReputation: 70,
            indexInLeague: i,
            leagueSize: 20,
            usedNames: used,
          ),
    ];
  }

  final clubs = sample();

  test('names are unique across 60 clubs and built from a city', () {
    expect(clubs.map((c) => c.name).toSet(), hasLength(60));
    for (final c in clubs) {
      expect(c.name, isNot(contains('{City}')));
      expect(c.shortName, hasLength(3));
      expect(c.shortName, c.shortName.toUpperCase());
      expect(c.stadiumName, isNot(contains('{City}')));
      final city = pool.cityNames.firstWhere((n) => c.name.contains(n));
      expect(c.shortName, city.substring(0, 3).toUpperCase());
      expect(c.stadiumName, contains(city));
      expect(
        pool.clubSuffixes.any((s) => s.replaceAll('{City}', city) == c.name),
        isTrue,
        reason: c.name,
      );
    }
  });

  test('generate adds the name to usedNames', () {
    final gen = ClubGenerator(pool, SeededRng(1), IdAllocator());
    final used = <String>{};
    final c = gen.generate(
      countryId: 1,
      leagueId: 1,
      tier: 1,
      countryReputation: 70,
      indexInLeague: 0,
      leagueSize: 18,
      usedNames: used,
    );
    expect(used, {c.name});
  });

  test('reputation: top club countryRep+5, linear to countryRep-25', () {
    final tier1 = clubs.sublist(0, 20);
    expect(tier1.first.reputation, 75);
    expect(tier1.last.reputation, 45);
    for (var i = 1; i < 20; i++) {
      expect(tier1[i].reputation, lessThan(tier1[i - 1].reputation));
    }
    expect(clubs[20].reputation, 50); // tier 2 = tier 1 - 25
    expect(clubs[40].reputation, 35); // tier 3 = tier 1 - 40
    expect(clubs[59].reputation, 5); // clamped
    for (final c in clubs) {
      expect(c.reputation, inInclusiveRange(5, 100));
    }
  });

  test('kits: home != away, each kit contrasts >= 0.4', () {
    for (final c in clubs) {
      expect(c.home.primary, isNot(c.away.primary));
      expect(
        (_lum(c.home.primary) - _lum(c.home.secondary)).abs(),
        greaterThanOrEqualTo(0.4),
      );
      expect(
        (_lum(c.away.primary) - _lum(c.away.secondary)).abs(),
        greaterThanOrEqualTo(0.4),
      );
      expect(
        (_lum(c.home.primary) - _lum(c.away.primary)).abs(),
        greaterThanOrEqualTo(0.4),
      );
      expect(c.logo.shape, inInclusiveRange(0, 7));
      expect(c.logo.color1, c.home.primary);
      expect(c.logo.color2, c.home.secondary);
    }
    expect(clubs.map((c) => c.home.primary).toSet().length, greaterThan(8));
  });

  test('capacity ranges by tier, scaled by reputation', () {
    for (final c in clubs.sublist(0, 20)) {
      expect(c.stadiumCapacity, inInclusiveRange(25000, 60000));
    }
    for (final c in clubs.sublist(20, 40)) {
      expect(c.stadiumCapacity, inInclusiveRange(8000, 25000));
    }
    for (final c in clubs.sublist(40, 60)) {
      expect(c.stadiumCapacity, inInclusiveRange(3000, 10000));
    }
    expect(clubs[0].stadiumCapacity, greaterThan(clubs[19].stadiumCapacity));
    expect(clubs[0].stadiumCapacity, 25000 + ((75 - 30) / 70 * 35000).round());
  });

  test('budgets and facilities from reputation', () {
    for (final c in clubs) {
      final meanWage = wageForCa((c.reputation * 1.3 + 30).round());
      expect(c.wageBudget, (24 * meanWage * 1.1).round());
      expect(c.transferBudget, c.reputation * c.reputation * 100);
      expect(c.balance, c.transferBudget);
      final f = c.facilities;
      final base = (c.reputation / 10).round();
      for (final v in [f.training, f.medical, f.youth]) {
        expect(v, inInclusiveRange(1, 10));
        expect(v, inInclusiveRange(base - 1, base + 1));
      }
    }
  });

  test('expectation from index in league; defaults', () {
    final tier1 = clubs.sublist(0, 20);
    expect(tier1[0].expectation, BoardExpectation.title);
    expect(tier1[1].expectation, BoardExpectation.title);
    expect(tier1[2].expectation, BoardExpectation.top);
    expect(tier1[5].expectation, BoardExpectation.top);
    expect(tier1[6].expectation, BoardExpectation.upperMid);
    expect(tier1[9].expectation, BoardExpectation.upperMid);
    expect(tier1[10].expectation, BoardExpectation.mid);
    expect(tier1[13].expectation, BoardExpectation.mid);
    expect(tier1[14].expectation, BoardExpectation.avoidRelegation);
    expect(tier1[19].expectation, BoardExpectation.avoidRelegation);
    var lastId = 0;
    for (final c in clubs) {
      expect(c.formation, Formation.f442);
      expect(c.activeTactic, 0);
      expect(c.tactics.map((t) => t.name), ['1', '2', '3']);
      expect(c.tactics.map((t) => t.formation), [
        Formation.f442,
        Formation.f433,
        Formation.f532,
      ]);
      expect(c.managerId, isNull);
      expect(c.lineup, isNull);
      expect(c.boardConfidence, 50);
      expect(c.countryId, 1);
      expect(c.id, lastId + 1);
      lastId = c.id;
    }
    expect(clubs[25].leagueId, 2);
  });

  test('same seed gives the same first club', () {
    final a = jsonEncode(clubToJson(sample().first));
    expect(jsonEncode(clubToJson(sample().first)), a);
    expect(jsonEncode(clubToJson(sample(seed: 2).first)), isNot(a));
  });
}
