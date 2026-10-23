import 'package:cm_app/engine/engine_gateway.dart';
import 'package:cm_app/engine/snapshot_builder.dart';
import 'package:cm_app/engine/snapshots.dart';
import 'package:engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

NewGameSpec _spec(ClubId? startClubId) => NewGameSpec(
  seed: 1,
  size: WorldSize.small,
  managerFirstName: 'Test',
  managerLastName: 'Manager',
  managerCountryCode: 'TR',
  startClubId: startClubId,
);

void main() {
  late ClubId club;
  late EngineSession s;
  late SnapshotBuilder b;

  setUpAll(() {
    final w = createNewGame(_spec(null));
    final tr = w.countries.values.firstWhere((c) => c.code == 'TR');
    club = w.leagues[tr.tiers.first]!.clubIds.first;
  });

  setUp(() {
    s = EngineSession.newGame(_spec(club));
    b = SnapshotBuilder(s);
  });

  test('squad sorts by position group, then CA descending, then id', () {
    final rows = b.squad(club);
    final expected = s.squad(club)
      ..sort((x, y) {
        var c = x.mainPosition.group.index.compareTo(
          y.mainPosition.group.index,
        );
        if (c != 0) return c;
        c = y.ca.compareTo(x.ca);
        return c != 0 ? c : x.id.compareTo(y.id);
      });
    expect(rows.map((r) => r.id), expected.map((p) => p.id));
  });

  test('MatchPlayed labels carry both names and the score', () {
    s.advanceUntil(s.world.date.addDays(90));
    final summary = s.advanceDay();
    final fixtureId = summary.playedFixtures.singleWhere((id) {
      final f = s.world.fixtures[id]!;
      return f.homeId == club || f.awayId == club;
    });
    final f = s.world.fixtures[fixtureId]!;

    final item = b.inbox().first;
    expect(item.event, isA<MatchPlayed>());
    expect(item.labels.homeName, s.world.clubs[f.homeId]!.name);
    expect(item.labels.awayName, s.world.clubs[f.awayId]!.name);
    expect(item.labels.homeGoals, f.result!.homeGoals);
    expect(item.labels.awayGoals, f.result!.awayGoals);
  });

  test('LeagueChampion labels carry the league country and tier', () {
    final leagueId = s.world.clubs[club]!.leagueId;
    s.world.inbox.add(
      InboxMessage(
        id: 1 << 30,
        date: s.world.date,
        event: LeagueChampion(
          date: s.world.date,
          leagueId: leagueId,
          clubId: club,
        ),
      ),
    );

    final item = b.inbox().first;
    expect(item.event, isA<LeagueChampion>());
    expect(item.labels.leagueCountryCode, 'TR');
    expect(item.labels.leagueTier, 1);
    expect(item.labels.leagueName, s.world.leagues[leagueId]!.name);
  });

  group('injury, sending-off and suspension labels', () {
    late PlayerId player;
    late Fixture f;

    setUp(() {
      player = s.world.squadOf(club).first;
      f = s
          .world
          .fixtures[s.world.fixturesOfClub(club, s.world.seasonYear).first]!;
    });

    InboxLabels labelsOf(GameEvent e) {
      s.world.inbox.add(
        InboxMessage(id: 1 << 30, date: s.world.date, event: e),
      );
      final item = b.inbox().first;
      expect(item.event.runtimeType, e.runtimeType);
      return item.labels;
    }

    String name(PlayerId id) {
      final p = s.world.players[id]!;
      return '${p.firstName} ${p.lastName}';
    }

    test('PlayerInjured', () {
      final l = labelsOf(
        PlayerInjured(
          date: s.world.date,
          playerId: player,
          clubId: club,
          days: 10,
        ),
      );
      expect(l.clubName, s.world.clubs[club]!.name);
      expect(l.playerNames, [name(player)]);
    });

    test('PlayerSentOff carries the fixture names', () {
      final l = labelsOf(
        PlayerSentOff(
          date: s.world.date,
          playerId: player,
          clubId: club,
          fixtureId: f.id,
        ),
      );
      expect(l.clubName, s.world.clubs[club]!.name);
      expect(l.playerNames, [name(player)]);
      expect(l.homeName, s.world.clubs[f.homeId]!.name);
      expect(l.awayName, s.world.clubs[f.awayId]!.name);
    });

    test('PlayerSuspended of a player who has left the world', () {
      final l = labelsOf(
        PlayerSuspended(
          date: s.world.date,
          playerId: 1 << 30,
          clubId: club,
          matches: 2,
        ),
      );
      expect(l.clubName, s.world.clubs[club]!.name);
      expect(l.playerNames, isEmpty);
    });
  });

  test('leaguePosition equals the table rank after some matches', () {
    for (var i = 0; i < 5; i++) {
      s.advanceUntil(s.world.date.addDays(90));
      s.advanceDay();
    }
    final leagueId = s.world.clubs[club]!.leagueId;
    final rank = s.table(leagueId).indexWhere((r) => r.clubId == club) + 1;
    expect(b.home().leaguePosition, rank);
    expect(b.table(leagueId).singleWhere((r) => r.isUser).rank, rank);
  });

  test('lineup returns a stored lineup unchanged with its errors', () {
    final auto = autoLineup(s.world, club);
    final starters = [...auto.starters]..[10] = -1;
    s.world.clubs[club]!.lineup = Lineup(
      formation: auto.formation,
      starters: starters,
      bench: auto.bench,
    );
    final view = b.lineup(club);
    expect(view.errors, contains(LineupError.notInClub));
    expect(view.starters, starters);
  });

  test('lineup returns a valid stored lineup, not the auto one', () {
    final auto = autoLineup(s.world, club);
    final stored = Lineup(
      formation: auto.formation,
      starters: [...auto.starters]..[10] = auto.bench[1],
      bench: [...auto.bench]..[1] = auto.starters[10],
    );
    s.world.clubs[club]!.lineup = stored;
    final view = b.lineup(club);
    expect(view.errors, isEmpty);
    expect(view.starters, stored.starters);
    expect(view.starters, isNot(auto.starters));
    expect(view.bench, stored.bench);
  });

  test('lineup of an unknown club is a GatewayError(engine)', () {
    expect(
      () => b.lineup(-1),
      throwsA(
        isA<GatewayError>().having(
          (e) => e.kind,
          'kind',
          GatewayErrorKind.engine,
        ),
      ),
    );
  });
}
