import '../core/game_date.dart';
import '../model/calendar.dart';

/// Builds the calendar every league in a country shares for [seasonYear]
/// (Spec §7.5, §16.7).
///
/// - `seasonStart`: the second Saturday of August (Aug 8–14).
/// - International breaks: 9 days from the Monday of the 2nd full week of
///   September, October, November and of March of the following year.
/// - `seasonEnd`: the last eligible Saturday on or before May 31 of the
///   following year, plus 7 days. It does not depend on any league's round
///   count: shorter leagues simply finish earlier and idle until `seasonEnd`.
/// - Summer window: June 1 of [seasonYear] to `seasonStart + 21`;
///   winter window: January 1–31 of the following year.
SeasonCalendar buildSeasonCalendar(int seasonYear) {
  final seasonStart = GameDate.ymd(seasonYear, 8, 7).nextWeekday(Weekday.sat);
  final breaks = [
    for (final (y, m) in [
      (seasonYear, 9),
      (seasonYear, 10),
      (seasonYear, 11),
      (seasonYear + 1, 3),
    ])
      _breakIn(y, m),
  ];
  final saturdays = _eligibleSaturdays(seasonYear, seasonStart, breaks);
  return SeasonCalendar(
    seasonYear: seasonYear,
    seasonStart: seasonStart,
    seasonEnd: saturdays.last.addDays(7),
    internationalBreaks: breaks,
    summer: TransferWindow(
      open: GameDate.ymd(seasonYear, 6, 1),
      close: seasonStart.addDays(21),
    ),
    winter: TransferWindow(
      open: GameDate.ymd(seasonYear + 1, 1, 1),
      close: GameDate.ymd(seasonYear + 1, 1, 31),
    ),
  );
}

/// Matchday dates for a league of [rounds] rounds on [cal].
///
/// Uses the eligible Saturdays from `seasonStart` to May 31 (outside breaks,
/// skipping Dec 24–26 and Jan 1). When [rounds] exceeds them, the Wednesday
/// after each used Saturday is added, earliest first, under the same
/// exclusions. Throws [ArgumentError] if there still are not enough dates.
List<GameDate> leagueMatchdays(SeasonCalendar cal, int rounds) {
  final saturdays = _eligibleSaturdays(
    cal.seasonYear,
    cal.seasonStart,
    cal.internationalBreaks,
  );
  if (rounds <= saturdays.length) return saturdays.sublist(0, rounds);

  final dates = List.of(saturdays);
  var missing = rounds - saturdays.length;
  for (final sat in saturdays) {
    if (missing == 0) break;
    final wed = sat.addDays(4);
    if (_excluded(wed, cal.internationalBreaks)) continue;
    dates.add(wed);
    missing--;
  }
  if (missing > 0) {
    throw ArgumentError.value(rounds, 'rounds', 'exceeds the available dates');
  }
  dates.sort((a, b) => a.dayIndex.compareTo(b.dayIndex));
  return dates;
}

/// The 9-day break starting on the Monday of the 2nd full week of [y]-[m].
BreakPeriod _breakIn(int y, int m) {
  final monthStart = GameDate.ymd(y, m, 1);
  final firstMonday = monthStart.addDays(-1).nextWeekday(Weekday.mon);
  final start = firstMonday.addDays(7);
  return BreakPeriod(start: start, end: start.addDays(8));
}

List<GameDate> _eligibleSaturdays(
  int seasonYear,
  GameDate seasonStart,
  List<BreakPeriod> breaks,
) {
  final limit = GameDate.ymd(seasonYear + 1, 5, 31);
  return [
    for (var d = seasonStart; !d.isAfter(limit); d = d.addDays(7))
      if (!_excluded(d, breaks)) d,
  ];
}

/// True inside a break or on the Christmas/New Year blanks.
bool _excluded(GameDate d, List<BreakPeriod> breaks) =>
    (d.month == 12 && d.day >= 24 && d.day <= 26) ||
    (d.month == 1 && d.day == 1) ||
    breaks.any((b) => !d.isBefore(b.start) && !d.isAfter(b.end));
