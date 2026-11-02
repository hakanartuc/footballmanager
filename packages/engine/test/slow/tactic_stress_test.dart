@Tags(['slow'])
library;

import 'package:engine/engine.dart';
import 'package:test/test.dart';

const _matches = 10000;
const _seed = 2026;

const _outfield = [
  Position.dl,
  Position.dc,
  Position.dr,
  Position.dm,
  Position.ml,
  Position.mc,
  Position.mr,
  Position.aml,
  Position.amc,
  Position.amr,
  Position.st,
];

T _pick<T>(SeededRng rng, List<T> items) => items[rng.nextInt(items.length)];

/// A formation's slots, or 10 random outfield positions behind the keeper
/// for [Formation.custom].
List<Position> _slots(SeededRng rng, Formation f) => f == Formation.custom
    ? [Position.gk, for (var i = 0; i < 10; i++) _pick(rng, _outfield)]
    : formationSlots(f);

/// Every setting drawn uniformly; player references point at the
/// starters [ids] (or nobody).
Tactic _randomTactic(
  SeededRng rng,
  Formation f,
  List<Position> slots,
  List<PlayerId> ids,
) {
  PlayerId? someone() => rng.nextBool(0.5) ? _pick(rng, ids) : null;
  final tactic = f == Formation.custom
      ? Tactic.custom(slots)
      : Tactic.preset(f);
  tactic
    ..mentality = _pick(rng, Mentality.values)
    ..passing = _pick(rng, PassingStyle.values)
    ..tempo = _pick(rng, Tempo.values)
    ..width = _pick(rng, Width.values)
    ..pressing = _pick(rng, Pressing.values)
    ..tackling = _pick(rng, Tackling.values)
    ..marking = _pick(rng, Marking.values)
    ..offsideTrap = rng.nextBool(0.5)
    ..counterAttack = rng.nextBool(0.5)
    ..playmaker = someone()
    ..targetMan = someone()
    ..captain = someone()
    ..viceCaptain = someone()
    ..setPieces = SetPieceTakers(
      cornerLeft: someone(),
      cornerRight: someone(),
      freeKickLeft: someone(),
      freeKickRight: someone(),
      penalty: someone(),
      longThrow: someone(),
    );
  for (final id in ids) {
    if (rng.nextBool(0.3)) {
      tactic.instructions[id] = PlayerInstructions(
        forwardRuns: rng.nextBool(0.5),
        runWithBall: rng.nextBool(0.5),
        longShots: rng.nextBool(0.5),
        throughBalls: rng.nextBool(0.5),
        holdUpBall: rng.nextBool(0.5),
        freeRole: rng.nextBool(0.5),
        crossFrom: _pick(rng, CrossTarget.values),
      );
    }
    if (rng.nextBool(0.3)) tactic.arrows[id] = _pick(rng, Arrow.values);
  }
  return tactic;
}

void main() {
  test('$_matches matches with random tactics, formations and strengths '
      'finish with finite statistics and 1.5..4.5 goals per match', () {
    final root = SeededRng(_seed);
    const sim = PossessionMatchSimulator();
    var goals = 0;
    var custom = 0;
    var abandoned = 0;
    final watch = Stopwatch()..start();
    for (var i = 0; i < _matches; i++) {
      final setup = root.fork('stress:setup:$i');
      final players = <PlayerId, Player>{};
      final clubs = <ClubId, Club>{};
      final tactics = <ClubId, Tactic>{};
      for (final id in [1, 2]) {
        final f = _pick(setup, Formation.values);
        if (f == Formation.custom) custom++;
        final slots = _slots(setup, f);
        clubs[id] = syntheticClub(
          id: id,
          attr: 8 + setup.nextInt(9),
          players: players,
          formation: f,
          slots: slots,
        );
        tactics[id] = _randomTactic(
          setup,
          f,
          slots,
          clubs[id]!.lineup!.starters,
        );
      }
      final w = syntheticWorld(players: players, clubs: clubs, seed: _seed);
      final r = sim.simulate(
        MatchContext(
          world: w,
          fixture: Fixture(
            id: i + 1,
            leagueId: 1,
            seasonYear: w.seasonYear,
            round: 1,
            date: w.date,
            homeId: 1,
            awayId: 2,
          ),
          home: clubs[1]!.lineup!,
          away: clubs[2]!.lineup!,
          rng: root.fork('stress:match:$i'),
          rules: MatchRules.league,
          conditions: MatchConditions.neutral,
          homeTactic: tactics[1],
          awayTactic: tactics[2],
        ),
      );
      final reason = 'match $i';
      expect(r.events.last, isA<FullTime>(), reason: reason);
      if (r.abandoned) abandoned++;
      goals += r.homeGoals + r.awayGoals;
      for (final stats in [r.homeStats!, r.awayStats!]) {
        expect(stats.xg.isFinite, isTrue, reason: reason);
        expect(stats.xg, greaterThanOrEqualTo(0), reason: reason);
        expect(stats.possessionPct, inInclusiveRange(0, 100), reason: reason);
        expect(
          stats.shots,
          greaterThanOrEqualTo(stats.onTarget),
          reason: reason,
        );
      }
      expect(
        r.homeStats!.possessionPct + r.awayStats!.possessionPct,
        100,
        reason: reason,
      );
      for (final v in r.ratings.values) {
        expect(v.isFinite, isTrue, reason: reason);
        expect(v, inInclusiveRange(1, 10), reason: reason);
      }
      for (final c in r.finalCondition.values) {
        expect(c.isFinite, isTrue, reason: reason);
        expect(c, inInclusiveRange(0, 100), reason: reason);
      }
      if (!r.abandoned) {
        expect(
          r.goals.where((g) => g.clubId == 1).length,
          r.homeGoals,
          reason: reason,
        );
        expect(
          r.goals.where((g) => g.clubId == 2).length,
          r.awayGoals,
          reason: reason,
        );
      }
    }
    print(
      'tactic stress: $_matches matches in ${watch.elapsedMilliseconds} ms, '
      '${(goals / _matches).toStringAsFixed(3)} goals/match, '
      '$custom custom formations, $abandoned abandoned',
    );
    expect(custom, greaterThan(0));
    expect(goals / _matches, inInclusiveRange(1.5, 4.5));
  });
}
