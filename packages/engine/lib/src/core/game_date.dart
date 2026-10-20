/// Day of the week; `mon` has index 0.
enum Weekday { mon, tue, wed, thu, fri, sat, sun }

final DateTime _epoch = DateTime.utc(2000, 1, 1);

/// A calendar date stored as days since 2000-01-01 (a Saturday).
///
/// The engine's only date type. Serializes as the plain [dayIndex] int.
/// Conversion goes through [DateTime.utc] only, so there are no time zones.
extension type const GameDate(int dayIndex) {
  /// The date [y]-[m]-[d]; throws [ArgumentError] if it does not exist.
  factory GameDate.ymd(int y, int m, int d) {
    final date = DateTime.utc(y, m, d);
    if (date.year != y || date.month != m || date.day != d) {
      throw ArgumentError('No such date: $y-$m-$d');
    }
    return GameDate(date.difference(_epoch).inDays);
  }

  DateTime get _utc => _epoch.add(Duration(days: dayIndex));

  int get year => _utc.year;
  int get month => _utc.month;
  int get day => _utc.day;

  Weekday get weekday => Weekday.values[(dayIndex + 5) % 7];

  GameDate addDays(int n) => GameDate(dayIndex + n);
  int daysUntil(GameDate other) => other.dayIndex - dayIndex;

  bool isBefore(GameDate o) => dayIndex < o.dayIndex;
  bool isAfter(GameDate o) => dayIndex > o.dayIndex;

  /// The first date strictly after this one that falls on [w].
  GameDate nextWeekday(Weekday w) {
    final ahead = (w.index - weekday.index + 6) % 7 + 1;
    return addDays(ahead);
  }

  /// The season this date belongs to, labelled by its starting year.
  int get seasonYear => month >= 7 ? year : year - 1;

  /// ISO `yyyy-mm-dd`.
  String get iso {
    final u = _utc;
    final mm = u.month.toString().padLeft(2, '0');
    final dd = u.day.toString().padLeft(2, '0');
    return '${u.year.toString().padLeft(4, '0')}-$mm-$dd';
  }
}

/// Full years completed between [birth] and [on].
int ageAt(GameDate birth, GameDate on) {
  final years = on.year - birth.year;
  final beforeBirthday =
      on.month < birth.month || (on.month == birth.month && on.day < birth.day);
  return beforeBirthday ? years - 1 : years;
}
