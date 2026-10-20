import 'package:engine/engine.dart';
import 'package:test/test.dart';

bool _inBreak(GameDate d, SeasonCalendar cal) => cal.internationalBreaks.any(
  (b) => !d.isBefore(b.start) && !d.isAfter(b.end),
);

bool _isBlank(GameDate d) =>
    (d.month == 12 && d.day >= 24 && d.day <= 26) ||
    (d.month == 1 && d.day == 1);

void _expectValidMatchdays(List<GameDate> dates, SeasonCalendar cal) {
  for (var i = 1; i < dates.length; i++) {
    expect(dates[i].isAfter(dates[i - 1]), isTrue, reason: 'ascending, unique');
  }
  for (final d in dates) {
    expect(d.weekday, anyOf(Weekday.sat, Weekday.wed), reason: d.iso);
    expect(_inBreak(d, cal), isFalse, reason: '${d.iso} inside a break');
    expect(_isBlank(d), isFalse, reason: '${d.iso} is a Christmas blank');
    expect(d.isBefore(cal.seasonEnd), isTrue, reason: '${d.iso} after end');
  }
}

void main() {
  for (final year in [2026, 2027, 2028, 2029, 2030]) {
    group('shape for $year', () {
      final cal = buildSeasonCalendar(year);

      test('seasonStart is the second Saturday of August', () {
        expect(cal.seasonYear, year);
        expect(cal.seasonStart.weekday, Weekday.sat);
        expect(cal.seasonStart.year, year);
        expect(cal.seasonStart.month, 8);
        expect(cal.seasonStart.day, inInclusiveRange(8, 14));
      });

      test('four 9-day breaks starting on a Monday', () {
        expect(cal.internationalBreaks, hasLength(4));
        for (final b in cal.internationalBreaks) {
          expect(b.start.weekday, Weekday.mon);
          expect(b.start.daysUntil(b.end), 8);
        }
        expect(cal.internationalBreaks.map((b) => b.start.month), [
          9,
          10,
          11,
          3,
        ]);
        expect(cal.internationalBreaks.last.start.year, year + 1);
      });

      test('windows are ordered', () {
        expect(cal.summer.open.isBefore(cal.summer.close), isTrue);
        expect(cal.summer.close.isBefore(cal.winter.open), isTrue);
        expect(cal.winter.open.isBefore(cal.winter.close), isTrue);
        expect(cal.summer.open, GameDate.ymd(year, 6, 1));
        expect(cal.summer.close, cal.seasonStart.addDays(21));
        expect(cal.winter.open, GameDate.ymd(year + 1, 1, 1));
        expect(cal.winter.close, GameDate.ymd(year + 1, 1, 31));
      });
    });
  }

  group('2026', () {
    final cal = buildSeasonCalendar(2026);

    test('breaks fall on the 2nd full week', () {
      expect(cal.seasonStart, GameDate.ymd(2026, 8, 8));
      expect(cal.internationalBreaks[0].start, GameDate.ymd(2026, 9, 14));
      expect(cal.internationalBreaks[1].start, GameDate.ymd(2026, 10, 12));
      expect(cal.internationalBreaks[2].start, GameDate.ymd(2026, 11, 9));
      // March 2027 starts on a Monday: that Monday is week 1.
      expect(cal.internationalBreaks[3].start, GameDate.ymd(2027, 3, 8));
    });

    test('38 rounds fit on Saturdays and end before May 31', () {
      final dates = leagueMatchdays(cal, 38);
      expect(dates, hasLength(38));
      expect(dates.first, cal.seasonStart);
      expect(dates.every((d) => d.weekday == Weekday.sat), isTrue);
      expect(dates.last.isBefore(GameDate.ymd(2027, 5, 31)), isTrue);
      expect(dates, isNot(contains(GameDate.ymd(2026, 12, 26))));
      _expectValidMatchdays(dates, cal);
    });

    test('46 rounds insert at least 8 Wednesdays', () {
      final dates = leagueMatchdays(cal, 46);
      expect(dates, hasLength(46));
      final wednesdays = dates.where((d) => d.weekday == Weekday.wed);
      expect(wednesdays.length, greaterThanOrEqualTo(8));
      // Earliest Wednesdays first; Sep 16 is skipped because it is in a break.
      expect(wednesdays.first, GameDate.ymd(2026, 8, 12));
      expect(dates, isNot(contains(GameDate.ymd(2026, 9, 16))));
      _expectValidMatchdays(dates, cal);
    });

    test('seasonEnd is the last eligible Saturday plus 7', () {
      expect(cal.seasonEnd, GameDate.ymd(2027, 5, 29).addDays(7));
      expect(cal.seasonEnd.isAfter(leagueMatchdays(cal, 38).last), isTrue);
      expect(cal.seasonEnd.isAfter(leagueMatchdays(cal, 46).last), isTrue);
    });

    test('too many rounds throws', () {
      expect(() => leagueMatchdays(cal, 200), throwsArgumentError);
    });
  });

  group('2027 (leap year 2028)', () {
    final cal = buildSeasonCalendar(2027);

    test('46 rounds yield valid dates around Feb 29', () {
      final dates = leagueMatchdays(cal, 46);
      expect(dates, hasLength(46));
      _expectValidMatchdays(dates, cal);
      expect(GameDate.ymd(2028, 2, 29).weekday, Weekday.tue);
      expect(dates, contains(GameDate.ymd(2028, 2, 26)));
      expect(dates, contains(GameDate.ymd(2028, 3, 4)));
    });

    test('seasonEnd is after every matchday', () {
      expect(cal.seasonEnd.isAfter(leagueMatchdays(cal, 38).last), isTrue);
      expect(cal.seasonEnd.isAfter(leagueMatchdays(cal, 46).last), isTrue);
    });
  });
}
