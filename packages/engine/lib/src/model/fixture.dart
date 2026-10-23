import '../core/game_date.dart';
import '../core/ids.dart';
import 'match_result.dart';

export 'match_result.dart';

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
