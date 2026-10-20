import '../core/game_date.dart';
import '../core/ids.dart';
import 'attributes.dart';
import 'calendar.dart';
import 'club.dart';
import 'country.dart';
import 'enums.dart';
import 'events.dart';
import 'fixture.dart';
import 'manager.dart';
import 'player.dart';
import 'world.dart';

// Hand-written JSON codec for the whole model: the save format and the
// determinism oracle. Keys are written in field declaration order and
// id-keyed maps in ascending numeric id order, so `jsonEncode` output is
// byte-identical for identical worlds.

List<int> _ints(dynamic l) => [for (final e in l as List) e as int];

double _double(dynamic v) => (v as num).toDouble();

GameDate _date(dynamic v) => GameDate(v as int);

Map<String, dynamic> _obj(dynamic v) => v as Map<String, dynamic>;

/// [m] as an object keyed by decimal ids in ascending order.
Map<String, dynamic> _idMapToJson<T>(Map<int, T> m, dynamic Function(T) f) => {
  for (final k in m.keys.toList()..sort()) '$k': f(m[k] as T),
};

Map<int, T> _idMapFromJson<T>(dynamic j, T Function(dynamic) f) => {
  for (final e in _obj(j).entries) int.parse(e.key): f(e.value),
};

// ---- world ----

Map<String, dynamic> worldToJson(World w) => {
  'schemaVersion': w.schemaVersion,
  'seed': w.seed,
  'date': w.date.dayIndex,
  'seasonYear': w.seasonYear,
  'countries': _idMapToJson(w.countries, countryToJson),
  'leagues': _idMapToJson(w.leagues, leagueToJson),
  'clubs': _idMapToJson(w.clubs, clubToJson),
  'players': _idMapToJson(w.players, playerToJson),
  'managers': _idMapToJson(w.managers, managerToJson),
  'fixtures': _idMapToJson(w.fixtures, fixtureToJson),
  'calendar': calendarToJson(w.calendar),
  'userManagerId': w.userManagerId,
  'inbox': [for (final m in w.inbox) inboxMessageToJson(m)],
  'history': [for (final a in w.history) seasonArchiveToJson(a)],
  'ids': w.ids.toJson(),
};

World worldFromJson(Map<String, dynamic> j) => World(
  schemaVersion: j['schemaVersion'] as int,
  seed: j['seed'] as int,
  date: _date(j['date']),
  seasonYear: j['seasonYear'] as int,
  countries: _idMapFromJson(j['countries'], (v) => countryFromJson(_obj(v))),
  leagues: _idMapFromJson(j['leagues'], (v) => leagueFromJson(_obj(v))),
  clubs: _idMapFromJson(j['clubs'], (v) => clubFromJson(_obj(v))),
  players: _idMapFromJson(j['players'], (v) => playerFromJson(_obj(v))),
  managers: _idMapFromJson(j['managers'], (v) => managerFromJson(_obj(v))),
  fixtures: _idMapFromJson(j['fixtures'], (v) => fixtureFromJson(_obj(v))),
  calendar: calendarFromJson(_obj(j['calendar'])),
  userManagerId: j['userManagerId'] as int,
  inbox: [for (final m in j['inbox'] as List) inboxMessageFromJson(_obj(m))],
  history: [
    for (final a in j['history'] as List) seasonArchiveFromJson(_obj(a)),
  ],
  ids: IdAllocator.fromJson(_obj(j['ids'])),
);

Map<String, dynamic> seasonArchiveToJson(SeasonArchive a) => {
  'seasonYear': a.seasonYear,
  'champions': _idMapToJson(a.champions, (c) => c),
  'finalOrder': _idMapToJson(a.finalOrder, (l) => List.of(l)),
};

SeasonArchive seasonArchiveFromJson(Map<String, dynamic> j) => SeasonArchive(
  seasonYear: j['seasonYear'] as int,
  champions: _idMapFromJson(j['champions'], (v) => v as int),
  finalOrder: _idMapFromJson(j['finalOrder'], _ints),
);

// ---- country / league ----

Map<String, dynamic> countryToJson(Country c) => {
  'id': c.id,
  'code': c.code,
  'name': c.name,
  'continent': c.continent.name,
  'namePool': c.namePool,
  'tiers': List.of(c.tiers),
};

Country countryFromJson(Map<String, dynamic> j) => Country(
  id: j['id'] as int,
  code: j['code'] as String,
  name: j['name'] as String,
  continent: Continent.values.byName(j['continent'] as String),
  namePool: j['namePool'] as String,
  tiers: _ints(j['tiers']),
);

