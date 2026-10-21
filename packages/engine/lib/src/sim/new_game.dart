import '../competition/season_calendar_builder.dart';
import '../core/game_date.dart';
import '../core/ids.dart';
import '../gen/world_generator.dart';
import '../model/enums.dart';
import '../model/events.dart';
import '../model/manager.dart';
import '../model/world.dart';

class NewGameSpec {
  int seed;
  WorldSize size;
  String managerFirstName;
  String managerLastName;

  /// Code of a country in the world, e.g. `'TR'`.
  String managerCountryCode;

  /// Null starts the user unemployed.
  ClubId? startClubId;

  NewGameSpec({
    required this.seed,
    required this.size,
    required this.managerFirstName,
    required this.managerLastName,
    required this.managerCountryCode,
    required this.startClubId,
  });
}

/// A new game: the generated world of [spec] dated 14 days before the
/// [startSeasonYear] season, the user manager (reputation 40, aged 40) and
/// a `NewSeasonStarted` inbox message.
///
/// With a `startClubId`, that club's AI manager is removed from the club
/// without any event (Faz 0 has no sacking) and stays in `managers`
/// unemployed. Throws [ArgumentError] when the country code or the club is
/// not in the world.
World createNewGame(NewGameSpec spec, {int startSeasonYear = 2026}) {
  final startDate = buildSeasonCalendar(
    startSeasonYear,
  ).seasonStart.addDays(-14);
  final world = generateWorld(
    seed: spec.seed,
    size: spec.size,
    startDate: startDate,
  );

  final country = world.countries.values
      .where((c) => c.code == spec.managerCountryCode)
      .firstOrNull;
  if (country == null) {
    throw ArgumentError.value(
      spec.managerCountryCode,
      'managerCountryCode',
      'not in the world',
    );
  }
  final club = spec.startClubId == null ? null : world.clubs[spec.startClubId];
  if (spec.startClubId != null && club == null) {
    throw ArgumentError.value(spec.startClubId, 'startClubId', 'no such club');
  }

  final user = Manager(
    id: world.ids.next('manager'),
    firstName: spec.managerFirstName,
    lastName: spec.managerLastName,
    nationality: country.id,
    birth: GameDate.ymd(startDate.year - 40, startDate.month, startDate.day),
    reputation: 40,
    clubId: spec.startClubId,
    isUser: true,
    preferredFormation: Formation.f442,
  );
  world.managers[user.id] = user;
  world.userManagerId = user.id;
  if (club != null) {
    world.managers[club.managerId]!.clubId = null;
    club.managerId = user.id;
  }

  world.inbox.add(
    InboxMessage(
      id: world.ids.next('inbox'),
      date: startDate,
      event: NewSeasonStarted(date: startDate, seasonYear: startSeasonYear),
    ),
  );
  world.rebuildIndexes();
  return world;
}
