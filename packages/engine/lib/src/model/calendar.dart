import '../core/game_date.dart';

class TransferWindow {
  GameDate open;
  GameDate close;

  TransferWindow({required this.open, required this.close});
}

class BreakPeriod {
  GameDate start;
  GameDate end;

  BreakPeriod({required this.start, required this.end});
}

class SeasonCalendar {
  int seasonYear;
  GameDate seasonStart;
  GameDate seasonEnd;
  List<BreakPeriod> internationalBreaks;
  TransferWindow summer;
  TransferWindow winter;

  SeasonCalendar({
    required this.seasonYear,
    required this.seasonStart,
    required this.seasonEnd,
    required this.internationalBreaks,
    required this.summer,
    required this.winter,
  });
}
