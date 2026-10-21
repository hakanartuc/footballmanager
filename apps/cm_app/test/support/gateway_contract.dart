import 'dart:typed_data';

import 'package:cm_app/engine/engine_gateway.dart';
import 'package:cm_app/engine/snapshots.dart';
import 'package:engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

NewGameSpec _spec({ClubId? startClubId}) => NewGameSpec(
  seed: 1,
  size: WorldSize.small,
  managerFirstName: 'Test',
  managerLastName: 'Manager',
  managerCountryCode: 'TR',
  startClubId: startClubId,
);

/// First club of Turkey's top division in the seed-1 small world.
ClubId _firstTrTier1Club() {
  final w = createNewGame(_spec());
  final tr = w.countries.values.firstWhere((c) => c.code == 'TR');
  return w.leagues[tr.tiers.first]!.clubIds.first;
}

/// The [EngineGateway] contract: every gateway implementation must pass it.
/// [make] returns a fresh gateway with no game loaded.
void runGatewayContract(Future<EngineGateway> Function() make) {
  late ClubId club;
  late World reference;
  late EngineGateway g;

  setUpAll(() {
    club = _firstTrTier1Club();
    reference = createNewGame(_spec(startClubId: club));
  });

  setUp(() async {
    g = await make();
    addTearDown(g.dispose);
  });

  Future<void> newGame() => g.newGame(_spec(startClubId: club));

  test('throws GatewayError(noGame) before newGame or load', () async {
    await expectLater(
      g.home(),
      throwsA(
        isA<GatewayError>().having(
          (e) => e.kind,
          'kind',
          GatewayErrorKind.noGame,
        ),
      ),
    );
  });

  test('refs() counts match the world', () async {
    await newGame();
    final refs = await g.refs();
    expect(refs.countries, hasLength(reference.countries.length));
    expect(refs.leagues, hasLength(reference.leagues.length));
    expect(refs.clubs, hasLength(reference.clubs.length));
    final userClub = refs.clubs.singleWhere((c) => c.id == club);
    expect(userClub.name, reference.clubs[club]!.name);
    expect(userClub.leagueId, reference.clubs[club]!.leagueId);
    final league = refs.leagues.singleWhere((l) => l.id == userClub.leagueId);
    expect(league.countryCode, 'TR');
    expect(league.tier, 1);
    expect(league.clubIds, contains(club));
    final country = refs.countries.singleWhere((c) => c.code == 'TR');
    expect(country.leagueIds, contains(league.id));
  });

  test('home() on day 1', () async {
    await newGame();
    final home = await g.home();
    expect(home.date, reference.date);
    expect(home.seasonYear, reference.seasonYear);
    expect(home.clubId, club);
    expect(home.clubName, reference.clubs[club]!.name);
    expect(home.leagueId, reference.clubs[club]!.leagueId);
    expect(home.leaguePosition, isNotNull);
    expect(home.isMatchDay, isFalse);
    expect(home.unreadCount, 1);
    expect(home.managerName, 'Test Manager');
    expect(home.seniorCount, reference.squadOf(club).length);
    expect(home.injuredCount, 0);
    expect(home.suspendedCount, 0);

    final first = reference
        .fixtures[reference.fixturesOfClub(club, reference.seasonYear).first]!;
    final next = home.nextMatch!;
    expect(next.fixtureId, first.id);
    expect(next.date, first.date);
    expect(next.homeId, first.homeId);
    expect(next.awayId, first.awayId);
    expect(next.homeName, reference.clubs[first.homeId]!.name);
    expect(next.awayName, reference.clubs[first.awayId]!.name);
    expect(next.isHome, first.homeId == club);
  });

  test(
    'squad() returns the seniors sorted by position group then CA desc',
    () async {
      await newGame();
      final rows = await g.squad(club);
      expect(rows.map((r) => r.id).toSet(), reference.squadOf(club).toSet());
      expect(rows.every((r) => !r.isYouth), isTrue);
      for (var i = 1; i < rows.length; i++) {
        final a = rows[i - 1];
        final b = rows[i];
        final ga = a.position.group.index;
        final gb = b.position.group.index;
        expect(ga <= gb, isTrue, reason: 'group order at $i');
        if (ga == gb) expect(a.ca >= b.ca, isTrue, reason: 'ca order at $i');
      }
      final p = reference.players[rows.first.id]!;
      expect(rows.first.name, '${p.firstName} ${p.lastName}');
      expect(rows.first.age, p.ageAt(reference.date));
      expect(rows.first.status, p.contract!.status);

      final youth = await g.squad(club, youth: true);
      expect(youth.map((r) => r.id).toSet(), reference.youthOf(club).toSet());
      expect(youth.every((r) => r.isYouth), isTrue);
    },
  );

  test('player() returns the detail; unknown id is an engine error', () async {
    await newGame();
    final id = reference.squadOf(club).first;
    final p = reference.players[id]!;
    final d = await g.player(id);
    expect(d.id, id);
    expect(d.name, '${p.firstName} ${p.lastName}');
    expect(d.countryCode, reference.countries[p.nationality]!.code);
    expect(d.position, p.mainPosition);
    expect(d.familiarity, p.familiarity);
    expect(d.age, p.ageAt(reference.date));
    expect(d.heightCm, p.heightCm);
    expect(d.attrs, p.attrs.toList());
    expect(d.ca, p.ca);
    expect(d.pa, p.pa);
    expect(d.condition, p.state.condition);
    expect(d.wageWeekly, p.contract!.wageWeekly);
    expect(d.contractEnd, p.contract!.end);
    expect(d.status, p.contract!.status);
    expect(d.apps, 0);
    expect(d.goals, 0);
    expect(d.assists, 0);

    await expectLater(
      g.player(-1),
      throwsA(
        isA<GatewayError>().having(
          (e) => e.kind,
          'kind',
          GatewayErrorKind.engine,
        ),
      ),
    );
  });

  test(
    'lineup() without a stored lineup is the auto lineup, no errors',
    () async {
      await newGame();
      final auto = autoLineup(reference, club);
      final view = await g.lineup(club);
      expect(view.formation, auto.formation);
      expect(view.slots, formationSlots(auto.formation));
      expect(view.starters, auto.starters);
      expect(view.bench, auto.bench);
      expect(view.errors, isEmpty);

      await expectLater(
        g.lineup(-1),
        throwsA(
          isA<GatewayError>().having(
            (e) => e.kind,
            'kind',
            GatewayErrorKind.engine,
          ),
        ),
      );
    },
  );

  test('lineup(auto: true) ignores a stored lineup', () async {
    await newGame();
    final auto = autoLineup(reference, club);
    final swapped = [...auto.starters];
    swapped[1] = auto.starters[2];
    swapped[2] = auto.starters[1];
    await g.playToday([
      SetLineup(
        clubId: club,
        lineup: Lineup(
          formation: auto.formation,
          starters: swapped,
          bench: auto.bench,
        ),
      ),
    ]);
    expect((await g.lineup(club)).starters, swapped);
    final world = EngineSession.fromBytes(await g.save()).world;
    final view = await g.lineup(club, auto: true);
    expect(view.starters, autoLineup(world, club).starters);
    expect(view.starters, isNot(swapped));
    expect(view.errors, isEmpty);
  });

  test('after dispose() every call fails with GatewayError(noGame)', () async {
    await newGame();
    await g.dispose();
    await expectLater(
      g.home(),
      throwsA(
        isA<GatewayError>().having(
          (e) => e.kind,
          'kind',
          GatewayErrorKind.noGame,
        ),
      ),
    );
  });

  test('table() ranks 1..n with isUser on exactly one row', () async {
    await newGame();
    final leagueId = reference.clubs[club]!.leagueId;
    final rows = await g.table(leagueId);
    expect(rows, hasLength(reference.leagues[leagueId]!.clubIds.length));
    expect(rows.map((r) => r.rank), List.generate(rows.length, (i) => i + 1));
    expect(rows.where((r) => r.isUser).map((r) => r.clubId), [club]);
    expect(rows.first.clubName, reference.clubs[rows.first.clubId]!.name);
    expect(rows.every((r) => r.played == 0 && r.points == 0), isTrue);

    await expectLater(
      g.table(-1),
      throwsA(
        isA<GatewayError>().having(
          (e) => e.kind,
          'kind',
          GatewayErrorKind.engine,
        ),
      ),
    );
  });

  test('clubFixtures() is in date order with names and no results', () async {
    await newGame();
    final rows = await g.clubFixtures(club);
    expect(rows, isNotEmpty);
    expect(
      rows.map((r) => r.id),
      reference.fixturesOfClub(club, reference.seasonYear),
    );
    for (var i = 1; i < rows.length; i++) {
      expect(rows[i - 1].date.isAfter(rows[i].date), isFalse);
    }
    final f = reference.fixtures[rows.first.id]!;
    expect(rows.first.round, f.round);
    expect(rows.first.homeName, reference.clubs[f.homeId]!.name);
    expect(rows.first.awayName, reference.clubs[f.awayId]!.name);
    expect(rows.first.homeGoals, isNull);
    expect(rows.first.awayGoals, isNull);
    expect(rows.first.goals, isEmpty);
  });

  test('inbox() is newest first with labels; markRead flips read', () async {
    await newGame();
    final items = await g.inbox();
    expect(items, hasLength(1));
    final item = items.single;
    expect(item.event, isA<NewSeasonStarted>());
    expect(item.read, isFalse);
    expect(item.date, reference.date);
    expect(item.labels.clubName, isNull);
    expect(item.labels.leagueName, isNull);
    expect(item.labels.playerNames, isEmpty);

    await g.markRead(item.id);
    expect((await g.inbox()).single.read, isTrue);
    expect((await g.home()).unreadCount, 0);

    // Play the first match: the MatchPlayed message comes first.
    await g.advanceToNext();
    await g.playToday(const []);
    final after = await g.inbox();
    expect(after, hasLength(2));
    expect(after.first.event, isA<MatchPlayed>());
    expect(after.first.id, greaterThan(after.last.id));
    expect(after.first.labels.homeGoals, isNotNull);
    expect(after.first.labels.awayGoals, isNotNull);
    expect(after.first.labels.homeName, isNotEmpty);
    expect(after.first.labels.awayName, isNotEmpty);
  });

  test(
    'advanceToNext() stops with matchDay on the first fixture date',
    () async {
      await newGame();
      final first =
          reference.fixtures[reference
              .fixturesOfClub(club, reference.seasonYear)
              .first]!;
      final out = await g.advanceToNext();
      expect(out.reason, StopReason.matchDay);
      expect(out.date, first.date);
      expect(out.daysAdvanced, reference.date.daysUntil(first.date));
      expect(out.userMatch, isNull);
      expect(out.seasonEnded, isFalse);
      expect(out.newInboxCount, 0);
      expect((await g.home()).isMatchDay, isTrue);

      // Already on a match day: nothing advances.
      final again = await g.advanceToNext();
      expect(again.reason, StopReason.matchDay);
      expect(again.daysAdvanced, 0);
      expect(again.date, first.date);
    },
  );

  test('playToday([]) plays the user match', () async {
    await newGame();
    await g.advanceToNext();
    final matchDate = (await g.home()).date;
    final out = await g.playToday(const []);
    expect(out.reason, StopReason.played);
    expect(out.daysAdvanced, 1);
    expect(out.date, matchDate.addDays(1));
    expect(out.newInboxCount, 1);
    final m = out.userMatch!;
    expect(m.date, matchDate);
    expect(m.homeGoals, isNotNull);
    expect(m.awayGoals, isNotNull);
    expect(m.homeId == club || m.awayId == club, isTrue);
    expect(m.goals, hasLength(m.homeGoals! + m.awayGoals!));
    for (final goal in m.goals) {
      expect(goal.scorerName, isNotEmpty);
    }
    expect((await g.clubFixtures(club)).first.homeGoals, m.homeGoals);
  });

  test(
    'advanceToNext() reports seasonEnded at the end of the season',
    () async {
      await newGame();
      AdvanceOutcome out;
      var guard = 0;
      while (true) {
        out = await g.advanceToNext();
        if (out.reason == StopReason.seasonEnded) break;
        expect(out.reason, StopReason.matchDay, reason: 'stop ${out.date.iso}');
        await g.playToday(const []);
        expect(++guard < 80, isTrue, reason: 'season never ended');
      }
      expect(out.seasonEnded, isTrue);
      expect(out.newInboxCount, greaterThan(0));
      final events = (await g.inbox()).map((i) => i.event);
      expect(events, contains(isA<SeasonEnded>()));
      final next = await g.advanceToNext();
      expect(next.reason, StopReason.matchDay);
      expect((await g.home()).seasonYear, reference.seasonYear + 1);
    },
  );

  test('unemployed: no club and advanceToNext hits the limit', () async {
    await g.newGame(_spec());
    final home = await g.home();
    expect(home.clubId, isNull);
    expect(home.clubName, isNull);
    expect(home.leagueId, isNull);
    expect(home.leaguePosition, isNull);
    expect(home.nextMatch, isNull);
    expect(home.isMatchDay, isFalse);
    expect(home.seniorCount, 0);
    final out = await g.advanceToNext(maxDays: 10);
    expect(out.reason, StopReason.reachedLimit);
    expect(out.daysAdvanced, 10);
    expect(out.date, reference.date.addDays(10));
    final played = await g.playToday(const []);
    expect(played.reason, StopReason.played);
    expect(played.userMatch, isNull);
  });

  test(
    'save() round-trips through load(); load(garbage) is a save error',
    () async {
      await newGame();
      await g.advanceToNext();
      final date = (await g.home()).date;
      final bytes = await g.save();

      final g2 = await make();
      addTearDown(g2.dispose);
      await g2.load(bytes);
      expect((await g2.home()).date, date);
      expect((await g2.home()).clubId, club);

      await expectLater(
        g2.load(Uint8List.fromList([1, 2, 3])),
        throwsA(
          isA<GatewayError>().having(
            (e) => e.kind,
            'kind',
            GatewayErrorKind.save,
          ),
        ),
      );
    },
  );
}
