import 'package:engine/engine.dart';
import 'package:test/test.dart';

List<ClubId> _clubs(int n) => List.generate(n, (i) => 101 + i);

void main() {
  for (final n in [4, 18, 19, 20, 24]) {
    group('n = $n', () {
      final clubs = _clubs(n);
      final rounds = doubleRoundRobin(clubs, SeededRng(7));

      test('round count', () {
        expect(rounds, hasLength(n.isEven ? 2 * (n - 1) : 2 * n));
      });

      test('every pair meets exactly twice with swapped venues', () {
        final counts = <(ClubId, ClubId), int>{};
        for (final round in rounds) {
          for (final m in round) {
            counts[m] = (counts[m] ?? 0) + 1;
          }
        }
        expect(counts, hasLength(n * (n - 1)));
        for (final a in clubs) {
          for (final b in clubs) {
            if (a == b) continue;
            expect(counts[(a, b)], 1, reason: '$a hosts $b once');
          }
        }
      });

      test('no club appears twice in a round', () {
        for (final round in rounds) {
          final seen = <ClubId>{};
          for (final (home, away) in round) {
            expect(seen.add(home), isTrue);
            expect(seen.add(away), isTrue);
          }
        }
      });

      test('second half mirrors first half', () {
        final half = rounds.length ~/ 2;
        for (var r = 0; r < half; r++) {
          expect(rounds[half + r], [
            for (final (home, away) in rounds[r]) (away, home),
          ]);
        }
      });

      if (n.isOdd) {
        test('each club has exactly 2 byes', () {
          for (final c in clubs) {
            final byes = rounds
                .where((round) => !round.any((m) => m.$1 == c || m.$2 == c))
                .length;
            expect(byes, 2, reason: 'club $c');
          }
        });
      } else {
        test('every club plays every round', () {
          for (final round in rounds) {
            expect(round, hasLength(n ~/ 2));
          }
        });
      }
    });
  }

  test('n = 20: no venue streak longer than 2', () {
    final clubs = _clubs(20);
    final rounds = doubleRoundRobin(clubs, SeededRng(99));
    for (final c in clubs) {
      var streak = 0;
      bool? lastHome;
      for (final round in rounds) {
        final home = round.firstWhere((m) => m.$1 == c || m.$2 == c).$1 == c;
        streak = home == lastHome ? streak + 1 : 1;
        lastHome = home;
        expect(streak, lessThanOrEqualTo(2), reason: 'club $c');
      }
    }
  });

  test('same seed gives identical output', () {
    expect(
      doubleRoundRobin(_clubs(20), SeededRng(5)),
      doubleRoundRobin(_clubs(20), SeededRng(5)),
    );
  });

  test('different seed gives a different first round', () {
    expect(
      doubleRoundRobin(_clubs(20), SeededRng(5)).first,
      isNot(doubleRoundRobin(_clubs(20), SeededRng(6)).first),
    );
  });

  test('does not mutate the input list', () {
    final clubs = _clubs(20);
    doubleRoundRobin(clubs, SeededRng(5));
    expect(clubs, _clubs(20));
  });

  test('fewer than 2 clubs throws', () {
    expect(() => doubleRoundRobin([1], SeededRng(1)), throwsArgumentError);
    expect(() => doubleRoundRobin([], SeededRng(1)), throwsArgumentError);
  });
}