Map<String, dynamic> leagueToJson(League l) => {
  'id': l.id,
  'countryId': l.countryId,
  'tier': l.tier,
  'name': l.name,
  'clubIds': List.of(l.clubIds),
  'promotedCount': l.promotedCount,
  'relegatedCount': l.relegatedCount,
  'reputation': l.reputation,
};

League leagueFromJson(Map<String, dynamic> j) => League(
  id: j['id'] as int,
  countryId: j['countryId'] as int,
  tier: j['tier'] as int,
  name: j['name'] as String,
  clubIds: _ints(j['clubIds']),
  promotedCount: j['promotedCount'] as int,
  relegatedCount: j['relegatedCount'] as int,
  reputation: j['reputation'] as int,
);

// ---- club ----

Map<String, dynamic> kitToJson(Kit k) => {
  'primary': k.primary,
  'secondary': k.secondary,
};

Kit kitFromJson(Map<String, dynamic> j) =>
    Kit(primary: j['primary'] as int, secondary: j['secondary'] as int);

Map<String, dynamic> logoSpecToJson(LogoSpec l) => {
  'shape': l.shape,
  'color1': l.color1,
  'color2': l.color2,
};

LogoSpec logoSpecFromJson(Map<String, dynamic> j) => LogoSpec(
  shape: j['shape'] as int,
  color1: j['color1'] as int,
  color2: j['color2'] as int,
);

Map<String, dynamic> facilitiesToJson(Facilities f) => {
  'training': f.training,
  'medical': f.medical,
  'youth': f.youth,
};

Facilities facilitiesFromJson(Map<String, dynamic> j) => Facilities(
  training: j['training'] as int,
  medical: j['medical'] as int,
  youth: j['youth'] as int,
);

Map<String, dynamic> lineupToJson(Lineup l) => {
  'formation': l.formation.name,
  'starters': List.of(l.starters),
  'bench': List.of(l.bench),
};

Lineup lineupFromJson(Map<String, dynamic> j) => Lineup(
  formation: Formation.values.byName(j['formation'] as String),
  starters: _ints(j['starters']),
  bench: _ints(j['bench']),
);

Map<String, dynamic> clubToJson(Club c) => {
  'id': c.id,
  'name': c.name,
  'shortName': c.shortName,
  'countryId': c.countryId,
  'leagueId': c.leagueId,
  'reputation': c.reputation,
  'home': kitToJson(c.home),
  'away': kitToJson(c.away),
  'logo': logoSpecToJson(c.logo),
  'stadiumName': c.stadiumName,
  'stadiumCapacity': c.stadiumCapacity,
  'balance': c.balance,
  'transferBudget': c.transferBudget,
  'wageBudget': c.wageBudget,
  'facilities': facilitiesToJson(c.facilities),
  'managerId': c.managerId,
  'expectation': c.expectation.name,
  'boardConfidence': c.boardConfidence,
  'lineup': c.lineup == null ? null : lineupToJson(c.lineup!),
  'formation': c.formation.name,
};

Club clubFromJson(Map<String, dynamic> j) => Club(
  id: j['id'] as int,
  name: j['name'] as String,
  shortName: j['shortName'] as String,
  countryId: j['countryId'] as int,
  leagueId: j['leagueId'] as int,
  reputation: j['reputation'] as int,
  home: kitFromJson(_obj(j['home'])),
  away: kitFromJson(_obj(j['away'])),
  logo: logoSpecFromJson(_obj(j['logo'])),
  stadiumName: j['stadiumName'] as String,
  stadiumCapacity: j['stadiumCapacity'] as int,
  balance: j['balance'] as int,
  transferBudget: j['transferBudget'] as int,
  wageBudget: j['wageBudget'] as int,
  facilities: facilitiesFromJson(_obj(j['facilities'])),
  managerId: j['managerId'] as int?,
  expectation: BoardExpectation.values.byName(j['expectation'] as String),
  boardConfidence: _double(j['boardConfidence']),
  lineup: j['lineup'] == null ? null : lineupFromJson(_obj(j['lineup'])),
  formation: Formation.values.byName(j['formation'] as String),
);

// ---- player ----

Map<String, dynamic> hiddenAttrsToJson(HiddenAttrs h) => {
  'injuryProneness': h.injuryProneness,
  'consistency': h.consistency,
  'bigMatches': h.bigMatches,
  'professionalism': h.professionalism,
};

HiddenAttrs hiddenAttrsFromJson(Map<String, dynamic> j) => HiddenAttrs(
  injuryProneness: j['injuryProneness'] as int,
  consistency: j['consistency'] as int,
  bigMatches: j['bigMatches'] as int,
  professionalism: j['professionalism'] as int,
);

