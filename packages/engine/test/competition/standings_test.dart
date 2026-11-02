import 'package:engine/engine.dart';
import 'package:test/test.dart';

Club _club(ClubId id, String name) => Club(
  id: id,
  name: name,
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
  expectation: BoardExpectation.mid,
);

/// A fixture in league 1, season 2026 unless overridden; unplayed when
/// [score] is null.
Fixture _f(
  FixtureId id,
  ClubId home,
  ClubId away,
  (int, int)? score, {
  LeagueId leagueId = 1,
  int seasonYear = 2026,
}) => Fixture(
  id: id,
  leagueId: leagueId,
  seasonYear: seasonYear,
  round: 1,
  date: GameDate.ymd(seasonYear, 8, 8),
  homeId: home,
  awayId: away,
  result: score == null
      ? null
      : MatchResult(
          homeGoals: score.$1,
          awayGoals: score.$2,
          goals: [],
          matchSeed: 0,
        ),
);

/// League 1 holds the clubs of [names] in map order.
World _world(Map<ClubId, String> names, List<Fixture> fixtures) => World(
  schemaVersion: 1,
  seed: 1,
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
      clubIds: names.keys.toList(),
      promotedCount: 0,
      relegatedCount: 1,
      reputation: 60,
    ),
  },
  clubs: {for (final e in names.entries) e.key: _club(e.key, e.value)},
  players: {},
  managers: {},
  fixtures: {for (final f in fixtures) f.id: f},
  calendar: SeasonCalendar(
    seasonYear: 2026,
    seasonStart: GameDate.ymd(2026, 8, 1),
    seasonEnd: GameDate.ymd(2027, 5, 31),
    internationalBreaks: [],
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
  ids: IdAllocator(),
);

/// `[clubId, played, won, drawn, lost, gf, ga, points]`.
List<int> _row(TableRow r) => [
  r.clubId,
  r.played,
  r.won,
  r.drawn,
  r.lost,
  r.gf,
  r.ga,
  r.points,
];

List<ClubId> _order(World w) => [
  for (final r in computeTable(w, 1, 2026)) r.clubId,
];

void main() {
  group('scripted season', () {
    final w = _world(
      {1: 'Club 1', 2: 'Club 2', 3: 'Club 3', 4: 'Club 4'},
      [
        // Inserted out of id order.
        _f(3, 3, 1, (0, 1)),
        _f(1, 1, 2, (3, 1)),
        _f(2, 2, 3, (2, 2)),
        _f(4, 1, 3, null), // unplayed
        _f(5, 2, 1, (5, 0), seasonYear: 2025), // other season
        _f(6, 2, 1, (5, 0), leagueId: 2), // other league
      ],
    );
    final table = computeTable(w, 1, 2026);

    test('exact rows in order; club without fixtures last with zeros', () {
      expect(table.map(_row).toList(), [
        [1, 2, 2, 0, 0, 4, 1, 6],
        [3, 2, 0, 1, 1, 2, 3, 1],
        [2, 2, 0, 1, 1, 3, 5, 1],
        [4, 0, 0, 0, 0, 0, 0, 0],
      ]);
    });

    test('gd is gf - ga', () {
      expect(table.map((r) => r.gd).toList(), [3, -1, -2, 0]);
    });

    test('sum(gf) == sum(ga)', () {
      final gf = table.fold(0, (s, r) => s + r.gf);
      final ga = table.fold(0, (s, r) => s + r.ga);
      expect(gf, 9);
      expect(ga, gf);
    });
  });

  group('after a simulated season', () {
    test('every table equals a brute-force pass over all fixtures', () {
      final w = createNewGame(
        NewGameSpec(
          seed: 1,
          size: WorldSize.small,
          managerFirstName: 'Test',
          managerLastName: 'Manager',
          managerCountryCode: 'TR',
          startClubId: null,
        ),
      );
      final runner = DayRunner();
      final seasonEnd = w.calendar.seasonEnd;
      while (!w.date.isAfter(seasonEnd)) {
        runner.advanceDay(w, const []);
      }
      var played = 0;
      for (final league in w.leagues.values) {
        final rows = {
          for (final c in league.clubIds) c: [0, 0, 0, 0, 0, 0, 0],
        };
        for (final f in w.fixtures.values) {
          final r = f.result;
          if (f.leagueId != league.id || f.seasonYear != w.seasonYear) continue;
          if (r == null) continue;
          played++;
          for (final (club, gf, ga) in [
            (f.homeId, r.homeGoals, r.awayGoals),
            (f.awayId, r.awayGoals, r.homeGoals),
          ]) {
            final row = rows[club]!;
            row[0]++;
            row[4] += gf;
            row[5] += ga;
            if (gf > ga) {
              row[1]++;
              row[6] += 3;
            } else if (gf == ga) {
              row[2]++;
              row[6] += 1;
            } else {
              row[3]++;
            }
          }
        }
        final table = computeTable(w, league.id, w.seasonYear);
        expect(table, hasLength(league.clubIds.length));
        for (final r in table) {
          expect(_row(r).sublist(1), rows[r.clubId], reason: '${r.clubId}');
        }
        for (var i = 1; i < table.length; i++) {
          final a = table[i - 1], b = table[i];
          final inOrder =
              a.points > b.points ||
              a.points == b.points &&
                  (a.gd > b.gd || a.gd == b.gd && a.gf >= b.gf);
          expect(inOrder, isTrue, reason: 'rows ${i - 1}, $i of ${league.id}');
        }
      }
      expect(played, w.fixtures.length);
    });
  });

  group('tie-breaks', () {
    test('points decide before goal difference', () {
      // Club 1: 3 pts, gd -4. Club 2: 1 pt, gd 0.
      final w = _world(
        {4: 'A', 3: 'B', 2: 'C', 1: 'D'},
        [_f(1, 1, 3, (1, 0)), _f(2, 4, 1, (5, 0)), _f(3, 2, 3, (0, 0))],
      );
      expect(_order(w), [4, 1, 2, 3]);
    });

    test('equal points: goal difference decides', () {
      // Clubs 1 and 2 on 3 pts; club 2 gd +3, club 1 gd +1.
      final w = _world(
        {1: 'A', 2: 'B', 3: 'C', 4: 'D'},
        [_f(1, 1, 3, (1, 0)), _f(2, 2, 4, (3, 0))],
      );
      expect(_order(w), [2, 1, 3, 4]);
    });

    test('equal points and gd: goals for decides', () {
      // Clubs 1 and 2 on 3 pts, gd +1; club 2 scored 3, club 1 scored 1.
      // Clubs 3 and 4 on 0 pts, gd -1; club 4 scored 2, club 3 scored 0.
      final w = _world(
        {1: 'A', 2: 'B', 3: 'C', 4: 'D'},
        [_f(1, 1, 3, (1, 0)), _f(2, 2, 4, (3, 2))],
      );
      expect(_order(w), [2, 1, 4, 3]);
    });

    test('equal points, gd and gf: club name ascending decides', () {
      final w = _world({1: 'Zeta', 2: 'Alpha'}, [_f(1, 1, 2, (1, 1))]);
      expect(_order(w), [2, 1]);
    });

    test('identical records and names: club id ascending decides', () {
      final w = _world({2: 'Same', 1: 'Same'}, []);
      expect(_order(w), [1, 2]);
    });
  });
}
