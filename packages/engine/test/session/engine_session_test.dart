import 'dart:convert';
import 'dart:typed_data';

import 'package:engine/engine.dart';
import 'package:test/test.dart';

NewGameSpec _spec({int seed = 1, ClubId? startClubId}) => NewGameSpec(
  seed: seed,
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

String _json(EngineSession s) => jsonEncode(worldToJson(s.world));

void main() {
  late ClubId club;

  setUpAll(() {
    club = _firstTrTier1Club();
  });

  group('advanceUntil with a club', () {
    test('stops on the morning of each user match day', () {
      final s = EngineSession.newGame(_spec(startClubId: club));
      final w = s.world;
      final start = w.date;
      final target = w.calendar.seasonStart.addDays(30);
      final firstFixture =
          w.fixtures[w.fixturesOfClub(club, w.seasonYear).first]!;
      expect(firstFixture.date.isBefore(target), isTrue);

      final summaries = s.advanceUntil(target);

      final first = s.nextUserMatchDate();
      expect(first, firstFixture.date);
      expect(w.date, first);
      expect(firstFixture.result, isNull);
      expect(summaries.length, first!.dayIndex - start.dayIndex);
      for (final d in summaries) {
        expect(d.date.isBefore(first), isTrue);
      }

      // Match day itself must be advanced explicitly.
      final matchDay = s.advanceDay();
      expect(matchDay.date, first);
      expect(matchDay.playedFixtures, contains(firstFixture.id));
      expect(firstFixture.result, isNotNull);

      final second = s.nextUserMatchDate();
      expect(second, isNotNull);
      expect(second!.isAfter(first), isTrue);
      expect(second.isBefore(target), isTrue);

      s.advanceUntil(target);
      expect(w.date, second);
      expect(
        w.fixtures[w.fixturesOfClub(club, w.seasonYear)[1]]!.result,
        isNull,
      );
    });

    test('applies commands on the first day only', () {
      final s = EngineSession.newGame(_spec(startClubId: club));
      final w = s.world;
      final auto = autoLineup(w, club);
      final custom = Lineup(
        formation: auto.formation,
        starters: [...auto.starters]..[10] = auto.bench[1],
        bench: [...auto.bench]..[1] = auto.starters[10],
      );
      expect(validateLineup(w, club, custom), isEmpty);

      s.advanceUntil(
        w.calendar.seasonStart.addDays(30),
        commands: [SetLineup(clubId: club, lineup: custom)],
      );
      expect(w.clubs[club]!.lineup!.starters, custom.starters);
    });
  });

  group('unemployed', () {
    test('nextUserMatchDate is null and advanceUntil runs to the target', () {
      final s = EngineSession.newGame(_spec());
      final start = s.world.date;
      final target = s.world.calendar.seasonStart.addDays(30);
      expect(s.nextUserMatchDate(), isNull);

      final summaries = s.advanceUntil(target);
      expect(s.world.date, target);
      expect(summaries.length, target.dayIndex - start.dayIndex);
      expect(summaries.first.date, start);
      expect(summaries.last.date, target.addDays(-1));
    });

    test('advanceUntil stops right after the day with SeasonEnded', () {
      final s = EngineSession.newGame(_spec());
      final end = s.world.calendar.seasonEnd;
      s.advanceUntil(end.addDays(-3));
      expect(s.world.date, end.addDays(-3));

      final summaries = s.advanceUntil(end.addDays(5));
      expect(summaries.length, 4);
      expect(summaries.last.date, end);
      expect(summaries.last.events.whereType<SeasonEnded>(), hasLength(1));
      expect(s.world.date, end.addDays(1));
      expect(s.world.seasonYear, 2027);
    });
  });

  group('save / fromBytes', () {
    test('restored session simulates identically to the original', () {
      final a = EngineSession.newGame(_spec(startClubId: club));
      a.advanceUntil(a.world.calendar.seasonStart.addDays(30));
      a.advanceDay();

      final bytes = a.save();
      final b = EngineSession.fromBytes(bytes);
      expect(_json(b), _json(a));

      for (var i = 0; i < 2; i++) {
        a.advanceDay();
        b.advanceDay();
      }
      expect(_json(b), _json(a));
      expect(b.save(), a.save());
    });

    test('garbage bytes throw SaveError', () {
      expect(
        () => EngineSession.fromBytes(Uint8List.fromList([1, 2, 3, 4])),
        throwsA(isA<SaveError>()),
      );
    });
  });

  group('inbox', () {
    test('is newest first and markRead flips the flag', () {
      final s = EngineSession.newGame(_spec(startClubId: club));
      s.advanceUntil(s.world.calendar.seasonStart.addDays(30));
      s.advanceDay();
      final stored = s.world.inbox;
      expect(stored.length, greaterThanOrEqualTo(2));
      expect(stored.first.event, isA<NewSeasonStarted>());
      expect(stored.map((m) => m.event), contains(isA<MatchPlayed>()));

      final all = s.inbox();
      expect(all, stored.reversed.toList());
      expect(all.first, same(stored.last));
      expect(s.inbox(unreadOnly: true), all);

      s.markRead(all.first);
      expect(stored.last.read, isTrue);
      expect(s.inbox(unreadOnly: true), stored.reversed.skip(1).toList());
      expect(s.inbox(), all);
    });

    test('markRead survives the daily trim of the stored list', () {
      final s = EngineSession.newGame(_spec(startClubId: club));
      final w = s.world;
      final newest = s.inbox().first;
      w.inbox.insertAll(0, [
        for (var i = 0; i < inboxLimit; i++)
          InboxMessage(
            id: 1000 + i,
            date: w.date,
            event: SeasonEnded(date: w.date, seasonYear: i),
          ),
      ]);
      s.advanceDay(); // trims the oldest messages from the front
      expect(w.inbox, hasLength(inboxLimit));
      expect(w.inbox, contains(same(newest)));

      s.markRead(newest);
      expect(newest.read, isTrue);
      expect(s.inbox(unreadOnly: true), isNot(contains(same(newest))));
    });

    test('markReadById flips that message only; an unknown id is a no-op', () {
      final s = EngineSession.newGame(_spec(startClubId: club));
      s.advanceUntil(s.world.calendar.seasonStart.addDays(30));
      s.advanceDay();
      final all = s.inbox();
      expect(all.length, greaterThanOrEqualTo(2));
      final target = all[1];

      s.markReadById(target.id);
      expect(target.read, isTrue);
      expect(all.where((m) => m.read), [target]);

      s.markReadById(999999);
      expect(all.where((m) => m.read), [target]);
    });
  });

  group('queries', () {
    test('table, clubFixtures, squad and youth are consistent', () {
      final s = EngineSession.newGame(_spec(startClubId: club));
      final w = s.world;
      final leagueId = w.clubs[club]!.leagueId;
      final n = w.leagues[leagueId]!.clubIds.length;

      final table = s.table(leagueId);
      expect(table.length, n);
      expect(
        table.map((r) => r.clubId).toSet(),
        w.leagues[leagueId]!.clubIds.toSet(),
      );
      expect(table.every((r) => r.played == 0), isTrue);

      final fixtures = s.clubFixtures(club);
      expect(fixtures.length, 2 * (n - 1));
      for (var i = 1; i < fixtures.length; i++) {
        expect(fixtures[i - 1].date.isAfter(fixtures[i].date), isFalse);
      }
      expect(
        fixtures.every((f) => f.homeId == club || f.awayId == club),
        isTrue,
      );

      final squad = s.squad(club);
      expect(squad.length, inInclusiveRange(22, 28));
      expect(
        squad.every((p) => !p.isYouth && p.contract!.clubId == club),
        isTrue,
      );
      final youth = s.youth(club);
      expect(youth, isNotEmpty);
      expect(
        youth.every((p) => p.isYouth && p.contract!.clubId == club),
        isTrue,
      );

      expect(s.checkInvariants(), isEmpty);
    });
  });

  group('user match', () {
    /// A session advanced to the morning of the user's first match day.
    EngineSession atMatchDay({int seed = 1}) {
      final s = EngineSession.newGame(_spec(seed: seed, startClubId: club));
      s.advanceUntil(s.world.calendar.seasonStart.addDays(60));
      expect(s.nextUserMatchDate(), s.world.date);
      return s;
    }

    Fixture userFixture(EngineSession s) => s.world
        .fixturesOn(s.world.date)
        .map((id) => s.world.fixtures[id]!)
        .firstWhere((f) => f.homeId == club || f.awayId == club);

    String resultJson(Fixture f) => jsonEncode(matchResultToJson(f.result!));

    test('startUserMatch needs a user match day and no match in progress', () {
      final s = EngineSession.newGame(_spec(startClubId: club));
      expect(s.nextUserMatchDate(), isNot(s.world.date));
      expect(s.startUserMatch, throwsStateError);
      expect(s.finishUserMatch, throwsStateError);
      expect(s.userMatchInProgress, isFalse);

      final unemployed = EngineSession.newGame(_spec());
      expect(unemployed.startUserMatch, throwsStateError);

      final m = atMatchDay();
      m.startUserMatch();
      expect(m.userMatchInProgress, isTrue);
      expect(m.startUserMatch, throwsStateError);
      expect(m.advanceDay, throwsStateError);
      expect(() => m.advanceUntil(m.world.date.addDays(3)), throwsStateError);
      m.finishUserMatch();
      expect(m.userMatchInProgress, isFalse);
      expect(m.finishUserMatch, throwsStateError);
      expect(m.world.date, isNot(m.nextUserMatchDate()));
    });

    test('with the AI on, start + finish equals advanceDay (5 seeds)', () {
      for (var seed = 1; seed <= 5; seed++) {
        final a = atMatchDay(seed: seed);
        final b = atMatchDay(seed: seed);
        expect(_json(b), _json(a));

        final da = a.advanceDay();
        final session = b.startUserMatch(userManaged: false);
        expect(session.finished, isFalse);
        final db = b.finishUserMatch();

        expect(_json(b), _json(a), reason: 'seed $seed');
        expect(db.date, da.date);
        expect(db.playedFixtures, da.playedFixtures);
        expect(
          db.events.map((e) => e.runtimeType).toList(),
          da.events.map((e) => e.runtimeType).toList(),
        );
        expect(
          db.events.whereType<MatchPlayed>().map((e) => e.fixtureId),
          da.events.whereType<MatchPlayed>().map((e) => e.fixtureId),
        );
      }
    });

    test('user-managed: only the user side\'s AI decisions differ', () {
      final a = atMatchDay();
      final b = atMatchDay();
      final fa = userFixture(a);
      final fb = userFixture(b);
      expect(fb.id, fa.id);

      a.advanceDay();
      final session = b.startUserMatch();
      expect(session.state.side(club).userManaged, isTrue);
      final db = b.finishUserMatch();

      bool aiDecision(MatchEvent e) =>
          e.clubId == club && (e is Substitution || e is TacticChange);
      expect(fb.result!.events.where(aiDecision), isEmpty);
      final aDecided = fa.result!.events.where(aiDecision).isNotEmpty;
      expect(resultJson(fb) == resultJson(fa), !aDecided);
      // Every other fixture of the day is untouched by the user's choice.
      for (final id in db.playedFixtures) {
        if (id == fb.id) continue;
        expect(
          jsonEncode(matchResultToJson(b.world.fixtures[id]!.result!)),
          jsonEncode(matchResultToJson(a.world.fixtures[id]!.result!)),
        );
      }
    });

    test('a substitution changes the result; the day still completes', () {
      final a = atMatchDay();
      final b = atMatchDay();
      final fa = userFixture(a);
      final fb = userFixture(b);
      final da = a.advanceDay();

      final session = b.startUserMatch(userManaged: false);
      session.runUntil(minute: 50, stopOnEvent: false);
      final side = session.state.side(club);
      session.apply(
        Substitute(club, outId: side.playing.last, inId: side.bench.first),
      );
      final db = b.finishUserMatch();

      expect(resultJson(fb), isNot(resultJson(fa)));
      expect(fb.result!.events.whereType<Substitution>(), isNotEmpty);
      expect(db.playedFixtures, da.playedFixtures);
      expect(b.world.date, a.world.date);
      expect(b.checkInvariants(), isEmpty);
      expect(_json(b), isNot(_json(a)));
    });

    test('save during a match holds the started day without the match', () {
      final s = atMatchDay();
      final before = s.save();
      s.startUserMatch();
      final during = s.save();
      expect(during, isNot(before));

      // The same bytes as the day's start on a twin world.
      final twin = EngineSession.fromBytes(before).world;
      DayRunner().startOfDay(twin, const []);
      expect(during, const JsonGzipSaveCodec().encode(twin));

      final restored = EngineSession.fromBytes(during);
      expect(restored.nextUserMatchDate(), restored.world.date);
      expect(userFixture(restored).result, isNull);
      expect(restored.userMatchInProgress, isFalse);
      s.finishUserMatch();
    });
  });

  group('isolation', () {
    test('two sessions do not interfere', () {
      final a = EngineSession.newGame(_spec(seed: 1));
      final b = EngineSession.newGame(_spec(seed: 2));
      final bBefore = _json(b);
      final aBefore = _json(a);

      a.advanceUntil(a.world.date.addDays(10));

      expect(_json(a), isNot(aBefore));
      expect(_json(b), bBefore);
    });
  });
}
