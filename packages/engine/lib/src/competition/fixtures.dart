import '../core/ids.dart';
import '../core/rng.dart';
import '../model/calendar.dart';
import '../model/country.dart';
import '../model/fixture.dart';
import 'season_calendar_builder.dart';

/// Sentinel opponent for odd club counts; its pairing is dropped (a bye).
const ClubId _bye = -1;

/// Double round robin via the circle (Berger) method.
///
/// Returns rounds of `(home, away)` pairs: `2 * (n - 1)` rounds for even `n`,
/// `2 * n` for odd `n` (each club sits out one round per half). The second
/// half repeats the first with venues swapped. [rng] only shuffles a copy of
/// [clubs]; [clubs] itself is not modified.
List<List<(ClubId, ClubId)>> doubleRoundRobin(
  List<ClubId> clubs,
  SeededRng rng,
) {
  if (clubs.length < 2) {
    throw ArgumentError.value(clubs, 'clubs', 'needs at least 2 clubs');
  }
  final order = List.of(clubs);
  rng.shuffle(order);
  if (order.length.isOdd) order.add(_bye);

  final n = order.length;
  final m = n - 1; // rounds per half; order[m] is the fixed club
  final fixed = order[m];
  final firstHalf = <List<(ClubId, ClubId)>>[];
  for (var i = 0; i < m; i++) {
    // Every club's venues alternate around the cycle of m rounds except for a
    // single repeat. Starting the half at cycle round 3 keeps those repeats
    // off the half's first and last transitions, so with the mirrored second
    // half no club plays more than 2 consecutive home or away matches.
    final r = (i + 3) % m;
    final round = <(ClubId, ClubId)>[];
    void add(ClubId home, ClubId away) {
      if (home != _bye && away != _bye) round.add((home, away));
    }

    final pivot = order[r];
    r.isEven ? add(fixed, pivot) : add(pivot, fixed);
    for (var k = 1; k < n ~/ 2; k++) {
      final a = order[(r + k) % m];
      final b = order[(r - k + m) % m];
      k.isOdd ? add(a, b) : add(b, a);
    }
    firstHalf.add(round);
  }
  return [
    ...firstHalf,
    for (final round in firstHalf) [for (final (h, a) in round) (a, h)],
  ];
}

/// [league]'s fixtures for [seasonYear]: `doubleRoundRobin(league.clubIds,
/// rng)` placed round by round on `leagueMatchdays(calendar, rounds)`, with
/// ids drawn from [ids] (`'fixture'`) in round-major, pair order.
List<Fixture> scheduleLeagueFixtures({
  required League league,
  required SeasonCalendar calendar,
  required int seasonYear,
  required IdAllocator ids,
  required SeededRng rng,
}) {
  final rounds = doubleRoundRobin(league.clubIds, rng);
  final dates = leagueMatchdays(calendar, rounds.length);
  return [
    for (var r = 0; r < rounds.length; r++)
      for (final (home, away) in rounds[r])
        Fixture(
          id: ids.next('fixture'),
          leagueId: league.id,
          seasonYear: seasonYear,
          round: r + 1,
          date: dates[r],
          homeId: home,
          awayId: away,
        ),
  ];
}
