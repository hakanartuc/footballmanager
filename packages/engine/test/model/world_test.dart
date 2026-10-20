import 'package:engine/engine.dart';
import 'package:test/test.dart';

final _d1 = GameDate.ymd(2026, 8, 8);
final _d2 = GameDate.ymd(2026, 8, 15);

Player _player(PlayerId id, {ClubId? clubId, bool isYouth = false}) => Player(
  id: id,
  firstName: 'P',
  lastName: '$id',
  nationality: 1,
  birth: GameDate.ymd(2000, 1, 1),
  heightCm: 180,
  mainPosition: Position.mc,
  familiarity: {Position.mc: 20},
  attrs: Attributes.filled(10),
  ca: 100,
  pa: 120,
  hidden: HiddenAttrs(
    injuryProneness: 10,
    consistency: 10,
    bigMatches: 10,
    professionalism: 10,
  ),
  contract: clubId == null
      ? null
      : Contract(
          clubId: clubId,
          wageWeekly: 1000,
          start: GameDate.ymd(2026, 7, 1),
          end: GameDate.ymd(2028, 6, 30),
          status: PlayerStatus.firstTeam,
        ),
  isYouth: isYouth,
);

Club _club(ClubId id, {ManagerId? managerId}) => Club(
  id: id,
  name: 'Club $id',
  shortName: 'C$id',
  countryId: 1,
  leagueId: 1,
  reputation: 50,
  home: Kit(primary: 0xFFFF0000, secondary: 0xFFFFFFFF),
  away: Kit(primary: 0xFFFFFFFF, secondary: 0xFFFF0000),
  logo: LogoSpec(shape: 0, color1: 0xFFFF0000, color2: 0xFFFFFFFF),
  stadiumName: 'Stadium $id',
  stadiumCapacity: 20000,
  balance: 1000000,
  transferBudget: 500000,
  wageBudget: 50000,
  facilities: Facilities(training: 5, medical: 5, youth: 5),
  managerId: managerId,
  expectation: BoardExpectation.mid,
);

Fixture _fixture(FixtureId id, GameDate date, ClubId home, ClubId away) =>
    Fixture(
      id: id,
      leagueId: 1,
      seasonYear: 2026,
      round: id,
      date: date,
      homeId: home,
      awayId: away,
    );

World _world({ClubId? userClubId}) {
  final calendar = SeasonCalendar(
    seasonYear: 2026,
    seasonStart: GameDate.ymd(2026, 8, 1),
    seasonEnd: GameDate.ymd(2027, 5, 31),
    internationalBreaks: [
      BreakPeriod(
        start: GameDate.ymd(2026, 9, 1),
        end: GameDate.ymd(2026, 9, 9),
      ),
    ],
    summer: TransferWindow(
      open: GameDate.ymd(2026, 6, 15),
      close: GameDate.ymd(2026, 8, 31),
    ),
    winter: TransferWindow(
      open: GameDate.ymd(2027, 1, 1),
      close: GameDate.ymd(2027, 1, 31),
    ),
  );
  return World(
    schemaVersion: 1,
    seed: 42,
    date: GameDate.ymd(2026, 7, 1),
    seasonYear: 2026,
    countries: {
      1: Country(
        id: 1,
        code: 'TUR',
        name: 'Turkey',
        continent: Continent.europe,
        namePool: 'tr',
        tiers: [1],
      ),
    },
    leagues: {
      1: League(
        id: 1,
        countryId: 1,
        tier: 1,
        name: 'Super League',
        clubIds: [1, 2],
        promotedCount: 0,
        relegatedCount: 1,
        reputation: 60,
      ),
    },
    clubs: {
      1: _club(1, managerId: userClubId == 1 ? 1 : null),
      2: _club(2),
    },
    players: {
      // Inserted out of id order to prove sorting.
      5: _player(5, clubId: 1),
      2: _player(2, clubId: 1),
      3: _player(3, clubId: 1, isYouth: true),
      4: _player(4, clubId: 2),
      6: _player(6), // free agent
      1: _player(1, clubId: 1),
    },
    managers: {
      1: Manager(
        id: 1,
        firstName: 'User',
        lastName: 'Manager',
        nationality: 1,
        birth: GameDate.ymd(1980, 1, 1),
        reputation: 30,
        preferredFormation: Formation.f442,
        clubId: userClubId,
        isUser: true,
      ),
    },
    fixtures: {
      // Later date has the lower id to prove date-then-id ordering.
      1: _fixture(1, _d2, 2, 1),
      2: _fixture(2, _d1, 1, 2),
    },
    calendar: calendar,
    userManagerId: 1,
    ids: IdAllocator(),
  );
}

void main() {
  test(
    'rebuildIndexes: squad sorted by id, excludes youth and free agents',
    () {
      final w = _world()..rebuildIndexes();
      expect(w.squadOf(1), [1, 2, 5]);
      expect(w.squadOf(2), [4]);
      expect(w.squadOf(99), isEmpty);

      // A structural change is visible only after rebuildIndexes.
      w.players[6]!.contract = Contract(
        clubId: 2,
        wageWeekly: 500,
        start: GameDate.ymd(2026, 7, 1),
        end: GameDate.ymd(2027, 6, 30),
        status: PlayerStatus.backup,
      );
      w.rebuildIndexes();
      expect(w.squadOf(2), [4, 6]);
    },
  );

  test('youthOf returns the youth player', () {
    final w = _world()..rebuildIndexes();
    expect(w.youthOf(1), [3]);
    expect(w.youthOf(2), isEmpty);
  });

  test('fixturesOn groups by date', () {
    final w = _world()..rebuildIndexes();
    expect(w.fixturesOn(_d1), [2]);
    expect(w.fixturesOn(_d2), [1]);
    expect(w.fixturesOn(_d1.addDays(1)), isEmpty);
  });

  test('fixturesOfClub returns fixtures in date order', () {
    final w = _world()..rebuildIndexes();
    expect(w.fixturesOfClub(1, 2026), [2, 1]);
    expect(w.fixturesOfClub(2, 2026), [2, 1]);
    expect(w.fixturesOfClub(1, 2027), isEmpty);
  });

  test('userClub is null when the user manager is unemployed', () {
    expect(_world().userClub, isNull);
    expect(_world(userClubId: 1).userClub?.id, 1);
  });

  test('query results cannot mutate the indexes', () {
    final w = _world()..rebuildIndexes();
    expect(() => w.squadOf(1).add(9), throwsUnsupportedError);
  });

  test('defaults', () {
    final w = _world();
    final c = w.clubs[1]!;
    expect(c.boardConfidence, 50);
    expect(c.lineup, isNull);
    expect(c.formation, Formation.f442);
    expect(c.managerId, isNull);
    expect(w.inbox, isEmpty);
    expect(w.history, isEmpty);
    expect(w.fixtures[1]!.result, isNull);
    final msg = InboxMessage(
      date: _d1,
      event: MatchPlayed(date: _d1, fixtureId: 2),
    );
    expect(msg.read, isFalse);
  });
}