Map<String, dynamic> injuryStubToJson(InjuryStub i) => {
  'daysLeft': i.daysLeft,
  'type': i.type,
};

InjuryStub injuryStubFromJson(Map<String, dynamic> j) =>
    InjuryStub(daysLeft: j['daysLeft'] as int, type: j['type'] as String);

Map<String, dynamic> loanStubToJson(LoanStub l) => {
  'parentClubId': l.parentClubId,
  'end': l.end.dayIndex,
};

LoanStub loanStubFromJson(Map<String, dynamic> j) =>
    LoanStub(parentClubId: j['parentClubId'] as int, end: _date(j['end']));

Map<String, dynamic> playerStateToJson(PlayerState s) => {
  'condition': s.condition,
  'sharpness': s.sharpness,
  'morale': s.morale,
  'form': s.form,
  'yellowCards': s.yellowCards,
  'suspensionMatches': s.suspensionMatches,
  'injury': s.injury == null ? null : injuryStubToJson(s.injury!),
};

PlayerState playerStateFromJson(Map<String, dynamic> j) => PlayerState(
  condition: _double(j['condition']),
  sharpness: _double(j['sharpness']),
  morale: _double(j['morale']),
  form: _double(j['form']),
  yellowCards: j['yellowCards'] as int,
  suspensionMatches: j['suspensionMatches'] as int,
  injury: j['injury'] == null ? null : injuryStubFromJson(_obj(j['injury'])),
);

Map<String, dynamic> contractToJson(Contract c) => {
  'clubId': c.clubId,
  'wageWeekly': c.wageWeekly,
  'start': c.start.dayIndex,
  'end': c.end.dayIndex,
  'status': c.status.name,
  'squadNumber': c.squadNumber,
  'releaseFee': c.releaseFee,
};

Contract contractFromJson(Map<String, dynamic> j) => Contract(
  clubId: j['clubId'] as int,
  wageWeekly: j['wageWeekly'] as int,
  start: _date(j['start']),
  end: _date(j['end']),
  status: PlayerStatus.values.byName(j['status'] as String),
  squadNumber: j['squadNumber'] as int?,
  releaseFee: j['releaseFee'] as int?,
);

Map<String, dynamic> seasonStatsToJson(SeasonStats s) => {
  'apps': s.apps,
  'goals': s.goals,
  'assists': s.assists,
  'yellows': s.yellows,
  'reds': s.reds,
  'ratingSum': s.ratingSum,
};

SeasonStats seasonStatsFromJson(Map<String, dynamic> j) => SeasonStats(
  apps: j['apps'] as int,
  goals: j['goals'] as int,
  assists: j['assists'] as int,
  yellows: j['yellows'] as int,
  reds: j['reds'] as int,
  ratingSum: _double(j['ratingSum']),
);

Map<String, dynamic> careerLineToJson(CareerLine c) => {
  'seasonYear': c.seasonYear,
  'clubId': c.clubId,
  'stats': seasonStatsToJson(c.stats),
};

CareerLine careerLineFromJson(Map<String, dynamic> j) => CareerLine(
  seasonYear: j['seasonYear'] as int,
  clubId: j['clubId'] as int,
  stats: seasonStatsFromJson(_obj(j['stats'])),
);

Map<String, dynamic> playerToJson(Player p) => {
  'id': p.id,
  'firstName': p.firstName,
  'lastName': p.lastName,
  'nationality': p.nationality,
  'birth': p.birth.dayIndex,
  'heightCm': p.heightCm,
  'mainPosition': p.mainPosition.name,
  'familiarity': {
    for (final pos in Position.values)
      if (p.familiarity.containsKey(pos)) pos.name: p.familiarity[pos],
  },
  'attrs': p.attrs.toList(),
  'ca': p.ca,
  'pa': p.pa,
  'hidden': hiddenAttrsToJson(p.hidden),
  'state': playerStateToJson(p.state),
  'contract': p.contract == null ? null : contractToJson(p.contract!),
  'isYouth': p.isYouth,
  'season': seasonStatsToJson(p.season),
  'career': [for (final c in p.career) careerLineToJson(c)],
  'internationalCaps': p.internationalCaps,
  'internationalGoals': p.internationalGoals,
  'loan': p.loan == null ? null : loanStubToJson(p.loan!),
};

