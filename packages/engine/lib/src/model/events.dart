import '../core/game_date.dart';
import '../core/ids.dart';

sealed class GameEvent {
  GameDate date;

  GameEvent({required this.date});
}

final class MatchPlayed extends GameEvent {
  FixtureId fixtureId;

  MatchPlayed({required super.date, required this.fixtureId});
}

final class SeasonEnded extends GameEvent {
  int seasonYear;

  SeasonEnded({required super.date, required this.seasonYear});
}

final class LeagueChampion extends GameEvent {
  LeagueId leagueId;
  ClubId clubId;

  LeagueChampion({
    required super.date,
    required this.leagueId,
    required this.clubId,
  });
}

final class Promoted extends GameEvent {
  ClubId clubId;
  LeagueId fromLeagueId;
  LeagueId toLeagueId;

  Promoted({
    required super.date,
    required this.clubId,
    required this.fromLeagueId,
    required this.toLeagueId,
  });
}

final class Relegated extends GameEvent {
  ClubId clubId;
  LeagueId fromLeagueId;
  LeagueId toLeagueId;

  Relegated({
    required super.date,
    required this.clubId,
    required this.fromLeagueId,
    required this.toLeagueId,
  });
}

final class PlayerRetired extends GameEvent {
  PlayerId playerId;

  /// Null when the player retired as a free agent.
  ClubId? clubId;

  PlayerRetired({
    required super.date,
    required this.playerId,
    required this.clubId,
  });
}

final class YouthIntake extends GameEvent {
  ClubId clubId;
  List<PlayerId> playerIds;

  YouthIntake({
    required super.date,
    required this.clubId,
    required this.playerIds,
  });
}

/// Youth aged 19 or more who were not promoted at the rollover. The players
/// are removed from the world.
final class YouthReleased extends GameEvent {
  ClubId clubId;
  List<PlayerId> playerIds;

  YouthReleased({
    required super.date,
    required this.clubId,
    required this.playerIds,
  });
}

final class NewSeasonStarted extends GameEvent {
  int seasonYear;

  NewSeasonStarted({required super.date, required this.seasonYear});
}

class InboxMessage {
  /// Unique per world, issued by `ids.next('inbox')`; stable across saves,
  /// so hosts can refer to a message without holding the instance.
  final int id;
  GameDate date;
  GameEvent event;
  bool read;

  InboxMessage({
    required this.id,
    required this.date,
    required this.event,
    this.read = false,
  });
}
