import 'package:cm_app/engine/engine_gateway.dart';
import 'package:cm_app/engine/snapshot_builder.dart';
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
