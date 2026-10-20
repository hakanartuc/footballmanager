@Tags(['slow'])
library;

import 'package:engine/engine.dart';
import 'package:test/test.dart';

void main() {
  test('large world generates in under 8 s', () {
    final sw = Stopwatch()..start();
    final w = generateWorld(
      seed: 1,
      size: WorldSize.large,
      startDate: buildSeasonCalendar(2026).seasonStart.addDays(-14),
    );
    sw.stop();
    expect(w.countries, hasLength(16));
    expect(w.clubs, hasLength(506));
    print('large world: ${sw.elapsedMilliseconds} ms');
    expect(sw.elapsed, lessThan(const Duration(seconds: 8)));
  });
}
