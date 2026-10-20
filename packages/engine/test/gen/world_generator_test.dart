import 'dart:convert';

import 'package:engine/engine.dart';
import 'package:test/test.dart';

const _year = 2026;
final _startDate = buildSeasonCalendar(_year).seasonStart.addDays(-14);

World _small({int seed = 1}) =>
    generateWorld(seed: seed, size: WorldSize.small, startDate: _startDate);

void main() {
  final data = CountryData.load();
  final small = _small();

  test('WorldSize country counts', () {
    expect(WorldSize.small.countryCount, 4);
    expect(WorldSize.medium.countryCount, 8);
    expect(WorldSize.large.countryCount, 16);
  });

  test('small world has the first 4 countries with the template clubs', () {
    expect(small.countries, hasLength(4));
    expect(small.date, _startDate);
    expect(small.seasonYear, _year);
    expect(small.calendar.seasonYear, _year);
    final templates = data.countries.take(4).toList();
    final codes = small.countries.values.map((c) => c.code).toList();
    expect(codes, templates.map((t) => t.code).toList());
    var expectedClubs = 0;
    for (final country in small.countries.values) {
      final t = templates.firstWhere((t) => t.code == country.code);
      expect(country.tiers, hasLength(t.tiers.length));
      for (var i = 0; i < t.tiers.length; i++) {
        final league = small.leagues[country.tiers[i]]!;
        expect(league.name, '${t.code}_${t.tiers[i].nameKey}');
        expect(league.tier, i + 1);
        expect(league.countryId, country.id);
        expect(league.clubIds, hasLength(t.tiers[i].clubs));
        expect(league.promotedCount, t.tiers[i].promoted);
        expect(league.relegatedCount, t.tiers[i].relegated);
        expect(league.reputation, (t.reputation - 15 * i).clamp(1, 100));
        for (final id in league.clubIds) {
          expect(small.clubs[id]!.leagueId, league.id);
          expect(small.clubs[id]!.countryId, country.id);
        }
        expectedClubs += t.tiers[i].clubs;
      }
    }
    expect(small.clubs, hasLength(expectedClubs));
    expect(
      small.clubs.values.map((c) => c.name).toSet(),
      hasLength(expectedClubs),
    );
  });

  test(
    'every club has a 22..26 senior squad with ranked statuses and 6 youth',
    () {
      const quota = {
        Position.gk: 3,
        Position.dc: 4,
        Position.dl: 2,
        Position.dr: 2,
        Position.dm: 2,
        Position.mc: 4,
        Position.ml: 1,
        Position.mr: 1,
        Position.amc: 2,
        Position.st: 3,
      };
      for (final club in small.clubs.values) {
        final squad = small
            .squadOf(club.id)
            .map((id) => small.players[id]!)
            .toList();
        expect(squad.length, inInclusiveRange(22, 26), reason: club.name);
        expect(squad.where((p) => p.mainPosition == Position.gk), hasLength(3));
        for (final p in squad) {
          expect(p.isYouth, isFalse);
          expect(p.contract!.clubId, club.id);
          expect(quota.containsKey(p.mainPosition), isTrue);
          expect(p.ageAt(_startDate), inInclusiveRange(18, 34));
        }
        final byCa = List.of(squad)..sort((a, b) => b.ca.compareTo(a.ca));
        final statuses = byCa.map((p) => p.contract!.status).toList();
        expect(statuses.sublist(0, 4), everyElement(PlayerStatus.keyPlayer));
        expect(statuses.sublist(4, 14), everyElement(PlayerStatus.firstTeam));
        expect(statuses.sublist(14, 20), everyElement(PlayerStatus.rotation));
        expect(statuses.sublist(20), everyElement(PlayerStatus.backup));
        // Higher CA never ranks below lower CA; equal CA ranks by id.
        for (final a in squad) {
          for (final b in squad) {
            if (a.ca > b.ca || a.ca == b.ca && a.id < b.id) {
              expect(
                a.contract!.status.index,
                lessThanOrEqualTo(b.contract!.status.index),
                reason: '${a.id} (ca ${a.ca}) vs ${b.id} (ca ${b.ca})',
              );
            }
          }
        }

        final youth = small.youthOf(club.id).map((id) => small.players[id]!);
        expect(youth, hasLength(6));
        for (final p in youth) {
          expect(p.isYouth, isTrue);
          expect(p.contract!.status, PlayerStatus.youth);
          expect(p.ageAt(_startDate), inInclusiveRange(15, 17));
          expect(p.ca, inInclusiveRange(10, 130));
        }
      }
    },
  );

  test('squad sizes vary and most players are domestic', () {
    final sizes = small.clubs.keys
        .map((id) => small.squadOf(id).length)
        .toSet();
    expect(sizes.length, greaterThan(1));
    final players = small.players.values.toList();
    final domestic = players.where(
      (p) => small.clubs[p.contract!.clubId]!.countryId == p.nationality,
    );
    final share = domestic.length / players.length;
    expect(share, inInclusiveRange(0.78, 0.92));
    for (final p in players) {
      expect(small.countries.containsKey(p.nationality), isTrue);
    }
  });

  test('every league is scheduled on its matchdays', () {
    for (final league in small.leagues.values) {
      final n = league.clubIds.length;
      final fixtures = small.fixtures.values
          .where((f) => f.leagueId == league.id)
          .toList();
      final rounds = fixtures.map((f) => f.round).toSet();
      expect(rounds.length, anyOf(2 * (n - 1), 2 * n));
      expect(rounds, {for (var r = 1; r <= rounds.length; r++) r});
      final dates = leagueMatchdays(small.calendar, rounds.length);
      for (final f in fixtures) {
        expect(f.date, dates[f.round - 1]);
        expect(f.seasonYear, _year);
        expect(f.result, isNull);
        expect(league.clubIds, containsAll([f.homeId, f.awayId]));
      }
      for (final c in league.clubIds) {
        final mine = small.fixturesOfClub(c, _year);
        expect(mine, hasLength(2 * (n - 1)));
        final home = mine.where((id) => small.fixtures[id]!.homeId == c);
        expect(home, hasLength(n - 1));
      }
    }
    expect(small.fixtures.values.every((f) => f.result == null), isTrue);
  });

  test('every club has an AI manager near its reputation', () {
    expect(small.managers, hasLength(small.clubs.length));
    expect(small.userManagerId, 0);
    for (final club in small.clubs.values) {
      final m = small.managers[club.managerId]!;
      expect(m.clubId, club.id);
      expect(m.isUser, isFalse);
      expect(m.nationality, club.countryId);
      expect(
        m.reputation,
        inInclusiveRange(club.reputation - 10, club.reputation + 10),
      );
      expect(m.reputation, inInclusiveRange(1, 100));
      expect(ageAt(m.birth, _startDate), inInclusiveRange(35, 60));
      expect(m.preferredFormation, Formation.f442);
    }
  });

  test('same seed gives identical world JSON', () {
    final a = jsonEncode(worldToJson(_small(seed: 7)));
    final b = jsonEncode(worldToJson(_small(seed: 7)));
    expect(a, b);
    expect(a, isNot(jsonEncode(worldToJson(_small(seed: 8)))));
  });

  test('adding countries does not perturb TR (fork isolation)', () {
    final medium = generateWorld(
      seed: 1,
      size: WorldSize.medium,
      startDate: _startDate,
    );
    expect(medium.countries, hasLength(8));
    final trSmall = small.countries.values.firstWhere((c) => c.code == 'TR');
    final trMedium = medium.countries.values.firstWhere((c) => c.code == 'TR');
    final clubSmall = small.clubs[small.leagues[trSmall.tiers[0]]!.clubIds[0]]!;
    final clubMedium =
        medium.clubs[medium.leagues[trMedium.tiers[0]]!.clubIds[0]]!;
    expect(
      jsonEncode(clubToJson(clubSmall)),
      jsonEncode(clubToJson(clubMedium)),
    );
    final pSmall = small.players[small.squadOf(clubSmall.id)[0]]!;
    final pMedium = medium.players[medium.squadOf(clubMedium.id)[0]]!;
    // A foreign player's nationality legitimately depends on which countries
    // exist, so it is compared only when the player is Turkish in both.
    final js = playerToJson(pSmall);
    final jm = playerToJson(pMedium);
    if (pSmall.nationality != trSmall.id ||
        pMedium.nationality != trMedium.id) {
      js.remove('nationality');
      jm.remove('nationality');
    }
    expect(jsonEncode(js), jsonEncode(jm));
  });

  group('createNewGame', () {
    final spec = NewGameSpec(
      seed: 3,
      size: WorldSize.small,
      managerFirstName: 'Hakan',
      managerLastName: 'Artuç',
      managerCountryCode: 'TR',
      startClubId: null,
    );

    test('unemployed start', () {
      final w = createNewGame(spec);
      final user = w.managers[w.userManagerId]!;
      expect(user.isUser, isTrue);
      expect(user.firstName, 'Hakan');
      expect(user.lastName, 'Artuç');
      expect(user.reputation, 40);
      expect(user.clubId, isNull);
      expect(w.userClub, isNull);
      expect(
        user.nationality,
        w.countries.values.firstWhere((c) => c.code == 'TR').id,
      );
      expect(ageAt(user.birth, w.date), 40);
      expect(w.date, buildSeasonCalendar(2026).seasonStart.addDays(-14));
      expect(w.seasonYear, 2026);
      expect(w.managers, hasLength(w.clubs.length + 1));
      expect(w.inbox, hasLength(1));
      final e = w.inbox.single.event;
      expect(e, isA<NewSeasonStarted>());
      expect((e as NewSeasonStarted).seasonYear, 2026);
      expect(e.date, w.date);
      expect(w.inbox.single.read, isFalse);
    });

    test('starting at a club replaces its AI manager', () {
      final probe = createNewGame(spec);
      final clubId = probe.clubs.keys.first;
      final aiId = probe.clubs[clubId]!.managerId!;
      final w = createNewGame(
        NewGameSpec(
          seed: 3,
          size: WorldSize.small,
          managerFirstName: 'A',
          managerLastName: 'B',
          managerCountryCode: 'ENG',
          startClubId: clubId,
        ),
      );
      expect(w.userClub!.id, clubId);
      expect(w.clubs[clubId]!.managerId, w.userManagerId);
      expect(w.managers[aiId]!.clubId, isNull);
      expect(w.managers[w.userManagerId]!.clubId, clubId);
    });

    test('other season year moves the start date', () {
      final w = createNewGame(spec, startSeasonYear: 2027);
      expect(w.seasonYear, 2027);
      expect(w.date, buildSeasonCalendar(2027).seasonStart.addDays(-14));
      expect((w.inbox.single.event as NewSeasonStarted).seasonYear, 2027);
    });

    test('rejects a country outside the world or an unknown club', () {
      expect(
        () => createNewGame(
          NewGameSpec(
            seed: 3,
            size: WorldSize.small,
            managerFirstName: 'A',
            managerLastName: 'B',
            managerCountryCode: 'BR',
            startClubId: null,
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => createNewGame(
          NewGameSpec(
            seed: 3,
            size: WorldSize.small,
            managerFirstName: 'A',
            managerLastName: 'B',
            managerCountryCode: 'TR',
            startClubId: 999999,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('is deterministic', () {
      expect(
        jsonEncode(worldToJson(createNewGame(spec))),
        jsonEncode(worldToJson(createNewGame(spec))),
      );
    });
  });
}
