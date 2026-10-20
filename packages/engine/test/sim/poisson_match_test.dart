import 'package:engine/engine.dart';
import 'package:test/test.dart';

World _world() => createNewGame(
  NewGameSpec(
    seed: 1,
    size: WorldSize.small,
    managerFirstName: 'Test',
    managerLastName: 'Manager',
    managerCountryCode: 'TR',
    startClubId: null,
  ),
);

void main() {
  late World w;
  late Fixture fx;
  late Lineup home;
  late Lineup away;
  const sim = PoissonMatchSimulator();

  setUp(() {
    w = _world();
    fx = w.fixtures.values.first;
    home = autoLineup(w, fx.homeId);
    away = autoLineup(w, fx.awayId);
  });

  MatchContext ctx(int seed, {Lineup? h, Lineup? a}) => MatchContext(
    world: w,
    fixture: fx,
    home: h ?? home,
    away: a ?? away,
    rng: SeededRng(seed),
  );

  group('PoissonMatchSimulator', () {
    test('same context twice gives the same result', () {
      final a = matchResultToJson(sim.simulate(ctx(42)));
      final b = matchResultToJson(sim.simulate(ctx(42)));
      expect(a, equals(b));
    });

    test('matchSeed is the first draw of the match rng', () {
      expect(sim.simulate(ctx(42)).matchSeed, SeededRng(42).nextUint32());
    });

    test('goal counts match the goal list and scorers are starters', () {
      var goals = 0;
      for (var seed = 1; seed <= 50; seed++) {
        final r = sim.simulate(ctx(seed));
        expect(
          r.goals.where((g) => g.clubId == fx.homeId),
          hasLength(r.homeGoals),
        );
        expect(
          r.goals.where((g) => g.clubId == fx.awayId),
          hasLength(r.awayGoals),
        );
        for (final g in r.goals) {
          final starters = g.clubId == fx.homeId
              ? home.starters
              : away.starters;
          expect(starters, contains(g.scorerId));
        }
        goals += r.goals.length;
      }
      expect(goals, greaterThan(50));
    });

    test('minutes are ascending within 1..90', () {
      for (var seed = 1; seed <= 50; seed++) {
        final r = sim.simulate(ctx(seed));
        for (var i = 0; i < r.goals.length; i++) {
          expect(r.goals[i].minute, inInclusiveRange(1, 90));
          if (i > 0) {
            expect(
              r.goals[i].minute,
              greaterThanOrEqualTo(r.goals[i - 1].minute),
            );
          }
        }
      }
    });

    test('a team with no starters scores nothing', () {
      final empty = Lineup(formation: Formation.f442, starters: [], bench: []);
      for (var seed = 1; seed <= 20; seed++) {
        final r = sim.simulate(ctx(seed, h: empty));
        expect(r.homeGoals, 0);
        expect(r.goals.where((g) => g.clubId == fx.homeId), isEmpty);
        expect(
          r.goals.where((g) => g.clubId == fx.awayId),
          hasLength(r.awayGoals),
        );
      }
    });
  });

  group('lineupStrength', () {
    test('matches the hand-computed mean over starters', () {
      final slots = formationSlots(home.formation);
      for (var i = 0; i < 11; i++) {
        w.players[home.starters[i]]!
          ..ca = 100
          ..familiarity = {slots[i]: 20}
          ..state.condition = 100;
      }
      expect(lineupStrength(w, home), closeTo(100, 1e-9));

      // One starter: 100 × 10/20 × (0.75 + 0.25 × 0.5) = 43.75.
      w.players[home.starters[3]]!
        ..familiarity = {slots[3]: 10}
        ..state.condition = 50;
      expect(lineupStrength(w, home), closeTo((10 * 100 + 43.75) / 11, 1e-9));
    });

    test('an unfamiliar slot counts as familiarity 1', () {
      final slots = formationSlots(home.formation);
      for (var i = 0; i < 11; i++) {
        w.players[home.starters[i]]!
          ..ca = 100
          ..familiarity = {slots[i]: 20}
          ..state.condition = 100;
      }
      w.players[home.starters[5]]!.familiarity = {};
      expect(lineupStrength(w, home), closeTo((10 * 100 + 5) / 11, 1e-9));
    });

    test('short-handed lineups are scaled by starters / 11', () {
      final slots = formationSlots(home.formation);
      for (var i = 0; i < 11; i++) {
        w.players[home.starters[i]]!
          ..ca = 100
          ..familiarity = {slots[i]: 20}
          ..state.condition = 100;
      }
      final short = Lineup(
        formation: home.formation,
        starters: home.starters.take(5).toList(),
        bench: [],
      );
      expect(lineupStrength(w, short), closeTo(100 * 5 / 11, 1e-9));
      final empty = Lineup(formation: home.formation, starters: [], bench: []);
      expect(lineupStrength(w, empty), 0);
    });
  });
}
