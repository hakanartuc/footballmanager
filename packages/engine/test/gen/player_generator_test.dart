import 'dart:convert';

import 'package:engine/engine.dart';
import 'package:test/test.dart';

const _rep80Ca = 80 * 1.3 + 30; // 134
const _rep30Ca = 30 * 1.3 + 30; // 69

/// Every attribute that is not in the GK weight table.
final _outfieldAttrs = Attr.values
    .where((a) => !caWeightsFor(PositionGroup.gk).containsKey(a))
    .toList();

void main() {
  final pool = CountryData.load().pools['tr']!;
  final today = GameDate.ymd(2026, 7, 1);

  List<Player> sample(int rep, {int seed = 1}) {
    final gen = PlayerGenerator(pool, SeededRng(seed), IdAllocator());
    return [
      for (var i = 0; i < 2000; i++)
        gen.generateForTier(
          clubReputation: rep,
          nationality: 1,
          position: Position.values[i % Position.values.length],
          today: today,
          clubId: 7,
        ),
    ];
  }

  final rep80 = sample(80);
  final rep30 = sample(30);

  test('ages are 18..34 with the mode near 25', () {
    final buckets = <int, int>{};
    for (final p in rep80) {
      final age = p.ageAt(today);
      expect(age, inInclusiveRange(18, 34));
      buckets[age] = (buckets[age] ?? 0) + 1;
    }
    int count(int lo, int hi) {
      var n = 0;
      for (var a = lo; a <= hi; a++) {
        n += buckets[a] ?? 0;
      }
      return n;
    }

    final mid = count(23, 27);
    expect(mid, greaterThan(count(18, 22)));
    expect(mid, greaterThan(count(28, 34)));
    expect(mid, greaterThan(count(30, 34)));
  });

  test('CA mean is within 3 of the club formula', () {
    double mean(List<Player> ps) =>
        ps.fold<int>(0, (s, p) => s + p.ca) / ps.length;
    expect(mean(rep80), closeTo(_rep80Ca, 3));
    expect(mean(rep30), closeTo(_rep30Ca, 3));
  });

  test('ca equals computeCa of the attributes, pa >= ca, pa <= 200', () {
    for (final p in [...rep80, ...rep30]) {
      expect(p.ca, computeCa(p.attrs, p.mainPosition));
      expect(p.pa, greaterThanOrEqualTo(p.ca));
      expect(p.pa, lessThanOrEqualTo(200));
    }
  });

  test('GK outfield attributes are 3..8', () {
    final gks = rep80.where((p) => p.mainPosition == Position.gk);
    expect(gks, isNotEmpty);
    for (final p in gks) {
      for (final a in _outfieldAttrs) {
        expect(p.attrs[a], inInclusiveRange(3, 8), reason: '$a');
      }
    }
  });

  test('wage formula', () {
    expect(wageForCa(100), 90);
    expect(wageForCa(150), 200);
    expect(wageForCa(180), 290);
    for (final p in rep80) {
      expect(p.contract!.wageWeekly, wageForCa(p.ca));
    }
  });

  test(
    'contract: club, start today, ends June 30 in 1..4 years, firstTeam',
    () {
      for (final p in rep80) {
        final c = p.contract!;
        expect(c.clubId, 7);
        expect(c.start, today);
        expect(c.end.month, 6);
        expect(c.end.day, 30);
        expect(c.end.year - today.year, inInclusiveRange(1, 4));
        expect(c.status, PlayerStatus.firstTeam);
      }
    },
  );

  test('familiarity: main 20, adjacency, every position present', () {
    final gen = PlayerGenerator(pool, SeededRng(1), IdAllocator());
    Player make(Position pos) => gen.generate(
      nationality: 1,
      position: pos,
      targetCa: 100,
      age: 25,
      today: today,
      clubId: null,
    );
    final dc = make(Position.dc);
    expect(dc.familiarity.keys.toSet(), Position.values.toSet());
    expect(dc.familiarity[Position.dc], 20);
    expect(dc.familiarity[Position.dl], 12);
    expect(dc.familiarity[Position.dr], 12);
    expect(dc.familiarity[Position.st], inInclusiveRange(1, 5));
    final mc = make(Position.mc);
    expect(mc.familiarity[Position.dm], 14);
    expect(mc.familiarity[Position.amc], 14);
    final st = make(Position.st);
    expect(st.familiarity[Position.amc], 10);
    expect(make(Position.aml).familiarity[Position.ml], 14);
    expect(make(Position.amc).familiarity[Position.st], 10);
    for (final p in rep80) {
      expect(p.familiarity[p.mainPosition], 20);
      for (final v in p.familiarity.values) {
        expect(v, inInclusiveRange(1, 20));
      }
    }
  });

  test('free agent when clubId is null', () {
    final gen = PlayerGenerator(pool, SeededRng(1), IdAllocator());
    final p = gen.generate(
      nationality: 1,
      position: Position.mc,
      targetCa: 100,
      age: 25,
      today: today,
      clubId: null,
    );
    expect(p.contract, isNull);
    expect(p.isYouth, isFalse);
    expect(p.ageAt(today), 25);
  });

  test('youth flag, youth status and age 15..17', () {
    final gen = PlayerGenerator(pool, SeededRng(1), IdAllocator());
    for (var i = 0; i < 200; i++) {
      final age = 15 + i % 3;
      final p = gen.generate(
        nationality: 1,
        position: Position.values[i % Position.values.length],
        targetCa: 50,
        age: age,
        today: today,
        clubId: 3,
        youth: true,
      );
      expect(p.isYouth, isTrue);
      expect(p.ageAt(today), age);
      expect(p.ageAt(today), inInclusiveRange(15, 17));
      expect(p.contract!.status, PlayerStatus.youth);
    }
  });

  test('height, hidden attrs, names and ids', () {
    var lastId = 0;
    for (final p in rep80) {
      expect(p.heightCm, inInclusiveRange(160, 205));
      expect(p.hidden.injuryProneness, inInclusiveRange(1, 20));
      expect(p.hidden.consistency, inInclusiveRange(1, 20));
      expect(p.hidden.bigMatches, inInclusiveRange(1, 20));
      expect(p.hidden.professionalism, inInclusiveRange(1, 20));
      expect(pool.firstNames, contains(p.firstName));
      expect(pool.lastNames, contains(p.lastName));
      expect(p.nationality, 1);
      expect(p.id, lastId + 1);
      lastId = p.id;
    }
    final gk = rep80.where((p) => p.mainPosition == Position.gk);
    final out = rep80.where((p) => p.mainPosition != Position.gk);
    double meanH(Iterable<Player> ps) =>
        ps.fold<int>(0, (s, p) => s + p.heightCm) / ps.length;
    expect(meanH(gk), greaterThan(meanH(out) + 4));
  });

  test('same seed gives the same first player', () {
    final a = jsonEncode(playerToJson(sample(80).first));
    final b = jsonEncode(playerToJson(sample(80).first));
    expect(a, b);
    expect(jsonEncode(playerToJson(sample(80, seed: 2).first)), isNot(a));
  });
}
