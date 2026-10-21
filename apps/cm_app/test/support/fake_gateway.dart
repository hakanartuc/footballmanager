import 'dart:async';
import 'dart:typed_data';

import 'package:cm_app/engine/engine_gateway.dart';
import 'package:cm_app/engine/snapshots.dart';
import 'package:engine/engine.dart';

/// A scripted [EngineGateway] for UI tests: returns the settable snapshot
/// fields, logs every call in [calls] and throws [failNext] once.
class FakeGateway implements EngineGateway {
  FakeGateway({
    required this.homeSnapshot,
    required this.refsSnapshot,
    this.squadRows = const [],
    this.playerDetail,
    this.lineupView,
    this.tableRows = const [],
    this.fixtureRows = const [],
    this.inboxItems = const [],
  });

  /// One club (id 1) in a 4-team league (id 10) of Türkiye (id 100), with
  /// 3 fixtures and 2 unread inbox items.
  factory FakeGateway.ready() {
    const clubs = [
      ClubRef(
        id: 1,
        name: 'Alpha FC',
        shortName: 'ALP',
        kitPrimary: 0xFFC62828,
        kitSecondary: 0xFFFFFFFF,
        leagueId: 10,
        countryId: 100,
      ),
      ClubRef(
        id: 2,
        name: 'Beta SK',
        shortName: 'BET',
        kitPrimary: 0xFF1565C0,
        kitSecondary: 0xFFFFEB3B,
        leagueId: 10,
        countryId: 100,
      ),
      ClubRef(
        id: 3,
        name: 'Gamma Spor',
        shortName: 'GAM',
        kitPrimary: 0xFF2E7D32,
        kitSecondary: 0xFF000000,
        leagueId: 10,
        countryId: 100,
      ),
      ClubRef(
        id: 4,
        name: 'Delta United',
        shortName: 'DEL',
        kitPrimary: 0xFF6A1B9A,
        kitSecondary: 0xFFFFFFFF,
        leagueId: 10,
        countryId: 100,
      ),
    ];
    final day1 = GameDate.ymd(2026, 7, 1);
    FixtureRow fixture(int id, int round, int home, int away) => FixtureRow(
      id: id,
      round: round,
      date: day1.addDays(7 * round),
      homeId: home,
      awayId: away,
      homeName: clubs[home - 1].name,
      awayName: clubs[away - 1].name,
      homeGoals: null,
      awayGoals: null,
      goals: const [],
    );
    TableRowView row(int rank, int club) => TableRowView(
      rank: rank,
      clubId: club,
      clubName: clubs[club - 1].name,
      played: 0,
      won: 0,
      drawn: 0,
      lost: 0,
      gf: 0,
      ga: 0,
      gd: 0,
      points: 0,
      isUser: club == 1,
    );
    final fixtures = [
      fixture(1, 1, 1, 2),
      fixture(2, 2, 3, 1),
      fixture(3, 3, 1, 4),
    ];
    return FakeGateway(
      homeSnapshot: HomeSnapshot(
        date: day1,
        seasonYear: 2026,
        clubId: 1,
        clubName: 'Alpha FC',
        leagueId: 10,
        leaguePosition: 1,
        nextMatch: NextMatch(
          fixtureId: 1,
          date: fixtures.first.date,
          homeId: 1,
          awayId: 2,
          homeName: 'Alpha FC',
          awayName: 'Beta SK',
          isHome: true,
        ),
        isMatchDay: false,
        unreadCount: 2,
        seniorCount: 22,
        injuredCount: 0,
        suspendedCount: 0,
        managerName: 'Test Manager',
      ),
      refsSnapshot: const WorldRefs(
        countries: [
          CountryRef(id: 100, code: 'TR', name: 'Türkiye', leagueIds: [10]),
        ],
        leagues: [
          LeagueRef(
            id: 10,
            name: 'TR_tier1',
            countryCode: 'TR',
            tier: 1,
            clubIds: [1, 2, 3, 4],
          ),
        ],
        clubs: clubs,
      ),
      tableRows: [row(1, 1), row(2, 2), row(3, 3), row(4, 4)],
      fixtureRows: fixtures,
      inboxItems: [
        InboxItem(
          id: 2,
          date: day1,
          read: false,
          event: NewSeasonStarted(date: day1, seasonYear: 2026),
          labels: const InboxLabels(),
        ),
        InboxItem(
          id: 1,
          date: day1,
          read: false,
          event: YouthIntake(date: day1, clubId: 1, playerIds: const []),
          labels: const InboxLabels(clubName: 'Alpha FC'),
        ),
      ],
    );
  }

