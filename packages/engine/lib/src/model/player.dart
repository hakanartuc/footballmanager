import '../core/game_date.dart' as dates;
import '../core/game_date.dart' show GameDate;
import '../core/ids.dart';
import 'attributes.dart';
import 'enums.dart';

/// Placeholder until injuries arrive in Faz 2.
class InjuryStub {
  int daysLeft;
  String type;

  InjuryStub({required this.daysLeft, required this.type});
}

/// Placeholder until loans arrive in Faz 3.
class LoanStub {
  ClubId parentClubId;
  GameDate end;

  LoanStub({required this.parentClubId, required this.end});
}

class PlayerState {
  double condition;
  double sharpness;
  double morale;
  double form;
  int yellowCards;
  int suspensionMatches;
  InjuryStub? injury;

  PlayerState({
    this.condition = 100,
    this.sharpness = 100,
    this.morale = 50,
    this.form = 6.0,
    this.yellowCards = 0,
    this.suspensionMatches = 0,
    this.injury,
  });
}

class Contract {
  ClubId clubId;
  int wageWeekly;
  GameDate start;
  GameDate end;
  PlayerStatus status;
  int? squadNumber;
  int? releaseFee;

  Contract({
    required this.clubId,
    required this.wageWeekly,
    required this.start,
    required this.end,
    required this.status,
    this.squadNumber,
    this.releaseFee,
  });
}

class SeasonStats {
  int apps;
  int goals;
  int assists;
  int yellows;
  int reds;
  double ratingSum;

  SeasonStats({
    this.apps = 0,
    this.goals = 0,
    this.assists = 0,
    this.yellows = 0,
    this.reds = 0,
    this.ratingSum = 0,
  });
}

class CareerLine {
  int seasonYear;
  ClubId clubId;
  SeasonStats stats;

  CareerLine({
    required this.seasonYear,
    required this.clubId,
    SeasonStats? stats,
  }) : stats = stats ?? SeasonStats();
}

class Player {
  PlayerId id;
  String firstName;
  String lastName;
  CountryId nationality;
  GameDate birth;
  int heightCm;
  Position mainPosition;

  /// Per-position familiarity 1..20; the main position is 20.
  Map<Position, int> familiarity;
  Attributes attrs;
  int ca;
  int pa;
  HiddenAttrs hidden;
  PlayerState state;

  /// Null means free agent.
  Contract? contract;

  /// In the youth squad (not counted toward the 18–28 senior squad).
  bool isYouth;
  SeasonStats season;
  List<CareerLine> career;
  int internationalCaps;
  int internationalGoals;
  LoanStub? loan;

  Player({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.nationality,
    required this.birth,
    required this.heightCm,
    required this.mainPosition,
    required this.familiarity,
    required this.attrs,
    required this.ca,
    required this.pa,
    required this.hidden,
    PlayerState? state,
    this.contract,
    this.isYouth = false,
    SeasonStats? season,
    List<CareerLine>? career,
    this.internationalCaps = 0,
    this.internationalGoals = 0,
    this.loan,
  }) : state = state ?? PlayerState(),
       season = season ?? SeasonStats(),
       career = career ?? [];

  /// Full years of age on [on].
  int ageAt(GameDate on) => dates.ageAt(birth, on);
}
