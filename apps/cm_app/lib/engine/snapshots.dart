/// Read-only views of the engine's world for the UI.
///
/// Every class here is a plain `final` value type holding only primitives,
/// lists, maps, engine enums, [GameDate] and [GameEvent], so each can be
/// sent across an isolate boundary unchanged.
library;

import 'package:engine/engine.dart';

final class ClubRef {
  const ClubRef({
    required this.id,
    required this.name,
    required this.shortName,
    required this.kitPrimary,
    required this.kitSecondary,
    required this.leagueId,
    required this.countryId,
  });

  final ClubId id;
  final String name;
  final String shortName;

  /// Home kit colours as ARGB ints.
  final int kitPrimary;
  final int kitSecondary;
  final LeagueId leagueId;
  final CountryId countryId;
}

final class LeagueRef {
  const LeagueRef({
    required this.id,
    required this.name,
    required this.countryCode,
    required this.tier,
    required this.clubIds,
  });

  final LeagueId id;
  final String name;
  final String countryCode;
  final int tier;
  final List<ClubId> clubIds;
}

final class CountryRef {
  const CountryRef({
    required this.id,
    required this.code,
    required this.name,
    required this.leagueIds,
  });

  final CountryId id;
  final String code;
  final String name;

  /// League ids by tier; the first is the top division.
  final List<LeagueId> leagueIds;
}

/// The static shape of the world; built once per game.
final class WorldRefs {
  const WorldRefs({
    required this.countries,
    required this.leagues,
    required this.clubs,
  });

  final List<CountryRef> countries;
  final List<LeagueRef> leagues;
  final List<ClubRef> clubs;
}

final class NextMatch {
  const NextMatch({
    required this.fixtureId,
    required this.date,
    required this.homeId,
    required this.awayId,
    required this.homeName,
    required this.awayName,
    required this.isHome,
  });

  final FixtureId fixtureId;
  final GameDate date;
  final ClubId homeId;
  final ClubId awayId;
  final String homeName;
  final String awayName;
  final bool isHome;
}

final class HomeSnapshot {
  const HomeSnapshot({
    required this.date,
    required this.seasonYear,
    required this.clubId,
    required this.clubName,
    required this.leagueId,
    required this.leaguePosition,
    required this.nextMatch,
    required this.isMatchDay,
    required this.unreadCount,
    required this.seniorCount,
    required this.injuredCount,
    required this.suspendedCount,
    required this.managerName,
  });

  final GameDate date;
  final int seasonYear;

  /// Null (with the other club fields) while the user is unemployed.
  final ClubId? clubId;
  final String? clubName;
  final LeagueId? leagueId;
  final int? leaguePosition;
  final NextMatch? nextMatch;
  final bool isMatchDay;
  final int unreadCount;
  final int seniorCount;
  final int injuredCount;
  final int suspendedCount;
  final String managerName;
}

final class SquadRow {
  const SquadRow({
    required this.id,
    required this.name,
    required this.position,
    required this.age,
    required this.ca,
    required this.condition,
    required this.injured,
    required this.suspension,
    required this.status,
    required this.isYouth,
  });

  final PlayerId id;
  final String name;
  final Position position;
  final int age;
  final int ca;
  final double condition;
  final bool injured;

  /// Matches left of a suspension; 0 when not suspended.
  final int suspension;
  final PlayerStatus status;
  final bool isYouth;
}

final class PlayerDetail {
  const PlayerDetail({
    required this.id,
    required this.name,
    required this.countryCode,
    required this.position,
    required this.familiarity,
    required this.age,
    required this.heightCm,
    required this.attrs,
    required this.ca,
    required this.pa,
    required this.condition,
    required this.morale,
    required this.sharpness,
    required this.form,
    required this.wageWeekly,
    required this.contractEnd,
    required this.status,
    required this.apps,
    required this.goals,
    required this.assists,
  });

  final PlayerId id;
  final String name;
  final String countryCode;
  final Position position;
  final Map<Position, int> familiarity;
  final int age;
  final int heightCm;

  /// One value per [Attr], in [Attr.values] order.
  final List<int> attrs;
  final int ca;
  final int pa;
  final double condition;
  final double morale;
  final double sharpness;
  final double form;

  /// Contract fields; null for a free agent.
  final int? wageWeekly;
  final GameDate? contractEnd;
  final PlayerStatus? status;
  final int apps;
  final int goals;
  final int assists;
}

