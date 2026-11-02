/// Spec 5.4: fast and detailed mode give the same result for the same seed.
/// Four ways of playing one fixture must produce identical result JSON.
library;

import 'dart:convert';

import 'package:engine/engine.dart';
import 'package:test/test.dart';

World _world() => createNewGame(
  NewGameSpec(
    seed: 1,
    size: WorldSize.small,
    managerFirstName: 'T',
    managerLastName: 'M',
    managerCountryCode: 'TR',
    startClubId: null,
  ),
);

List<Fixture> _fixtures(World w, int n) {
  final ids = w.fixtures.keys.toList()..sort();
  return [for (final id in ids.take(n)) w.fixtures[id]!];
}

MatchContext _ctx(
  World w,
  Fixture f,
  Lineup home,
  Lineup away,
  MatchDetail detail,
) => MatchContext(
  world: w,
  fixture: f,
  home: home,
  away: away,
  rng: SeededRng(w.seed).fork('match:${f.id}:${w.seasonYear}'),
  detail: detail,
);

String _json(MatchResult r) => jsonEncode(matchResultToJson(r));

/// The result of [f] by `simulate`, by a `step` loop, by a `runUntil` loop
/// and by a `full` session, as JSON.
List<String> _variants(World w, Fixture f) {
  final home = autoLineup(w, f.homeId);
  final away = autoLineup(w, f.awayId);
  final a = const PossessionMatchSimulator().simulate(
    _ctx(w, f, home, away, MatchDetail.result),
  );
  final sb = MatchSession(_ctx(w, f, home, away, MatchDetail.result));
  while (!sb.finished) {
    sb.step();
  }
  final b = sb.finish();
  final sc = MatchSession(_ctx(w, f, home, away, MatchDetail.events));
  while (!sc.finished) {
    sc.runUntil();
  }
  final c = sc.finish();
  final d = MatchSession(_ctx(w, f, home, away, MatchDetail.full)).finish();
  return [_json(a), _json(b), _json(c), _json(d)];
}

void _expectEquivalent(World w, List<Fixture> fixtures) {
  for (final f in fixtures) {
    final v = _variants(w, f);
    expect(v[1], v[0], reason: 'fixture ${f.id}: step loop');
    expect(v[2], v[0], reason: 'fixture ${f.id}: runUntil loop');
    expect(v[3], v[0], reason: 'fixture ${f.id}: full detail');
  }
}

void main() {
  test('20 fixtures: simulate == step loop == runUntil loop == full', () {
    final w = _world();
    _expectEquivalent(w, _fixtures(w, 20));
  });

  // 800 matches run well under two seconds, so this stays untagged.
  test('200 fixtures: simulate == step loop == runUntil loop == full', () {
    final w = _world();
    _expectEquivalent(w, _fixtures(w, 200));
  });
}
