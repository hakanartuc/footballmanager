@Tags(['slow'])
library;

import 'package:engine/engine.dart';
import 'package:test/test.dart';

const _n = 20000;
const _formation = Formation.f442;

Player _player(int id, Position slot, int ca) => Player(
  id: id,
  firstName: 'P',
  lastName: '$id',
  nationality: 1,
  birth: GameDate.ymd(2000, 1, 1),
  heightCm: 180,
  mainPosition: slot,
  familiarity: {slot: 20},
  attrs: Attributes.filled(10),
  ca: ca,
  pa: ca,
  hidden: HiddenAttrs(
    injuryProneness: 10,
    consistency: 10,
    bigMatches: 10,
    professionalism: 10,
  ),
);

/// Two eleven-player lineups (ids 1..11 and 12..22) of the given strengths.
(World, Lineup, Lineup) _setup(int homeCa, int awayCa) {
  final slots = formationSlots(_formation);
  final players = <PlayerId, Player>{};
  Lineup lineup(int firstId, int ca) {
    final ids = <PlayerId>[];
    for (var i = 0; i < 11; i++) {
      final id = firstId + i;
      players[id] = _player(id, slots[i], ca);
      ids.add(id);
    }
    return Lineup(formation: _formation, starters: ids, bench: []);
  }

  final home = lineup(1, homeCa);
  final away = lineup(12, awayCa);
  final w = World(
    schemaVersion: 1,
    seed: 1,
    date: GameDate.ymd(2026, 8, 1),
    seasonYear: 2026,
    countries: {},
    leagues: {},
    clubs: {},
    players: players,
    managers: {},
    fixtures: {},
    calendar: buildSeasonCalendar(2026),
    userManagerId: 1,
    ids: IdAllocator(),
  );
  return (w, home, away);
}

typedef _Stats = ({double meanGoals, double home, double draw, double away});

_Stats _run(int homeCa, int awayCa) {
  final (w, home, away) = _setup(homeCa, awayCa);
  final fx = Fixture(
    id: 1,
    leagueId: 1,
    seasonYear: 2026,
    round: 1,
    date: w.date,
    homeId: 1,
    awayId: 2,
  );
  final root = SeededRng(1);
  const sim = PoissonMatchSimulator();
  var goals = 0;
  var homeWins = 0;
  var draws = 0;
  for (var i = 0; i < _n; i++) {
    final r = sim.simulate(
      MatchContext(
        world: w,
        fixture: fx,
        home: home,
        away: away,
        rng: root.fork('match:$i'),
      ),
    );
    goals += r.homeGoals + r.awayGoals;
    if (r.homeGoals > r.awayGoals) {
      homeWins++;
    } else if (r.homeGoals == r.awayGoals) {
      draws++;
    }
  }
  return (
    meanGoals: goals / _n,
    home: homeWins / _n,
    draw: draws / _n,
    away: (_n - homeWins - draws) / _n,
  );
}

void main() {
  test('equal strength 120 v 120 hits the calibration targets', () {
    final s = _run(120, 120);
    print(
      'equal: goals ${s.meanGoals.toStringAsFixed(3)} '
      'H ${(s.home * 100).toStringAsFixed(1)}% '
      'D ${(s.draw * 100).toStringAsFixed(1)}% '
      'A ${(s.away * 100).toStringAsFixed(1)}%',
    );
    expect(s.meanGoals, inInclusiveRange(2.5, 2.9));
    expect(s.home, inInclusiveRange(0.43, 0.47));
    expect(s.draw, inInclusiveRange(0.24, 0.28));
    expect(s.away, inInclusiveRange(0.27, 0.31));
  });

  test('strength gap +40 makes the stronger side win 74-82%', () {
    final strongerHome = _run(160, 120).home;
    final strongerAway = _run(120, 160).away;
    final avg = (strongerHome + strongerAway) / 2;
    print(
      'gap +40: stronger wins ${(avg * 100).toStringAsFixed(1)}% '
      '(home ${(strongerHome * 100).toStringAsFixed(1)}%, '
      'away ${(strongerAway * 100).toStringAsFixed(1)}%)',
    );
    expect(avg, inInclusiveRange(0.74, 0.82));
  });
}
