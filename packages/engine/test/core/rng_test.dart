import 'dart:math' as math;

import 'package:engine/engine.dart';
import 'package:test/test.dart';

void main() {
  test('same seed same sequence', () {
    final a = SeededRng(12345);
    final b = SeededRng(12345);
    for (var i = 0; i < 1000; i++) {
      expect(a.nextUint32(), b.nextUint32());
    }
  });

  test('fork is independent of parent consumption', () {
    final fresh = SeededRng(7).fork('a');
    final parent = SeededRng(7);
    for (var i = 0; i < 50; i++) {
      parent.nextUint32();
    }
    final consumed = parent.fork('a');
    for (var i = 0; i < 10; i++) {
      expect(consumed.nextUint32(), fresh.nextUint32());
    }
  });

  test('forks with different names differ', () {
    final parent = SeededRng(7);
    final a = parent.fork('a');
    final b = parent.fork('b');
    final seqA = List.generate(10, (_) => a.nextUint32());
    final seqB = List.generate(10, (_) => b.nextUint32());
    expect(seqA, isNot(equals(seqB)));
  });

  test('known vector', () {
    expect(
      SeededRng(42).nextUint32(),
      isA<int>().having((v) => v, 'v', inInclusiveRange(0, 0xFFFFFFFF)),
    );
    // Recorded once from the reference implementation; pins cross-platform
    // determinism (native and web must both reproduce these).
    final rng = SeededRng(42);
    expect(List.generate(5, (_) => rng.nextUint32()), [
      2726265396,
      265113989,
      4262593846,
      1494547604,
      863275254,
    ]);
  });

  test('nextInt is unbiased', () {
    final rng = SeededRng(99);
    const draws = 100000;
    final buckets = List.filled(7, 0);
    for (var i = 0; i < draws; i++) {
      buckets[rng.nextInt(7)]++;
    }
    for (final count in buckets) {
      expect(count / draws, inInclusiveRange(0.135, 0.151));
    }
  });

  test('nextInt rejects non-positive max', () {
    expect(() => SeededRng(1).nextInt(0), throwsArgumentError);
    expect(() => SeededRng(1).nextInt(-3), throwsArgumentError);
  });

  test('mul32 matches BigInt', () {
    final random = math.Random(2024);
    for (var i = 0; i < 1000; i++) {
      final a = random.nextInt(0x100000000);
      final b = random.nextInt(0x100000000);
      final expected =
          (BigInt.from(a) * BigInt.from(b)) & BigInt.from(0xFFFFFFFF);
      expect(mul32(a, b), expected.toInt(), reason: 'mul32($a, $b)');
    }
    expect(mul32(0xFFFFFFFF, 0xFFFFFFFF), 1);
  });

  test('nextPoisson mean', () {
    final rng = SeededRng(5);
    const draws = 20000;
    var sum = 0;
    for (var i = 0; i < draws; i++) {
      sum += rng.nextPoisson(2.7);
    }
    expect(sum / draws, inInclusiveRange(2.65, 2.75));
  });

  test('nextPoisson large lambda and non-positive lambda', () {
    final rng = SeededRng(5);
    const draws = 20000;
    var sum = 0;
    for (var i = 0; i < draws; i++) {
      final v = rng.nextPoisson(50);
      expect(v, greaterThanOrEqualTo(0));
      sum += v;
    }
    expect(sum / draws, inInclusiveRange(49.5, 50.5));
    expect(rng.nextPoisson(0), 0);
    expect(rng.nextPoisson(-1), 0);
  });

  test('nextGaussian sd', () {
    final rng = SeededRng(8);
    const draws = 20000;
    var sum = 0.0;
    var sumSq = 0.0;
    for (var i = 0; i < draws; i++) {
      final v = rng.nextGaussian();
      sum += v;
      sumSq += v * v;
    }
    final mean = sum / draws;
    final sd = math.sqrt(sumSq / draws - mean * mean);
    expect(mean, inInclusiveRange(-0.03, 0.03));
    expect(sd, inInclusiveRange(0.97, 1.03));
  });

  test('weightedIndex proportions', () {
    final rng = SeededRng(3);
    const draws = 20000;
    var second = 0;
    for (var i = 0; i < draws; i++) {
      if (rng.weightedIndex([1, 3]) == 1) second++;
    }
    expect(second / draws, inInclusiveRange(0.73, 0.77));
  });

  test('weightedIndex never picks zero weight and validates input', () {
    final rng = SeededRng(3);
    for (var i = 0; i < 1000; i++) {
      expect(rng.weightedIndex([0, 1, 0]), 1);
    }
    expect(() => rng.weightedIndex([]), throwsArgumentError);
    expect(() => rng.weightedIndex([0, 0]), throwsArgumentError);
    expect(() => rng.weightedIndex([1, -1]), throwsArgumentError);
  });

  test('nextDouble is in [0,1) and nextBool follows pTrue', () {
    final rng = SeededRng(11);
    var trues = 0;
    for (var i = 0; i < 20000; i++) {
      final d = rng.nextDouble();
      expect(d, greaterThanOrEqualTo(0));
      expect(d, lessThan(1));
      if (rng.nextBool(0.3)) trues++;
    }
    expect(trues / 20000, inInclusiveRange(0.28, 0.32));
    expect(rng.nextBool(0), isFalse);
    expect(rng.nextBool(1), isTrue);
  });

  test('pick and shuffle use every element', () {
    final rng = SeededRng(13);
    final items = List.generate(20, (i) => i);
    final seen = <int>{};
    for (var i = 0; i < 2000; i++) {
      seen.add(rng.pick(items));
    }
    expect(seen, items.toSet());

    final shuffled = List.of(items);
    rng.shuffle(shuffled);
    expect(shuffled, isNot(equals(items)));
    expect(shuffled..sort(), items);
  });

  test('state restore replays', () {
    final rng = SeededRng(21);
    for (var i = 0; i < 17; i++) {
      rng.nextUint32();
    }
    final saved = rng.state;
    final first = List.generate(10, (_) => rng.nextUint32());
    rng.nextGaussian();
    rng.shuffle([1, 2, 3, 4]);
    rng.restore(saved);
    final replay = List.generate(10, (_) => rng.nextUint32());
    expect(replay, first);
  });

  test('all ops stay within 32-bit', () {
    final rng = SeededRng(0xDEADBEEF);
    for (var i = 0; i < 100000; i++) {
      expect(rng.nextUint32(), inInclusiveRange(0, 0xFFFFFFFF));
    }
    final s = rng.state;
    for (final word in [s.s0, s.s1, s.s2, s.s3]) {
      expect(word, inInclusiveRange(0, 0xFFFFFFFF));
    }
  });

  test('zero seed still produces a non-degenerate stream', () {
    final rng = SeededRng(0);
    final values = List.generate(10, (_) => rng.nextUint32()).toSet();
    expect(values.length, greaterThan(1));
  });

  test('fnv1a32 and splitmix32 reference values', () {
    // FNV-1a 32-bit reference vectors.
    expect(fnv1a32(''), 0x811C9DC5);
    expect(fnv1a32('a'), 0xE40C292C);
    expect(fnv1a32('foobar'), 0xBF9CF968);
    expect(splitmix32(0), inInclusiveRange(0, 0xFFFFFFFF));
    expect(splitmix32(0), isNot(splitmix32(1)));
  });
}
