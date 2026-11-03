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

  /// Fine weather, a good pitch, nobody counted in the crowd and the
  /// midpoint of the [homeAdvantage] range; what a match plays under when
  /// its context carries no conditions.
  static const neutral = MatchConditions(
    weather: Weather.sunny,
    pitch: 8,
    attendance: 0,
    homeAdvantage: 1.055,
  );
}