Player playerFromJson(Map<String, dynamic> j) => Player(
  id: j['id'] as int,
  firstName: j['firstName'] as String,
  lastName: j['lastName'] as String,
  nationality: j['nationality'] as int,
  birth: _date(j['birth']),
  heightCm: j['heightCm'] as int,
  mainPosition: Position.values.byName(j['mainPosition'] as String),
  familiarity: {
    for (final e in _obj(j['familiarity']).entries)
      Position.values.byName(e.key): e.value as int,
  },
  attrs: Attributes.fromList(_ints(j['attrs'])),
  ca: j['ca'] as int,
  pa: j['pa'] as int,
  hidden: hiddenAttrsFromJson(_obj(j['hidden'])),
  state: playerStateFromJson(_obj(j['state'])),
  contract: j['contract'] == null
      ? null
      : contractFromJson(_obj(j['contract'])),
  isYouth: j['isYouth'] as bool,
  season: seasonStatsFromJson(_obj(j['season'])),
  career: [for (final c in j['career'] as List) careerLineFromJson(_obj(c))],
  internationalCaps: j['internationalCaps'] as int,
  internationalGoals: j['internationalGoals'] as int,
  loan: j['loan'] == null ? null : loanStubFromJson(_obj(j['loan'])),
);

// ---- manager ----

Map<String, dynamic> managerToJson(Manager m) => {
  'id': m.id,
  'firstName': m.firstName,
  'lastName': m.lastName,
  'nationality': m.nationality,
  'birth': m.birth.dayIndex,
  'reputation': m.reputation,
  'clubId': m.clubId,
  'isUser': m.isUser,
  'preferredFormation': m.preferredFormation.name,
  'career': [for (final c in m.career) careerLineToJson(c)],
};

Manager managerFromJson(Map<String, dynamic> j) => Manager(
  id: j['id'] as int,
  firstName: j['firstName'] as String,
  lastName: j['lastName'] as String,
  nationality: j['nationality'] as int,
  birth: _date(j['birth']),
  reputation: j['reputation'] as int,
  clubId: j['clubId'] as int?,
  isUser: j['isUser'] as bool,
  preferredFormation: Formation.values.byName(
    j['preferredFormation'] as String,
  ),
  career: [for (final c in j['career'] as List) careerLineFromJson(_obj(c))],
);

// ---- fixture ----

Map<String, dynamic> goalEventToJson(GoalEvent g) => {
  'minute': g.minute,
  'scorerId': g.scorerId,
  'clubId': g.clubId,
};

GoalEvent goalEventFromJson(Map<String, dynamic> j) => GoalEvent(
  minute: j['minute'] as int,
  scorerId: j['scorerId'] as int,
  clubId: j['clubId'] as int,
);

Map<String, dynamic> matchResultToJson(MatchResult r) => {
  'homeGoals': r.homeGoals,
  'awayGoals': r.awayGoals,
  'goals': [for (final g in r.goals) goalEventToJson(g)],
  'matchSeed': r.matchSeed,
};

MatchResult matchResultFromJson(Map<String, dynamic> j) => MatchResult(
  homeGoals: j['homeGoals'] as int,
  awayGoals: j['awayGoals'] as int,
  goals: [for (final g in j['goals'] as List) goalEventFromJson(_obj(g))],
  matchSeed: j['matchSeed'] as int,
);

Map<String, dynamic> fixtureToJson(Fixture f) => {
  'id': f.id,
  'leagueId': f.leagueId,
  'seasonYear': f.seasonYear,
  'round': f.round,
  'date': f.date.dayIndex,
  'homeId': f.homeId,
  'awayId': f.awayId,
  'result': f.result == null ? null : matchResultToJson(f.result!),
};

Fixture fixtureFromJson(Map<String, dynamic> j) => Fixture(
  id: j['id'] as int,
  leagueId: j['leagueId'] as int,
  seasonYear: j['seasonYear'] as int,
  round: j['round'] as int,
  date: _date(j['date']),
  homeId: j['homeId'] as int,
  awayId: j['awayId'] as int,
  result: j['result'] == null ? null : matchResultFromJson(_obj(j['result'])),
);

// ---- calendar ----

Map<String, dynamic> transferWindowToJson(TransferWindow w) => {
  'open': w.open.dayIndex,
  'close': w.close.dayIndex,
};

TransferWindow transferWindowFromJson(Map<String, dynamic> j) =>
    TransferWindow(open: _date(j['open']), close: _date(j['close']));

Map<String, dynamic> breakPeriodToJson(BreakPeriod b) => {
  'start': b.start.dayIndex,
  'end': b.end.dayIndex,
};

BreakPeriod breakPeriodFromJson(Map<String, dynamic> j) =>
    BreakPeriod(start: _date(j['start']), end: _date(j['end']));

