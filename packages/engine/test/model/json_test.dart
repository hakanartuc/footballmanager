import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:engine/engine.dart';
import 'package:test/test.dart';

const _deep = DeepCollectionEquality();

final _d = GameDate.ymd(2026, 8, 8);

Player _player(PlayerId id) {
  final clubId = (id - 1) ~/ 10 + 1; // 10 players per club, clubs 1..4
  final p = Player(
    id: id,
    firstName: 'First$id',
    lastName: 'Last$id',
    nationality: id.isEven ? 1 : 2,
    birth: GameDate.ymd(1990 + id % 15, 1 + id % 12, 1 + id % 28),
    heightCm: 170 + id % 25,
    mainPosition: Position.values[id % Position.values.length],
    // Inserted out of Position.values order to prove ordering.
    familiarity: {
      Position.st: 5 + id % 10,
      Position.values[id % Position.values.length]: 20,
      Position.dc: 3,
    },
    attrs: Attributes.fromList([
      for (var i = 0; i < Attr.values.length; i++) 1 + (id + i) % 20,
    ]),
    ca: 80 + id,
    pa: 120 + id,
    hidden: HiddenAttrs(
      injuryProneness: 1 + id % 20,
      consistency: 2 + id % 19,
      bigMatches: 3 + id % 18,
      professionalism: 4 + id % 17,
    ),
    state: PlayerState(
      condition: 90.5,
      sharpness: 80,
      morale: 55.25,
      form: 6.7,
      yellowCards: id % 3,
      suspensionMatches: id % 2,
    ),
    contract: Contract(
      clubId: clubId,
      wageWeekly: 1000 * id,
      start: GameDate.ymd(2025, 7, 1),
      end: GameDate.ymd(2028, 6, 30),
      status: PlayerStatus.values[id % PlayerStatus.values.length],
      squadNumber: id.isEven ? id : null,
      releaseFee: id % 5 == 0 ? 5000000 : null,
    ),
    season: SeasonStats(
      apps: 3,
      goals: id % 4,
      assists: 1,
      yellows: 1,
      reds: 0,
      ratingSum: 20.1,
    ),
    career: [
      CareerLine(
        seasonYear: 2024,
        clubId: clubId,
        stats: SeasonStats(apps: 30, goals: 5, ratingSum: 201.5),
      ),
      CareerLine(seasonYear: 2025, clubId: clubId),
    ],
    internationalCaps: id % 7,
    internationalGoals: id % 3,
  );
  return p;
}

Club _club(ClubId id, LeagueId leagueId, {ManagerId? managerId}) => Club(
  id: id,
  name: 'Club $id',
  shortName: 'C$id',
  countryId: leagueId,
  leagueId: leagueId,
  reputation: 40 + id,
  home: Kit(primary: 0xFFFF0000 + id, secondary: 0xFFFFFFFF),
  away: Kit(primary: 0xFFFFFFFF, secondary: 0xFF0000FF + id),
  logo: LogoSpec(shape: id % 8, color1: 0xFF00FF00, color2: 0xFF000000 + id),
  stadiumName: 'Stadium $id',
  stadiumCapacity: 20000 + id,
  balance: -100000 * id,
  transferBudget: 500000,
  wageBudget: 50000,
  facilities: Facilities(training: id, medical: 2 * id, youth: 10 - id),
  expectation: BoardExpectation.values[id % BoardExpectation.values.length],
  managerId: managerId,
  boardConfidence: 61.5,
  lineup: id == 1
      ? Lineup(
          formation: Formation.f433,
          starters: [for (var i = 1; i <= 11; i++) i],
          bench: [12, 13],
        )
      : null,
  tactics: [
    id == 1 ? _richTactic() : Tactic.preset(Formation.f4231, name: 'one'),
    Tactic.preset(Formation.values[id % 6], name: 'two'),
    Tactic.preset(Formation.f352, name: 'three'),
  ],
  activeTactic: id % 3,
);