final class LineupView {
  const LineupView({
    required this.formation,
    required this.slots,
    required this.starters,
    required this.bench,
    required this.errors,
  });

  final Formation formation;

  /// The 11 positions of [formation]; `starters[i]` fills `slots[i]`.
  final List<Position> slots;
  final List<PlayerId> starters;
  final List<PlayerId> bench;

  /// Empty when the lineup is valid.
  final List<LineupError> errors;
}

final class TableRowView {
  const TableRowView({
    required this.rank,
    required this.clubId,
    required this.clubName,
    required this.played,
    required this.won,
    required this.drawn,
    required this.lost,
    required this.gf,
    required this.ga,
    required this.gd,
    required this.points,
    required this.isUser,
  });

  /// 1-based.
  final int rank;
  final ClubId clubId;
  final String clubName;
  final int played;
  final int won;
  final int drawn;
  final int lost;
  final int gf;
  final int ga;
  final int gd;
  final int points;
  final bool isUser;
}

final class GoalRow {
  const GoalRow({
    required this.minute,
    required this.scorerId,
    required this.scorerName,
    required this.clubId,
  });

  final int minute;
  final PlayerId scorerId;
  final String scorerName;
  final ClubId clubId;
}

final class FixtureRow {
  const FixtureRow({
    required this.id,
    required this.round,
    required this.date,
    required this.homeId,
    required this.awayId,
    required this.homeName,
    required this.awayName,
    required this.homeGoals,
    required this.awayGoals,
    required this.goals,
  });

  final FixtureId id;
  final int round;
  final GameDate date;
  final ClubId homeId;
  final ClubId awayId;
  final String homeName;
  final String awayName;

  /// Null until played.
  final int? homeGoals;
  final int? awayGoals;
  final List<GoalRow> goals;
}

final class InboxItem {
  const InboxItem({
    required this.id,
    required this.date,
    required this.read,
    required this.event,
    required this.labels,
  });

  final int id;
  final GameDate date;
  final bool read;
  final GameEvent event;
  final InboxLabels labels;
}

/// Display names resolved for an [InboxItem]'s event; only the fields the
/// event kind uses are set.
///
/// - [MatchPlayed]: [homeName], [awayName], [homeGoals], [awayGoals].
/// - [LeagueChampion]: [clubName], [leagueName].
/// - [Promoted] / [Relegated]: [clubName], [leagueName] (from),
///   [toLeagueName].
/// - [PlayerRetired]: [clubName] only. The player is removed from the
///   world when the event is raised, so the name cannot be resolved and
///   [playerNames] stays empty (Faz 4 archives names).
/// - [YouthIntake]: [clubName], [playerNames] of the players still in the
///   world.
/// - [YouthReleased]: [clubName] only; the players are gone.
/// - [SeasonEnded] / [NewSeasonStarted]: nothing.
final class InboxLabels {
  const InboxLabels({
    this.clubName,
    this.otherClubName,
    this.leagueName,
    this.toLeagueName,
    this.homeName,
    this.awayName,
    this.homeGoals,
    this.awayGoals,
    this.playerNames = const [],
  });

  final String? clubName;
  final String? otherClubName;
  final String? leagueName;
  final String? toLeagueName;
  final String? homeName;
  final String? awayName;
  final int? homeGoals;
  final int? awayGoals;
  final List<String> playerNames;
}

/// Why an advance call returned.
enum StopReason {
  /// Today is a user match day; play it with `playToday`.
  matchDay,

  /// The season's last day was processed.
  seasonEnded,

  /// `maxDays` passed without another stop.
  reachedLimit,

  /// `playToday` processed its single day.
  played,
}

final class AdvanceOutcome {
  const AdvanceOutcome({
    required this.daysAdvanced,
    required this.reason,
    required this.date,
    required this.userMatch,
    required this.seasonEnded,
    required this.newInboxCount,
  });

  final int daysAdvanced;
  final StopReason reason;

  /// The world's date after the call.
  final GameDate date;

  /// The user's fixture played by `playToday`; null for `advanceToNext`
  /// and when no user match was played.
  final FixtureRow? userMatch;

  /// Whether a season ended during the call.
  final bool seasonEnded;

  /// Inbox messages added during the call.
  final int newInboxCount;
}