Map<String, dynamic> calendarToJson(SeasonCalendar c) => {
  'seasonYear': c.seasonYear,
  'seasonStart': c.seasonStart.dayIndex,
  'seasonEnd': c.seasonEnd.dayIndex,
  'internationalBreaks': [
    for (final b in c.internationalBreaks) breakPeriodToJson(b),
  ],
  'summer': transferWindowToJson(c.summer),
  'winter': transferWindowToJson(c.winter),
};

SeasonCalendar calendarFromJson(Map<String, dynamic> j) => SeasonCalendar(
  seasonYear: j['seasonYear'] as int,
  seasonStart: _date(j['seasonStart']),
  seasonEnd: _date(j['seasonEnd']),
  internationalBreaks: [
    for (final b in j['internationalBreaks'] as List)
      breakPeriodFromJson(_obj(b)),
  ],
  summer: transferWindowFromJson(_obj(j['summer'])),
  winter: transferWindowFromJson(_obj(j['winter'])),
);

// ---- events ----

Map<String, dynamic> eventToJson(GameEvent e) => {
  't': switch (e) {
    MatchPlayed() => 'MatchPlayed',
    SeasonEnded() => 'SeasonEnded',
    LeagueChampion() => 'LeagueChampion',
    Promoted() => 'Promoted',
    Relegated() => 'Relegated',
    PlayerRetired() => 'PlayerRetired',
    YouthIntake() => 'YouthIntake',
    YouthReleased() => 'YouthReleased',
    NewSeasonStarted() => 'NewSeasonStarted',
  },
  'date': e.date.dayIndex,
  ...switch (e) {
    MatchPlayed() => {'fixtureId': e.fixtureId},
    SeasonEnded() => {'seasonYear': e.seasonYear},
    LeagueChampion() => {'leagueId': e.leagueId, 'clubId': e.clubId},
    Promoted() => {
      'clubId': e.clubId,
      'fromLeagueId': e.fromLeagueId,
      'toLeagueId': e.toLeagueId,
    },
    Relegated() => {
      'clubId': e.clubId,
      'fromLeagueId': e.fromLeagueId,
      'toLeagueId': e.toLeagueId,
    },
    PlayerRetired() => {'playerId': e.playerId, 'clubId': e.clubId},
    YouthIntake() => {'clubId': e.clubId, 'playerIds': List.of(e.playerIds)},
    YouthReleased() => {'clubId': e.clubId, 'playerIds': List.of(e.playerIds)},
    NewSeasonStarted() => {'seasonYear': e.seasonYear},
  },
};

GameEvent eventFromJson(Map<String, dynamic> j) {
  final date = _date(j['date']);
  return switch (j['t']) {
    'MatchPlayed' => MatchPlayed(date: date, fixtureId: j['fixtureId'] as int),
    'SeasonEnded' => SeasonEnded(
      date: date,
      seasonYear: j['seasonYear'] as int,
    ),
    'LeagueChampion' => LeagueChampion(
      date: date,
      leagueId: j['leagueId'] as int,
      clubId: j['clubId'] as int,
    ),
    'Promoted' => Promoted(
      date: date,
      clubId: j['clubId'] as int,
      fromLeagueId: j['fromLeagueId'] as int,
      toLeagueId: j['toLeagueId'] as int,
    ),
    'Relegated' => Relegated(
      date: date,
      clubId: j['clubId'] as int,
      fromLeagueId: j['fromLeagueId'] as int,
      toLeagueId: j['toLeagueId'] as int,
    ),
    'PlayerRetired' => PlayerRetired(
      date: date,
      playerId: j['playerId'] as int,
      clubId: j['clubId'] as int?,
    ),
    'YouthIntake' => YouthIntake(
      date: date,
      clubId: j['clubId'] as int,
      playerIds: _ints(j['playerIds']),
    ),
    'YouthReleased' => YouthReleased(
      date: date,
      clubId: j['clubId'] as int,
      playerIds: _ints(j['playerIds']),
    ),
    'NewSeasonStarted' => NewSeasonStarted(
      date: date,
      seasonYear: j['seasonYear'] as int,
    ),
    final t => throw FormatException('Unknown event type: $t'),
  };
}

Map<String, dynamic> inboxMessageToJson(InboxMessage m) => {
  'date': m.date.dayIndex,
  'event': eventToJson(m.event),
  'read': m.read,
};

InboxMessage inboxMessageFromJson(Map<String, dynamic> j) => InboxMessage(
  date: _date(j['date']),
  event: eventFromJson(_obj(j['event'])),
  read: j['read'] as bool,
);