  /// [FakeGateway.ready] on a match day with a full squad, a player
  /// detail, a valid 4-4-2 lineup and more inbox items, for goldens.
  factory FakeGateway.rich() {
    final g = FakeGateway.ready();
    SquadRow row(
      int id,
      String name,
      Position position,
      int ca, {
      bool injured = false,
      int suspension = 0,
      bool youth = false,
    }) => SquadRow(
      id: id,
      name: name,
      position: position,
      age: youth ? 17 : 20 + id % 12,
      ca: ca,
      condition: 100 - id % 15,
      injured: injured,
      suspension: suspension,
      status: youth ? PlayerStatus.youth : PlayerStatus.firstTeam,
      isYouth: youth,
    );
    final day = g.homeSnapshot.date;
    InboxItem item(
      int id,
      GameEvent event,
      InboxLabels labels, {
      bool read = true,
    }) =>
        InboxItem(id: id, date: day, read: read, event: event, labels: labels);
    g
      ..homeSnapshot = copyHome(g.homeSnapshot, isMatchDay: true)
      ..squadRows = [
        row(1, 'Emre Kaya', Position.gk, 128),
        row(2, 'Can Demir', Position.dl, 112),
        row(3, 'Mert Yılmaz', Position.dc, 121),
        row(4, 'Burak Şahin', Position.dc, 118),
        row(5, 'Ali Çelik', Position.dr, 109),
        row(6, 'Kerem Aydın', Position.ml, 115),
        row(7, 'Arda Öztürk', Position.mc, 131),
        row(8, 'Yusuf Arslan', Position.mc, 119),
        row(9, 'Oğuz Koç', Position.mr, 113),
        row(10, 'Hakan Polat', Position.st, 134),
        row(11, 'Cenk Erdoğan', Position.st, 122),
        row(12, 'Deniz Kurt', Position.gk, 97),
        row(13, 'Selim Aksoy', Position.st, 101),
        row(14, 'Tolga Güneş', Position.mc, 125, injured: true),
        row(15, 'Serkan Uçar', Position.dc, 117, suspension: 1),
        row(16, 'Efe Bulut', Position.st, 64, youth: true),
      ]
      ..playerDetail = PlayerDetail(
        id: 10,
        name: 'Hakan Polat',
        countryCode: 'TR',
        position: Position.st,
        familiarity: const {Position.st: 20, Position.amc: 14},
        age: 26,
        heightCm: 184,
        attrs: [for (var i = 0; i < Attr.values.length; i++) 6 + i * 7 % 15],
        ca: 134,
        pa: 158,
        condition: 96,
        morale: 75,
        sharpness: 82,
        form: 7.1,
        wageWeekly: 18500,
        contractEnd: GameDate.ymd(2028, 6, 30),
        status: PlayerStatus.keyPlayer,
        apps: 12,
        goals: 8,
        assists: 3,
      )
      ..lineupView = LineupView(
        formation: Formation.f442,
        slots: formationSlots(Formation.f442),
        starters: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
        bench: const [12, 13],
        errors: const [],
      )
      ..inboxItems = [
        item(
          5,
          PlayerRetired(date: day, playerId: 99, clubId: 2),
          const InboxLabels(clubName: 'Beta SK', playerNames: ['Volkan Er']),
        ),
        item(
          4,
          LeagueChampion(date: day, leagueId: 10, clubId: 3),
          const InboxLabels(
            clubName: 'Gamma Spor',
            leagueCountryCode: 'TR',
            leagueTier: 1,
          ),
        ),
        item(3, SeasonEnded(date: day, seasonYear: 2025), const InboxLabels()),
        ...g.inboxItems,
      ];
    return g;
  }

  HomeSnapshot homeSnapshot;
  WorldRefs refsSnapshot;
  List<SquadRow> squadRows;
  PlayerDetail? playerDetail;
  LineupView? lineupView;
  List<TableRowView> tableRows;
  List<FixtureRow> fixtureRows;
  List<InboxItem> inboxItems;

  AdvanceOutcome? advanceOutcome;
  AdvanceOutcome? playOutcome;

  /// Thrown by the next call, then cleared.
  GatewayError? failNext;

  /// When set, every call waits for it before answering.
  Completer<void>? hold;

  /// Method names in call order.
  final List<String> calls = [];

  /// The spec of the latest [newGame] call.
  NewGameSpec? lastSpec;

  /// The commands of each [playToday] call.
  final List<List<Command>> playTodayCommands = [];

