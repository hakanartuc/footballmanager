import 'package:engine/engine.dart';
import 'package:test/test.dart';

Player _player(GameDate birth) => Player(
  id: 1,
  firstName: 'Ali',
  lastName: 'Kaya',
  nationality: 1,
  birth: birth,
  heightCm: 180,
  mainPosition: Position.mc,
  familiarity: {Position.mc: 20},
  attrs: Attributes.filled(10),
  ca: 100,
  pa: 140,
  hidden: HiddenAttrs(
    injuryProneness: 10,
    consistency: 10,
    bigMatches: 10,
    professionalism: 10,
  ),
);

void main() {
  test('Player.ageAt a date', () {
    final p = _player(GameDate.ymd(2000, 6, 15));
    expect(p.ageAt(GameDate.ymd(2026, 6, 14)), 25);
    expect(p.ageAt(GameDate.ymd(2026, 6, 15)), 26);
  });

  test('Player defaults', () {
    final p = _player(GameDate.ymd(2000, 6, 15));
    expect(p.state.condition, 100);
    expect(p.state.sharpness, 100);
    expect(p.state.morale, 50);
    expect(p.state.form, 6.0);
    expect(p.state.yellowCards, 0);
    expect(p.state.suspensionMatches, 0);
    expect(p.state.injury, isNull);
    expect(p.contract, isNull);
    expect(p.isYouth, isFalse);
    expect(p.season.apps, 0);
    expect(p.season.ratingSum, 0);
    expect(p.career, isEmpty);
    expect(p.internationalCaps, 0);
    expect(p.internationalGoals, 0);
    expect(p.loan, isNull);
  });

  test('IdAllocator issues per-kind sequences from 1 and round trips', () {
    final ids = IdAllocator();
    expect(ids.next('player'), 1);
    expect(ids.next('player'), 2);
    expect(ids.next('club'), 1);
    expect(ids.next('player'), 3);
    expect(ids.toJson(), {'player': 3, 'club': 1});

    final restored = IdAllocator.fromJson(
      Map<String, dynamic>.from(ids.toJson()),
    );
    expect(restored.next('player'), 4);
    expect(restored.next('club'), 2);
    expect(restored.next('league'), 1);
  });
}