/// A custom 3-4-3 with every optional field set; instructions and arrows
/// are inserted out of id order to prove key sorting.
Tactic _richTactic() => Tactic.custom(
  const [
    Position.gk,
    Position.dc,
    Position.dc,
    Position.dc,
    Position.ml,
    Position.mc,
    Position.mc,
    Position.mr,
    Position.aml,
    Position.amr,
    Position.st,
  ],
  name: 'Custom',
  mentality: Mentality.attacking,
  passing: PassingStyle.direct,
  tempo: Tempo.fast,
  width: Width.wide,
  pressing: Pressing.high,
  tackling: Tackling.hard,
  marking: Marking.man,
  offsideTrap: true,
  counterAttack: true,
  playmaker: 6,
  targetMan: 11,
  captain: 2,
  viceCaptain: 3,
  setPieces: SetPieceTakers(
    cornerLeft: 8,
    cornerRight: 9,
    freeKickLeft: 6,
    penalty: 11,
  ),
  instructions: {
    10: PlayerInstructions(forwardRuns: true, crossFrom: CrossTarget.far),
    2: PlayerInstructions(holdUpBall: true, freeRole: true),
    7: PlayerInstructions(
      runWithBall: true,
      longShots: true,
      throughBalls: true,
      crossFrom: CrossTarget.near,
    ),
  },
  arrows: {9: Arrow.forward, 1: Arrow.none, 4: Arrow.back},
);

Fixture _fixture(FixtureId id, LeagueId leagueId, ClubId home, ClubId away) =>
    Fixture(
      id: id,
      leagueId: leagueId,
      seasonYear: 2026,
      round: (id + 1) ~/ 2,
      date: _d.addDays(7 * ((id - 1) ~/ 2)),
      homeId: home,
      awayId: away,
    );

