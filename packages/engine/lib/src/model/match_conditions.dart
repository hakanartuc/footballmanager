enum Weather { sunny, cloudy, rainy, heavyRain, snow, windy, hot }

/// Match-day weather, pitch, crowd and the resulting home advantage.
class MatchConditions {
  final Weather weather;

  /// 1..10.
  final int pitch;
  final int attendance;

  /// 1.03..1.08.
  final double homeAdvantage;

  const MatchConditions({
    required this.weather,
    required this.pitch,
    required this.attendance,
    required this.homeAdvantage,
  });
}
