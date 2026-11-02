@Tags(['slow'])
library;

import 'package:engine/engine.dart';
import 'package:test/test.dart';

const _days = 400;
const _fastMatches = 1000;
const _fastWarmUp = 100;

/// The first match days are JIT warm-up and are left out of the p95.
const _warmUpMatchDays = 5;

/// Nearest-rank percentile of [sorted].
double _percentile(List<double> sorted, int p) =>
    sorted[((p / 100) * (sorted.length - 1)).round()];

String _describe(String name, List<double> sorted) =>
    '$name n=${sorted.length} '
    'p50 ${_percentile(sorted, 50).toStringAsFixed(2)} ms, '
    'p95 ${_percentile(sorted, 95).toStringAsFixed(2)} ms, '
    'max ${sorted.last.toStringAsFixed(2)} ms';

void main() {
  // The three tests run in order on one session: generate, advance, save.
  late EngineSession session;

  test('large world generates in under 8 s', () {
    final watch = Stopwatch()..start();
    session = EngineSession.newGame(
      NewGameSpec(
        seed: 1,
        size: WorldSize.large,
        managerFirstName: 'Perf',
        managerLastName: 'Gate',
        managerCountryCode: 'TR',
        startClubId: null,
      ),
    );
    watch.stop();
    print('perf: large world generated in ${watch.elapsedMilliseconds} ms');
    expect(session.world.clubs, hasLength(506));
    expect(watch.elapsed, lessThan(const Duration(seconds: 8)));
  });

  test('$_days days: match-day p95 < 300 ms, other-day p95 < 50 ms', () {
    final matchDays = <double>[];
    final otherDays = <double>[];
    for (var i = 0; i < _days; i++) {
      final s = session.advanceDay();
      (s.playedFixtures.isNotEmpty ? matchDays : otherDays).add(
        s.elapsed.inMicroseconds / 1000,
      );
    }
    expect(matchDays.length, greaterThan(_warmUpMatchDays + 20));
    final warm = matchDays.sublist(_warmUpMatchDays)..sort();
    final other = [...otherDays]..sort();
    print(
      'perf: ${_describe('match days', warm)} '
      '(warm-up ${matchDays.take(_warmUpMatchDays).map((ms) => ms.toStringAsFixed(1)).join('/')} ms); '
      '${_describe('other days', other)}',
    );
    expect(_percentile(warm, 95), lessThan(300));
    expect(_percentile(other, 95), lessThan(50));
  });

  test('save < 15 MB in < 2 s and load < 2 s', () {
    final watch = Stopwatch()..start();
    final bytes = session.save();
    final saveMs = watch.elapsedMilliseconds;
    watch.reset();
    final restored = EngineSession.fromBytes(bytes);
    final loadMs = watch.elapsedMilliseconds;
    print('perf: save ${bytes.length} bytes in $saveMs ms, load in $loadMs ms');
    expect(restored.world.date, session.world.date);
    expect(bytes.length, lessThan(15 * 1024 * 1024));
    expect(saveMs, lessThan(2000));
    expect(loadMs, lessThan(2000));
  });

  test('$_fastMatches fast-mode matches between large-world clubs < 600 ms', () {
    final w = createNewGame(
      NewGameSpec(
        seed: 1,
        size: WorldSize.large,
        managerFirstName: 'Perf',
        managerLastName: 'Gate',
        managerCountryCode: 'TR',
        startClubId: null,
      ),
    );
    final runner = DayRunner();
    final ids = w.fixtures.keys.toList()..sort();
    List<MatchContext> contexts(int from, int count) => [
      for (final id in ids.skip(from).take(count))
        runner.contextFor(w, w.fixtures[id]!),
    ];
    const sim = PossessionMatchSimulator();
    // JIT warm-up on the next fixtures; only the first ones are timed.
    for (final c in contexts(_fastMatches, _fastWarmUp)) {
      sim.simulate(c);
    }
    final timed = contexts(0, _fastMatches);
    final watch = Stopwatch()..start();
    for (final c in timed) {
      sim.simulate(c);
    }
    watch.stop();
    print(
      'perf: $_fastMatches fast-mode matches in ${watch.elapsedMilliseconds} ms '
      '(${(watch.elapsedMicroseconds / _fastMatches / 1000).toStringAsFixed(3)} ms each)',
    );
    expect(watch.elapsedMilliseconds, lessThan(600));
  });
}
