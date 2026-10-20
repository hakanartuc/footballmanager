import '../core/game_date.dart';
import '../core/ids.dart';
import 'enums.dart';
import 'player.dart';

class Manager {
  ManagerId id;
  String firstName;
  String lastName;
  CountryId nationality;
  GameDate birth;
  int reputation;

  /// Null means unemployed.
  ClubId? clubId;
  bool isUser;
  Formation preferredFormation;

  /// Stats are unused for managers in Faz 0.
  List<CareerLine> career;

  Manager({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.nationality,
    required this.birth,
    required this.reputation,
    required this.preferredFormation,
    this.clubId,
    this.isUser = false,
    List<CareerLine>? career,
  }) : career = career ?? [];
}