World _world() {
  // Players inserted in descending id order to prove key sorting.
  final players = {for (var id = 40; id >= 1; id--) id: _player(id)};
  players[1]!.isYouth = true;
  players[2]!.isYouth = true;
  players[3]!.contract = null; // free agent
  players[4]!.state.injury = InjuryStub(daysLeft: 12, type: 'hamstring');
  players[5]!.loan = LoanStub(parentClubId: 3, end: GameDate.ymd(2027, 5, 31));

  final fixtures = {
    6: _fixture(6, 2, 4, 3),
    1: _fixture(1, 1, 1, 2),
    2: _fixture(2, 2, 3, 4),
    3: _fixture(3, 1, 2, 1),
    4: _fixture(4, 2, 4, 3),
    5: _fixture(5, 1, 1, 2),
  };
  fixtures[1]!.result = MatchResult(
    homeGoals: 2,
    awayGoals: 1,
    goals: [
      GoalEvent(minute: 12, scorerId: 10, clubId: 1),
      GoalEvent(minute: 55, scorerId: 15, clubId: 2),
      GoalEvent(minute: 90, scorerId: 9, clubId: 1),
    ],
    matchSeed: 123456789,
  );
  fixtures[2]!.result = MatchResult(
    homeGoals: 0,
    awayGoals: 1,
    goals: [GoalEvent(minute: 77, scorerId: 33, clubId: 4)],
    matchSeed: 987,
  );

  final ids = IdAllocator();
  for (var i = 0; i < 40; i++) {
    ids.next('player');
  }
  for (var i = 0; i < 4; i++) {
    ids.next('club');
  }

  return World(
    schemaVersion: 1,
    seed: 42,
    date: GameDate.ymd(2026, 8, 20),
    seasonYear: 2026,
    countries: {
      2: Country(
        id: 2,
        code: 'ENG',
        name: 'England',
        continent: Continent.europe,
        namePool: 'en',
        tiers: [2],
      ),
      1: Country(
        id: 1,
        code: 'TUR',
        name: 'Turkey',
        continent: Continent.asia,
        namePool: 'tr',
        tiers: [1],
      ),
    },
    leagues: {
      2: League(
        id: 2,
        countryId: 2,
        tier: 1,
        name: 'Premier',
        clubIds: [3, 4],
        promotedCount: 0,
        relegatedCount: 1,
        reputation: 80,
      ),
      1: League(
        id: 1,
        countryId: 1,
        tier: 1,
        name: 'Super Lig',
        clubIds: [1, 2],
        promotedCount: 0,
        relegatedCount: 1,
        reputation: 60,
      ),
    },
    clubs: {
      4: _club(4, 2),
      1: _club(1, 1, managerId: 1),
      3: _club(3, 2),
      2: _club(2, 1),
    },
    players: players,
    managers: {
      2: Manager(
        id: 2,
        firstName: 'Free',
        lastName: 'Agent',
        nationality: 2,
        birth: GameDate.ymd(1970, 3, 4),
        reputation: 30,
        preferredFormation: Formation.f352,
      ),
      1: Manager(
        id: 1,
        firstName: 'User',
        lastName: 'Manager',
        nationality: 1,
        birth: GameDate.ymd(1980, 5, 6),
        reputation: 50,
        preferredFormation: Formation.f4231,
        clubId: 1,
        isUser: true,
        career: [CareerLine(seasonYear: 2025, clubId: 1)],
      ),
    },
    fixtures: fixtures,
    calendar: SeasonCalendar(
      seasonYear: 2026,
      seasonStart: GameDate.ymd(2026, 8, 1),
      seasonEnd: GameDate.ymd(2027, 5, 31),
      internationalBreaks: [
        BreakPeriod(
          start: GameDate.ymd(2026, 9, 1),
          end: GameDate.ymd(2026, 9, 9),
        ),
        BreakPeriod(
          start: GameDate.ymd(2026, 10, 6),
          end: GameDate.ymd(2026, 10, 14),
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
    ),
    userManagerId: 1,
    ids: ids,
    inbox: [
      InboxMessage(
        id: 1,
        date: _d,
        event: MatchPlayed(date: _d, fixtureId: 1),
        read: true,
      ),
      InboxMessage(
        id: 2,
        date: _d.addDays(1),
        event: PlayerRetired(date: _d.addDays(1), playerId: 3, clubId: null),
      ),
      InboxMessage(
        id: 3,
        date: _d.addDays(2),
        event: YouthIntake(date: _d.addDays(2), clubId: 1, playerIds: [1, 2]),
      ),
    ],
    history: [
      SeasonArchive(
        seasonYear: 2025,
        champions: {2: 3, 1: 1},
        finalOrder: {
          2: [3, 4],
          1: [1, 2],
        },
      ),
    ],
  );
}

List<GameEvent> _allEvents() => [
  MatchPlayed(date: _d, fixtureId: 7),
  SeasonEnded(date: _d, seasonYear: 2026),
  LeagueChampion(date: _d, leagueId: 1, clubId: 2),
  Promoted(date: _d, clubId: 3, fromLeagueId: 2, toLeagueId: 1),
  Relegated(date: _d, clubId: 4, fromLeagueId: 1, toLeagueId: 2),
  PlayerRetired(date: _d, playerId: 9, clubId: 1),
  YouthIntake(date: _d, clubId: 2, playerIds: [41, 42, 43]),
  YouthReleased(date: _d, clubId: 2, playerIds: [44]),
  NewSeasonStarted(date: _d, seasonYear: 2027),
  PlayerInjured(date: _d, playerId: 5, clubId: 1, days: 21),
  PlayerSentOff(date: _d, playerId: 6, clubId: 1, fixtureId: 7),
  PlayerSuspended(date: _d, playerId: 6, clubId: 1, matches: 2),
];

List<MatchEvent> _allMatchEvents() => [
  Goal(
    minute: 12,
    half: 1,
    clubId: 1,
    scorerId: 10,
    assistId: 9,
    type: ChanceType.throughBall,
    isPenalty: false,
  ),
  Goal(
    minute: 40,
    half: 1,
    clubId: 1,
    scorerId: 15,
    assistId: null,
    type: ChanceType.cross,
    isPenalty: false,
    isOwnGoal: true,
  ),
  Booking(
    minute: 30,
    half: 1,
    clubId: 2,
    playerId: 14,
    kind: CardKind.secondYellow,
    reason: FoulKind.lastMan,
  ),
  Injury(
    minute: 33,
    half: 1,
    clubId: 2,
    playerId: 13,
    injury: InjuryStub(daysLeft: 14, type: 'hamstring'),
  ),
  Substitution(
    minute: 34,
    half: 1,
    clubId: 2,
    outId: 13,
    inId: 20,
    reason: SubReason.injury,
  ),
  HalfTime(minute: 45, half: 1, clubId: 1),
  PenaltyMissed(
    minute: 60,
    half: 2,
    clubId: 2,
    playerId: 19,
    outcome: ShotOutcome.post,
  ),
  TacticChange(
    minute: 70,
    half: 2,
    clubId: 2,
    mentality: Mentality.veryAttacking,
  ),
  FullTime(minute: 90, half: 2, clubId: 1),
  ExtraTimeStart(minute: 90, half: 3, clubId: 1),
  ShootoutStart(minute: 120, half: 5, clubId: 1),
  ShootoutKick(minute: 120, half: 5, clubId: 1, playerId: 10, scored: true),
];

MatchResult _fullResult() => MatchResult(
  homeGoals: 2,
  awayGoals: 2,
  goals: [
    GoalEvent(minute: 12, scorerId: 10, clubId: 1),
    GoalEvent(minute: 40, scorerId: 15, clubId: 1),
  ],
  matchSeed: 77,
  homeStats: TeamStats(
    shots: 14,
    onTarget: 6,
    blocked: 3,
    corners: 7,
    fouls: 11,
    yellows: 2,
    reds: 0,
    offsides: 3,
    possessionPct: 55,
    xg: 1.85,
  ),
  awayStats: TeamStats(
    shots: 8,
    onTarget: 3,
    blocked: 1,
    corners: 2,
    fouls: 15,
    yellows: 3,
    reds: 1,
    offsides: 1,
    possessionPct: 45,
    xg: 0.9,
  ),
  events: _allMatchEvents(),
  ratings: {15: 6.5, 9: 7.25, 10: 8.0},
  manOfTheMatch: 10,
  conditions: const MatchConditions(
    weather: Weather.rainy,
    pitch: 6,
    attendance: 31500,
    homeAdvantage: 1.065,
  ),
  homeShootout: 4,
  awayShootout: 3,
  abandoned: true,
  finalCondition: {10: 70.0, 9: 61.5},
);

void main() {
  group('world json', () {
    test('worldToJson(worldFromJson(j)) deep-equals j', () {
      final j = worldToJson(_world());
      final again = worldToJson(worldFromJson(j));
      expect(_deep.equals(again, j), isTrue);
    });

    test('round trip is byte-identical through jsonEncode/jsonDecode', () {
      final encoded = jsonEncode(worldToJson(_world()));
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      expect(jsonEncode(worldToJson(worldFromJson(decoded))), encoded);
    });

    test('restored world has the same content and rebuilt indexes', () {
      final w = _world();
      final r = worldFromJson(
        jsonDecode(jsonEncode(worldToJson(w))) as Map<String, dynamic>,
      );
      expect(r.players.length, 40);
      expect(r.players[3]!.contract, isNull);
      expect(r.players[4]!.state.injury!.type, 'hamstring');
      expect(r.players[5]!.loan!.parentClubId, 3);
      expect(r.players[7]!.attrs.toList(), w.players[7]!.attrs.toList());
      expect(r.players[7]!.familiarity, w.players[7]!.familiarity);
      expect(r.fixtures[1]!.result!.goals.map((g) => g.scorerId), [10, 15, 9]);
      expect(r.squadOf(1), w.squadOf(1));
      expect(r.youthOf(1), [1, 2]);
      expect(r.fixturesOn(_d), w.fixturesOn(_d));
      expect(r.userClub!.id, 1);
      expect(r.inbox[2].event, isA<YouthIntake>());
      expect(r.ids.toJson(), {'player': 40, 'club': 4});
    });

    test('inbox messages carry their id, emitted first, and round-trip it', () {
      final j = worldToJson(_world());
      final inbox = j['inbox'] as List;
      expect((inbox[0] as Map).keys.toList(), ['id', 'date', 'event', 'read']);
      expect([for (final m in inbox) (m as Map)['id']], [1, 2, 3]);
      final r = worldFromJson(
        jsonDecode(jsonEncode(j)) as Map<String, dynamic>,
      );
      expect(r.inbox.map((m) => m.id), [1, 2, 3]);
    });

    test('id-keyed maps are emitted in ascending numeric order', () {
      final j = worldToJson(_world());
      final ascending = [for (var i = 1; i <= 40; i++) '$i'];
      expect((j['players'] as Map).keys.toList(), ascending);
      for (final k in ['countries', 'leagues', 'managers']) {
        expect((j[k] as Map).keys.toList(), ['1', '2'], reason: k);
      }
      expect((j['clubs'] as Map).keys.toList(), ['1', '2', '3', '4']);
      expect((j['fixtures'] as Map).keys.toList(), [
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
      ]);
      final archive = (j['history'] as List).single as Map;
      expect((archive['champions'] as Map).keys.toList(), ['1', '2']);
      expect((archive['finalOrder'] as Map).keys.toList(), ['1', '2']);
    });

    test('familiarity is keyed by position name in Position.values order', () {
      final j = playerToJson(_player(1));
      expect((j['familiarity'] as Map).keys.toList(), ['dl', 'dc', 'st']);
    });
  });

  group('tactic json', () {
    test('club carries tactics and activeTactic in place of formation', () {
      final j = clubToJson(_club(2, 1));
      expect(j.keys, isNot(contains('formation')));
      expect(j.keys.toList().sublist(j.keys.length - 3), [
        'lineup',
        'tactics',
        'activeTactic',
      ]);
      expect((j['tactics'] as List), hasLength(3));
      expect(j['activeTactic'], 2);
    });

    test('keys are in declaration order', () {
      final j = tacticToJson(_richTactic());
      expect(j.keys.toList(), [
        'name',
        'formation',
        'slots',
        'mentality',
        'passing',
        'tempo',
        'width',
        'pressing',
        'tackling',
        'marking',
        'offsideTrap',
        'counterAttack',
        'playmaker',
        'targetMan',
        'captain',
        'viceCaptain',
        'setPieces',
        'instructions',
        'arrows',
      ]);
      expect(j['formation'], 'custom');
      expect((j['slots'] as List).take(2), ['gk', 'dc']);
      expect((j['setPieces'] as Map).keys.toList(), [
        'cornerLeft',
        'cornerRight',
        'freeKickLeft',
        'freeKickRight',
        'penalty',
        'longThrow',
      ]);
      expect((j['setPieces'] as Map)['freeKickRight'], isNull);
      expect((j['instructions'] as Map).keys.toList(), ['2', '7', '10']);
      expect(((j['instructions'] as Map)['10'] as Map).keys.toList(), [
        'forwardRuns',
        'runWithBall',
        'longShots',
        'throughBalls',
        'holdUpBall',
        'freeRole',
        'crossFrom',
      ]);
      expect((j['arrows'] as Map), {'1': 'none', '4': 'back', '9': 'forward'});
    });

    test('a rich custom tactic round-trips', () {
      final t = _richTactic();
      final r = tacticFromJson(
        jsonDecode(jsonEncode(tacticToJson(t))) as Map<String, dynamic>,
      );
      expect(r.name, 'Custom');
      expect(r.formation, Formation.custom);
      expect(r.slots, t.slots);
      expect(r.mentality, Mentality.attacking);
      expect(r.passing, PassingStyle.direct);
      expect(r.tempo, Tempo.fast);
      expect(r.width, Width.wide);
      expect(r.pressing, Pressing.high);
      expect(r.tackling, Tackling.hard);
      expect(r.marking, Marking.man);
      expect(r.offsideTrap, isTrue);
      expect(r.counterAttack, isTrue);
      expect(r.playmaker, 6);
      expect(r.targetMan, 11);
      expect(r.captain, 2);
      expect(r.viceCaptain, 3);
      expect(r.setPieces.cornerLeft, 8);
      expect(r.setPieces.cornerRight, 9);
      expect(r.setPieces.freeKickLeft, 6);
      expect(r.setPieces.freeKickRight, isNull);
      expect(r.setPieces.penalty, 11);
      expect(r.setPieces.longThrow, isNull);
      expect(r.instructions.keys.toList(), [2, 7, 10]);
      final i10 = r.instructions[10]!;
      expect(i10.forwardRuns, isTrue);
      expect(i10.runWithBall, isFalse);
      expect(i10.crossFrom, CrossTarget.far);
      final i7 = r.instructions[7]!;
      expect(i7.runWithBall, isTrue);
      expect(i7.longShots, isTrue);
      expect(i7.throughBalls, isTrue);
      expect(i7.crossFrom, CrossTarget.near);
      expect(r.instructions[2]!.holdUpBall, isTrue);
      expect(r.instructions[2]!.freeRole, isTrue);
      expect(r.arrows, {1: Arrow.none, 4: Arrow.back, 9: Arrow.forward});
      expect(jsonEncode(tacticToJson(r)), jsonEncode(tacticToJson(t)));
    });
  });

  group('match result json', () {
    test('a v2 result decodes with defaults and re-encodes every key', () {
      final r = matchResultFromJson({
        'homeGoals': 1,
        'awayGoals': 0,
        'goals': [
          {'minute': 5, 'scorerId': 3, 'clubId': 1},
        ],
        'matchSeed': 9,
      });
      expect(r.homeStats, isNull);
      expect(r.awayStats, isNull);
      expect(r.events, isEmpty);
      expect(r.ratings, isEmpty);
      expect(r.manOfTheMatch, isNull);
      expect(r.conditions, isNull);
      expect(r.homeShootout, isNull);
      expect(r.awayShootout, isNull);
      expect(r.abandoned, isFalse);
      expect(r.finalCondition, isEmpty);
      expect(matchResultToJson(r), {
        'homeGoals': 1,
        'awayGoals': 0,
        'goals': [
          {'minute': 5, 'scorerId': 3, 'clubId': 1},
        ],
        'matchSeed': 9,
        'homeStats': null,
        'awayStats': null,
        'events': <Object>[],
        'ratings': <String, Object>{},
        'manOfTheMatch': null,
        'conditions': null,
        'homeShootout': null,
        'awayShootout': null,
        'abandoned': false,
      });
    });

    test('a full result round-trips byte-identically', () {
      final events = _allMatchEvents();
      expect(
        events.map((e) => e.runtimeType).toSet(),
        hasLength(11), // every MatchEvent subtype
      );
      final j = matchResultToJson(_fullResult());
      final encoded = jsonEncode(j);
      final back = matchResultFromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
      expect(jsonEncode(matchResultToJson(back)), encoded);
      expect(back.events.map((e) => e.runtimeType).toList(), [
        for (final e in events) e.runtimeType,
      ]);
      expect(back.ratings, {9: 7.25, 10: 8.0, 15: 6.5});
      expect(back.homeStats!.xg, 1.85);
      expect(back.conditions!.weather, Weather.rainy);
      expect(back.conditions!.homeAdvantage, 1.065);
      expect((back.events[1] as Goal).isOwnGoal, isTrue);
      expect((back.events[0] as Goal).assistId, 9);
      expect((back.events[2] as Booking).kind, CardKind.secondYellow);
      final injury = back.events[3] as Injury;
      expect(injury.severityDays, 14);
      expect(injury.injury.type, 'hamstring');
      expect(back.homeShootout, 4);
      expect(back.abandoned, isTrue);
      // finalCondition is in-memory only (consumed before any save).
      expect(back.finalCondition, isEmpty);
    });

    test('ratings are keyed by ascending player id, events by type', () {
      final j = matchResultToJson(_fullResult());
      expect((j['ratings'] as Map).keys.toList(), ['9', '10', '15']);
      expect(
        [for (final e in j['events'] as List) (e as Map)['t']],
        [for (final e in _allMatchEvents()) e.runtimeType.toString()],
      );
      expect((j['events'] as List).first, {
        't': 'Goal',
        'minute': 12,
        'half': 1,
        'clubId': 1,
        'scorerId': 10,
        'assistId': 9,
        'type': 'throughBall',
        'isPenalty': false,
        'isOwnGoal': false,
      });
    });

    test('unknown match event type throws FormatException', () {
      expect(
        () => matchEventFromJson({
          't': 'Nope',
          'minute': 1,
          'half': 1,
          'clubId': 1,
        }),
        throwsFormatException,
      );
    });
  });

  group('event json', () {
    test('every GameEvent subtype round-trips', () {
      final events = _allEvents();
      expect(events.map((e) => e.runtimeType).toSet(), hasLength(12));
      for (final e in events) {
        final j = eventToJson(e);
        expect(j['t'], e.runtimeType.toString());
        expect(j['date'], _d.dayIndex);
        final back = eventFromJson(
          jsonDecode(jsonEncode(j)) as Map<String, dynamic>,
        );
        expect(back.runtimeType, e.runtimeType);
        expect(eventToJson(back), j);
      }
    });

    test('PlayerRetired with null club round-trips', () {
      final j = eventToJson(PlayerRetired(date: _d, playerId: 1, clubId: null));
      expect(j, {
        't': 'PlayerRetired',
        'date': _d.dayIndex,
        'playerId': 1,
        'clubId': null,
      });
      expect(eventToJson(eventFromJson(j)), j);
    });

    test('unknown event type throws FormatException', () {
      expect(
        () => eventFromJson({'t': 'Bogus', 'date': 0}),
        throwsFormatException,
      );
    });
  });
}
