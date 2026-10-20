import '../core/game_date.dart';
import '../core/ids.dart';

class GoalEvent {
  int minute;
  PlayerId scorerId;
  ClubId clubId;

  GoalEvent({
    required this.minute,
    required this.scorerId,
    required this.clubId,
  });
}

class MatchResult {
  int homeGoals;
  int awayGoals;
  List<GoalEvent> goals;
  int matchSeed;

  MatchResult({
    required this.homeGoals,
    required this.awayGoals,
    required this.goals,
    required this.matchSeed,
  });
}

class Fixture {
  FixtureId id;
  LeagueId leagueId;
  int seasonYear;
  int round;
  GameDate date;
  ClubId homeId;
  ClubId awayId;

  /// Null until played.
  MatchResult? result;

  Fixture({
    required this.id,
    required this.leagueId,
    required this.seasonYear,
    required this.round,
    required this.date,
    required this.homeId,
    required this.awayId,
    this.result,
  });
}
