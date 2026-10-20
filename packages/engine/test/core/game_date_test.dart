import 'package:engine/engine.dart';
import 'package:test/test.dart';

void main() {
  test('ymd round trip', () {
    const dates = [
      (2000, 1, 1),
      (1999, 12, 31),
      (1985, 6, 15),
      (2000, 2, 29),
      (2023, 12, 31),
      (2024, 2, 29),
      (2024, 3, 1),
      (2026, 10, 20),
      (2099, 12, 31),
      (2100, 3, 1),
    ];
    for (final (y, m, d) in dates) {
      final date = GameDate.ymd(y, m, d);
      expect((date.year, date.month, date.day), (y, m, d));
      expect(GameDate(date.dayIndex), date);
    }
    expect(GameDate.ymd(2000, 1, 1).dayIndex, 0);
    expect(GameDate.ymd(2000, 1, 2).dayIndex, 1);
    expect(GameDate.ymd(1999, 12, 31).dayIndex, -1);
    expect(GameDate.ymd(2001, 1, 1).dayIndex, 366);
  });

  test('2000-01-01 is Saturday', () {
    expect(const GameDate(0).weekday, Weekday.sat);
    expect(const GameDate(1).weekday, Weekday.sun);
    expect(const GameDate(2).weekday, Weekday.mon);
    expect(const GameDate(-1).weekday, Weekday.fri);
    expect(GameDate.ymd(2026, 10, 20).weekday, Weekday.tue);
  });

  test('Feb 29 2028 exists and 2100 has no Feb 29', () {
    final leap = GameDate.ymd(2028, 2, 29);
    expect((leap.year, leap.month, leap.day), (2028, 2, 29));
    expect(() => GameDate.ymd(2100, 2, 29), throwsArgumentError);
    expect(() => GameDate.ymd(2026, 2, 30), throwsArgumentError);
    expect(() => GameDate.ymd(2026, 13, 1), throwsArgumentError);
    expect(() => GameDate.ymd(2026, 4, 0), throwsArgumentError);
  });

  test('nextWeekday from Saturday to Saturday is +7', () {
    const sat = GameDate(0);
    expect(sat.nextWeekday(Weekday.sat), sat.addDays(7));
    expect(sat.nextWeekday(Weekday.sun), sat.addDays(1));
    expect(sat.nextWeekday(Weekday.fri), sat.addDays(6));
  });

  test('seasonYear of 2026-05-20 is 2025 and 2026-08-01 is 2026', () {
    expect(GameDate.ymd(2026, 5, 20).seasonYear, 2025);
    expect(GameDate.ymd(2026, 8, 1).seasonYear, 2026);
    expect(GameDate.ymd(2026, 6, 30).seasonYear, 2025);
    expect(GameDate.ymd(2026, 7, 1).seasonYear, 2026);
  });

  test('ageAt before/after birthday', () {
    final birth = GameDate.ymd(2008, 3, 15);
    expect(ageAt(birth, GameDate.ymd(2026, 3, 14)), 17);
    expect(ageAt(birth, GameDate.ymd(2026, 3, 15)), 18);
    expect(ageAt(birth, GameDate.ymd(2026, 12, 31)), 18);
    expect(ageAt(birth, birth), 0);
  });

  test('addDays, daysUntil, isBefore, isAfter', () {
    final a = GameDate.ymd(2024, 2, 28);
    final b = a.addDays(2);
    expect(b, GameDate.ymd(2024, 3, 1));
    expect(a.daysUntil(b), 2);
    expect(b.daysUntil(a), -2);
    expect(a.isBefore(b), isTrue);
    expect(b.isAfter(a), isTrue);
    expect(a.isBefore(a), isFalse);
    expect(a.isAfter(a), isFalse);
  });

  test('iso formats as yyyy-mm-dd', () {
    expect(GameDate.ymd(2026, 3, 5).iso, '2026-03-05');
    expect(GameDate.ymd(1999, 12, 31).iso, '1999-12-31');
  });
}