  Future<T> _call<T>(String name, T Function() result) async {
    calls.add(name);
    await hold?.future;
    final error = failNext;
    if (error != null) {
      failNext = null;
      throw error;
    }
    return result();
  }

  AdvanceOutcome _outcome(StopReason reason) => AdvanceOutcome(
    daysAdvanced: 1,
    reason: reason,
    date: homeSnapshot.date,
    userMatch: null,
    seasonEnded: false,
    newInboxCount: 0,
  );

  @override
  Future<void> newGame(NewGameSpec spec) =>
      _call('newGame', () => lastSpec = spec);

  @override
  Future<void> load(Uint8List bytes) => _call('load', () {});

  @override
  Future<Uint8List> save() => _call('save', () => Uint8List.fromList([1]));

  @override
  Future<AdvanceOutcome> advanceToNext({int maxDays = 90}) => _call(
    'advanceToNext',
    () => advanceOutcome ?? _outcome(StopReason.reachedLimit),
  );

  @override
  Future<AdvanceOutcome> playToday(List<Command> commands) =>
      _call('playToday', () {
        playTodayCommands.add(commands);
        return playOutcome ?? _outcome(StopReason.played);
      });

  @override
  Future<WorldRefs> refs() => _call('refs', () => refsSnapshot);

  @override
  Future<HomeSnapshot> home() => _call('home', () => homeSnapshot);

  @override
  Future<List<SquadRow>> squad(ClubId clubId, {bool youth = false}) => _call(
    'squad',
    () => [
      for (final r in squadRows)
        if (r.isYouth == youth) r,
    ],
  );

  @override
  Future<PlayerDetail> player(PlayerId id) =>
      _call('player', () => playerDetail!);

  /// The `auto` argument of each [lineup] call.
  final List<bool> lineupAutoArgs = [];

  /// Returned by `lineup(auto: true)`; [lineupView] when null.
  LineupView? autoLineupView;

  @override
  Future<LineupView> lineup(ClubId clubId, {bool auto = false}) =>
      _call('lineup', () {
        lineupAutoArgs.add(auto);
        return (auto ? autoLineupView : null) ?? lineupView!;
      });

  /// The league id of each [table] call.
  final List<LeagueId> tableArgs = [];

  @override
  Future<List<TableRowView>> table(LeagueId leagueId) {
    tableArgs.add(leagueId);
    return _call('table', () => tableRows);
  }

  /// The club id of each [clubFixtures] call.
  final List<ClubId> clubFixturesArgs = [];

  @override
  Future<List<FixtureRow>> clubFixtures(ClubId clubId) {
    clubFixturesArgs.add(clubId);
    return _call('clubFixtures', () => fixtureRows);
  }

  /// Thrown by every [inbox] call while set.
  GatewayError? inboxError;

  @override
  Future<List<InboxItem>> inbox() => _call('inbox', () {
    if (inboxError case final e?) throw e;
    return inboxItems;
  });

  /// Marks the item read and recounts [HomeSnapshot.unreadCount], like the
  /// real gateway.
  @override
  Future<void> markRead(int inboxId) => _call('markRead', () {
    inboxItems = [
      for (final i in inboxItems)
        i.id == inboxId
            ? InboxItem(
                id: i.id,
                date: i.date,
                read: true,
                event: i.event,
                labels: i.labels,
              )
            : i,
    ];
    homeSnapshot = copyHome(
      homeSnapshot,
      unreadCount: inboxItems.where((i) => !i.read).length,
    );
  });

  @override
  Future<void> dispose() => _call('dispose', () {});
}

/// [h] with the given fields replaced; [unemployed] clears the club fields.
HomeSnapshot copyHome(
  HomeSnapshot h, {
  GameDate? date,
  int? unreadCount,
  bool? isMatchDay,
  bool unemployed = false,
}) => HomeSnapshot(
  date: date ?? h.date,
  seasonYear: h.seasonYear,
  clubId: unemployed ? null : h.clubId,
  clubName: unemployed ? null : h.clubName,
  leagueId: unemployed ? null : h.leagueId,
  leaguePosition: unemployed ? null : h.leaguePosition,
  nextMatch: unemployed ? null : h.nextMatch,
  isMatchDay: isMatchDay ?? h.isMatchDay,
  unreadCount: unreadCount ?? h.unreadCount,
  seniorCount: unemployed ? 0 : h.seniorCount,
  injuredCount: unemployed ? 0 : h.injuredCount,
  suspendedCount: unemployed ? 0 : h.suspendedCount,
  managerName: h.managerName,
);
