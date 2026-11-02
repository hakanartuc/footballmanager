import '../core/ids.dart';
import 'match_conditions.dart';
import 'player.dart';
import 'tactic.dart';

enum ChanceType {
  throughBall,
  cross,
  longShot,
  dribble,
  corner,
  freeKick,
  penalty,
}

enum ShotOutcome { goal, saved, blocked, post, off }

enum CardKind { yellow, secondYellow, red }

enum FoulKind { normal, lastMan, violent }

enum SubReason { injury, tactical, fatigue }

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

/// One side's match statistics.
class TeamStats {
  int shots;
  int onTarget;
  int blocked;
  int corners;
  int fouls;
  int yellows;
  int reds;
  int offsides;

  /// 0..100; the two sides sum to 100.
  int possessionPct;
  double xg;

  TeamStats({
    required this.shots,
    required this.onTarget,
    required this.blocked,
    required this.corners,
    required this.fouls,
    required this.yellows,
    required this.reds,
    required this.offsides,
    required this.possessionPct,
    required this.xg,
  });
}

/// A persisted match event. [half] is 1 or 2, 3 or 4 for the extra-time
/// halves, 5 for the shootout.
sealed class MatchEvent {
  int minute;
  int half;
  ClubId clubId;

  MatchEvent({required this.minute, required this.half, required this.clubId});
}

/// A goal; [clubId] is the club the goal counts for, also for an own goal
/// (whose [scorerId] then plays for the other club).
final class Goal extends MatchEvent {
  PlayerId scorerId;
  PlayerId? assistId;
  ChanceType type;
  bool isPenalty;
  bool isOwnGoal;

  Goal({
    required super.minute,
    required super.half,
    required super.clubId,
    required this.scorerId,
    required this.assistId,
    required this.type,
    required this.isPenalty,
    this.isOwnGoal = false,
  });
}

final class Booking extends MatchEvent {
  PlayerId playerId;
  CardKind kind;
  FoulKind reason;

  Booking({
    required super.minute,
    required super.half,
    required super.clubId,
    required this.playerId,
    required this.kind,
    required this.reason,
  });
}

final class Injury extends MatchEvent {
  PlayerId playerId;
  InjuryStub injury;

  Injury({
    required super.minute,
    required super.half,
    required super.clubId,
    required this.playerId,
    required this.injury,
  });

  int get severityDays => injury.daysLeft;
}

final class Substitution extends MatchEvent {
  PlayerId outId;
  PlayerId inId;
  SubReason reason;

  Substitution({
    required super.minute,
    required super.half,
    required super.clubId,
    required this.outId,
    required this.inId,
    required this.reason,
  });
}

final class PenaltyMissed extends MatchEvent {
  PlayerId playerId;
  ShotOutcome outcome;

  PenaltyMissed({
    required super.minute,
    required super.half,
    required super.clubId,
    required this.playerId,
    required this.outcome,
  });
}

final class TacticChange extends MatchEvent {
  Mentality mentality;

  TacticChange({
    required super.minute,
    required super.half,
    required super.clubId,
    required this.mentality,
  });
}

final class HalfTime extends MatchEvent {
  HalfTime({required super.minute, required super.half, required super.clubId});
}

final class FullTime extends MatchEvent {
  FullTime({required super.minute, required super.half, required super.clubId});
}

final class ExtraTimeStart extends MatchEvent {
  ExtraTimeStart({
    required super.minute,
    required super.half,
    required super.clubId,
  });
}

final class ShootoutStart extends MatchEvent {
  ShootoutStart({
    required super.minute,
    required super.half,
    required super.clubId,
  });
}

final class ShootoutKick extends MatchEvent {
  PlayerId playerId;
  bool scored;

  ShootoutKick({
    required super.minute,
    required super.half,
    required super.clubId,
    required this.playerId,
    required this.scored,
  });
}

class MatchResult {
  int homeGoals;
  int awayGoals;
  List<GoalEvent> goals;
  int matchSeed;

  /// Null for results played before match statistics existed.
  TeamStats? homeStats;
  TeamStats? awayStats;
  List<MatchEvent> events;

  /// Match rating per player who took part.
  Map<PlayerId, double> ratings;
  PlayerId? manOfTheMatch;
  MatchConditions? conditions;

  /// Shootout score; null when there was no shootout.
  int? homeShootout;
  int? awayShootout;
  bool abandoned;

  /// Condition at the final whistle of every player in either match squad
  /// (starters and bench); the day loop writes it back to the players.
  Map<PlayerId, double> finalCondition;

  MatchResult({
    required this.homeGoals,
    required this.awayGoals,
    required this.goals,
    required this.matchSeed,
    this.homeStats,
    this.awayStats,
    List<MatchEvent>? events,
    Map<PlayerId, double>? ratings,
    this.manOfTheMatch,
    this.conditions,
    this.homeShootout,
    this.awayShootout,
    this.abandoned = false,
    Map<PlayerId, double>? finalCondition,
  }) : events = events ?? [],
       ratings = ratings ?? {},
       finalCondition = finalCondition ?? {};
}
