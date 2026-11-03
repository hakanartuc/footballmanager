import 'package:engine/engine.dart';
import 'package:test/test.dart';

void main() {
  test('attributes clamp to 1..20', () {
    final a = Attributes.filled(10);
    a.set(Attr.pace, 25);
    a.set(Attr.finishing, 0);
    a.set(Attr.passing, -3);
    expect(a[Attr.pace], 20);
    expect(a[Attr.finishing], 1);
    expect(a[Attr.passing], 1);
    expect(a[Attr.tackling], 10);
    expect(Attributes.filled(99)[Attr.reflexes], 20);
    expect(Attributes.filled(0)[Attr.reflexes], 1);
  });

  test('fromList round trips and validates length', () {
    final values = List<int>.generate(Attr.values.length, (i) => i % 20 + 1);
    expect(Attributes.fromList(values).toList(), values);
    expect(() => Attributes.fromList([1, 2, 3]), throwsArgumentError);
  });

  test('toList returns a copy', () {
    final a = Attributes.filled(10);
    a.toList()[0] = 1;
    expect(a[Attr.values[0]], 10);
  });

  test('computeCa extremes', () {
    expect(computeCa(Attributes.filled(20), Position.st), 200);
    expect(computeCa(Attributes.filled(1), Position.gk), 10);
    for (final p in Position.values) {
      expect(computeCa(Attributes.filled(20), p), 200);
      expect(computeCa(Attributes.filled(1), p), 10);
      expect(computeCa(Attributes.filled(15), p), 150);
    }
  });

  test('GK weights ignore outfield attributes', () {
    final a = Attributes.filled(12)..set(Attr.finishing, 1);
    final b = Attributes.filled(12)..set(Attr.finishing, 20);
    expect(computeCa(a, Position.gk), computeCa(b, Position.gk));
    // Sanity: finishing does matter for a striker.
    expect(computeCa(b, Position.st), greaterThan(computeCa(a, Position.st)));
  });

  test('computeCa is the weighted mean x 10', () {
    // DEF weights: tackling 3, positioning 3, heading 2, strength 2,
    // concentration 2, pace 1, anticipation 1, passing 1 (sum 15).
    final a = Attributes.filled(10)..set(Attr.tackling, 20);
    // (3*20 + 12*10) / 15 = 12.0 -> 120
    expect(computeCa(a, Position.dc), 120);
  });

  test('position group mapping', () {
    expect(Position.gk.group, PositionGroup.gk);
    for (final p in [Position.dl, Position.dc, Position.dr]) {
      expect(p.group, PositionGroup.def);
    }
    for (final p in [Position.dm, Position.ml, Position.mc, Position.mr]) {
      expect(p.group, PositionGroup.mid);
    }
    for (final p in [Position.aml, Position.amc, Position.amr, Position.st]) {
      expect(p.group, PositionGroup.att);
    }
  });

  test('formationSlots has 11 slots with exactly one gk first', () {
    expect(formationSlots(Formation.f442), [
      Position.gk,
      Position.dl,
      Position.dc,
      Position.dc,
      Position.dr,
      Position.ml,
      Position.mc,
      Position.mc,
      Position.mr,
      Position.st,
      Position.st,
    ]);
    for (final f in Formation.values) {
      if (f == Formation.custom) continue;
      final slots = formationSlots(f);
      expect(slots, hasLength(11), reason: '$f');
      expect(slots.first, Position.gk, reason: '$f');
      expect(slots.where((p) => p == Position.gk), hasLength(1), reason: '$f');
    }
  });

  test('formationSlots rejects custom, which is listed last', () {
    expect(Formation.values.last, Formation.custom);
    expect(() => formationSlots(Formation.custom), throwsArgumentError);
  });
}
