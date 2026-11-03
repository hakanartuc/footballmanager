import '../competition/season_calendar_builder.dart';
import '../core/game_date.dart';
import '../core/ids.dart';
import '../model/attributes.dart';
import '../model/club.dart';
import '../model/enums.dart';
import '../model/player.dart';
import '../model/tactic.dart';
import '../model/world.dart';

/// Synthetic players, clubs and worlds for the calibration harness and
/// the match tests: every factor of spec 5.2 is 1.0, so the match engine
/// sees exactly the attributes it is given.

/// Date every synthetic world starts on.
final syntheticDate = GameDate.ymd(2026, 8, 1);

/// Slot indexes of the 7-man bench: a keeper, two defenders, two
/// midfielders and two forwards in every preset (4-4-2: gk, dc, dr, mc,
/// mr, st, st).
const _benchSlotIndexes = [0, 2, 4, 6, 8, 9, 10];

/// Factors all 1.0: familiarity 20 in [slot], condition 100, sharpness
/// 100, morale 50, form 5.5; age 26 on [syntheticDate]; proneness 10
/// (×1.21 injury weight). `ca` is `computeCa` of the uniform [attr]
/// (attr 12 → CA 120).
Player syntheticPlayer(
  PlayerId id,
  Position slot, {
  int attr = 10,
  ClubId? clubId,
}) {
  final attrs = Attributes.filled(attr);
  return Player(
    id: id,
    firstName: 'P',
    lastName: '$id',
    nationality: 1,
    birth: GameDate.ymd(2000, 1, 1),
    heightCm: 180,
    mainPosition: slot,
    familiarity: {slot: 20},
    attrs: attrs,
    ca: computeCa(attrs, slot),
    pa: computeCa(attrs, slot),
    hidden: HiddenAttrs(
      injuryProneness: 10,
      consistency: 10,
      bigMatches: 10,
      professionalism: 10,
    ),
    state: PlayerState(condition: 100, sharpness: 100, morale: 50, form: 5.5),
    contract: clubId == null
        ? null
        : Contract(
            clubId: clubId,
            wageWeekly: 0,
            start: GameDate.ymd(2026, 7, 1),
            end: GameDate.ymd(2030, 6, 30),
            status: PlayerStatus.firstTeam,
          ),
  );
}

/// The first player id of club [id]: club 1 owns 1.., club 2 101.., and
/// so on.
int syntheticFirstPlayerId(ClubId id) => (id - 1) * 100 + 1;

/// Club [id] with 11 starters on [slots] (ids from
/// [syntheticFirstPlayerId]) and a 7-man bench after them, all with
/// uniform [attr], its lineup stored and three balanced preset tactics
/// (the first on [formation]; a custom [slots] list gets a custom
/// tactic). The players are added to [players].
///
/// [plusOne] of the 18 players (the first ones in id order, starters
/// first) get `attr + 1` instead, so a club's mean CA can sit between two
/// uniform levels (the season harness needs distinct club strengths).
Club syntheticClub({
  required ClubId id,
  required int attr,
  required Map<PlayerId, Player> players,
  Formation formation = Formation.f442,
  List<Position>? slots,
  int plusOne = 0,
}) {
  final positions = slots ?? formationSlots(formation);
  final first = syntheticFirstPlayerId(id);
  final starters = <PlayerId>[];
  final bench = <PlayerId>[];
  int attrOf(int k) => k < plusOne ? attr + 1 : attr;
  for (var i = 0; i < 11; i++) {
    final pid = first + i;
    players[pid] = syntheticPlayer(
      pid,
      positions[i],
      attr: attrOf(i),
      clubId: id,
    );
    starters.add(pid);
  }
  for (var k = 0; k < _benchSlotIndexes.length; k++) {
    final pid = first + 11 + k;
    players[pid] = syntheticPlayer(
      pid,
      positions[_benchSlotIndexes[k]],
      attr: attrOf(11 + k),
      clubId: id,
    );
    bench.add(pid);
  }
  final tactics = formation == Formation.custom
      ? [
          Tactic.custom(positions, name: '1'),
          Tactic.preset(Formation.f433, name: '2'),
          Tactic.preset(Formation.f532, name: '3'),
        ]
      : defaultTactics(formation);
  return Club(
    id: id,
    name: 'Club $id',
    shortName: 'C$id',
    countryId: 1,
    leagueId: 1,
    reputation: 50,
    home: Kit(primary: 0xFFFFFFFF, secondary: 0xFF000000),
    away: Kit(primary: 0xFF000000, secondary: 0xFFFFFFFF),
    logo: LogoSpec(shape: 0, color1: 0xFFFFFFFF, color2: 0xFF000000),
    stadiumName: 'Ground $id',
    stadiumCapacity: 20000,
    balance: 0,
    transferBudget: 0,
    wageBudget: 0,
    facilities: Facilities(training: 5, medical: 5, youth: 5),
    expectation: BoardExpectation.mid,
    lineup: Lineup(formation: formation, starters: starters, bench: bench),
    tactics: tactics,
  );
}

/// A world of [players] and [clubs] on [syntheticDate] with no
/// countries, leagues, managers or fixtures.
World syntheticWorld({
  required Map<PlayerId, Player> players,
  Map<ClubId, Club> clubs = const {},
  int seed = 1,
}) => World(
  schemaVersion: currentSchemaVersion,
  seed: seed,
  date: syntheticDate,
  seasonYear: 2026,
  countries: {},
  leagues: {},
  clubs: Map.of(clubs),
  players: players,
  managers: {},
  fixtures: {},
  calendar: buildSeasonCalendar(2026),
  userManagerId: 1,
  ids: IdAllocator(),
);

/// Home club 1 with uniform [homeAttr] against away club 2 with uniform
/// [awayAttr], both in [formation] with 11 starters, a 7-man bench and
/// balanced preset tactics; CA is attr × 10 (12 → 120).
World syntheticPair({
  int homeAttr = 12,
  int awayAttr = 12,
  Formation formation = Formation.f442,
  int seed = 1,
}) {
  final players = <PlayerId, Player>{};
  final clubs = {
    1: syntheticClub(
      id: 1,
      attr: homeAttr,
      players: players,
      formation: formation,
    ),
    2: syntheticClub(
      id: 2,
      attr: awayAttr,
      players: players,
      formation: formation,
    ),
  };
  return syntheticWorld(players: players, clubs: clubs, seed: seed);
}
