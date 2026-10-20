@Tags(['slow'])
library;

import 'package:engine/engine.dart';
import 'package:test/test.dart';

void main() {
  test('large world invariant check runs in under 50 ms', () {
    final w = createNewGame(
      NewGameSpec(
        seed: 1,
        size: WorldSize.large,
        managerFirstName: 'Test',
        managerLastName: 'Manager',
        managerCountryCode: 'TR',
        startClubId: null,
      ),
    );
    final sw = Stopwatch()..start();
    final violations = checkInvariants(w);
    sw.stop();
    print('large world invariants: ${sw.elapsedMicroseconds / 1000} ms');
    expect(violations, isEmpty);
    expect(sw.elapsed, lessThan(const Duration(milliseconds: 50)));
  });
}
