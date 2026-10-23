/// Competition rules a match is played under.
class MatchRules {
  final int substitutions;
  final int benchSize;
  final bool extraTime;
  final bool penalties;

  /// Accumulated yellow cards that trigger a ban; the i-th threshold bans
  /// for `i + 1` matches.
  final List<int> yellowThresholds;

  /// Matches banned for a red card from two yellows, a professional foul and
  /// violent conduct.
  final int redBanSecondYellow;
  final int redBanFoul;
  final int redBanViolent;

  const MatchRules({
    required this.substitutions,
    required this.benchSize,
    required this.extraTime,
    required this.penalties,
    required this.yellowThresholds,
    required this.redBanSecondYellow,
    required this.redBanFoul,
    required this.redBanViolent,
  });

  /// Domestic league rules.
  static const league = MatchRules(
    substitutions: 5,
    benchSize: 7,
    extraTime: false,
    penalties: false,
    yellowThresholds: [5, 10, 15],
    redBanSecondYellow: 1,
    redBanFoul: 3,
    redBanViolent: 4,
  );
}
