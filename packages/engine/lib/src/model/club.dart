import '../core/ids.dart';
import 'enums.dart';
import 'tactic.dart';

/// Shirt colours as ARGB ints.
class Kit {
  int primary;
  int secondary;

  Kit({required this.primary, required this.secondary});
}

class LogoSpec {
  /// 0..7.
  int shape;

  /// ARGB ints.
  int color1;
  int color2;

  LogoSpec({required this.shape, required this.color1, required this.color2});
}

/// Facility levels 1..10.
class Facilities {
  int training;
  int medical;
  int youth;

  Facilities({
    required this.training,
    required this.medical,
    required this.youth,
  });
}

class Lineup {
  Formation formation;

  /// 11 players, ordered as [formationSlots] of [formation].
  List<PlayerId> starters;
  List<PlayerId> bench;

  Lineup({
    required this.formation,
    required this.starters,
    required this.bench,
  });
}

class Club {
  ClubId id;
  String name;
  String shortName;
  CountryId countryId;
  LeagueId leagueId;
  int reputation;
  Kit home;
  Kit away;
  LogoSpec logo;
  String stadiumName;
  int stadiumCapacity;
  int balance;
  int transferBudget;
  int wageBudget;
  Facilities facilities;

  /// Null means no manager.
  ManagerId? managerId;
  BoardExpectation expectation;
  double boardConfidence;
  Lineup? lineup;

  /// Exactly three tactic slots; [activeTactic] indexes the one in use.
  List<Tactic> tactics;
  int activeTactic;

  Club({
    required this.id,
    required this.name,
    required this.shortName,
    required this.countryId,
    required this.leagueId,
    required this.reputation,
    required this.home,
    required this.away,
    required this.logo,
    required this.stadiumName,
    required this.stadiumCapacity,
    required this.balance,
    required this.transferBudget,
    required this.wageBudget,
    required this.facilities,
    required this.expectation,
    this.managerId,
    this.boardConfidence = 50,
    this.lineup,
    List<Tactic>? tactics,
    this.activeTactic = 0,
  }) : tactics = tactics ?? defaultTactics(Formation.f442) {
    if (this.tactics.length != 3) {
      throw ArgumentError.value(this.tactics, 'tactics', 'must be exactly 3');
    }
    if (activeTactic < 0 || activeTactic > 2) {
      throw ArgumentError.value(activeTactic, 'activeTactic', 'must be 0..2');
    }
  }

  Tactic get tactic => tactics[activeTactic];

  /// The active tactic's formation.
  Formation get formation => tactic.formation;

  /// Replaces the active tactic with the [f] preset, keeping its name.
  set formation(Formation f) {
    tactics[activeTactic] = Tactic.preset(f, name: tactic.name);
  }
}
