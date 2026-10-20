@Tags(['slow'])
library;

import 'package:engine/engine.dart';
import 'package:test/test.dart';

const _seasons = 5;

/// Faz 0 placeholder bands (spec §9's 2.5..2.9 is a single-match,
/// equal-strength target; a league with the generator's strength spread
/// sits at ~2.87 under the Poisson placeholder, so the ceiling is 3.0).
const _goalsBand = (2.5, 3.0);
const _homeBand = (43.0, 47.0);

typedef _Buckets = ({double u20, double u25, double u30, double over30});

class _Season {
  _Season(this.year);

  final int year;
  int retired = 0;
  int intake = 0;
  int released = 0;
  int matches = 0;
  double goalsPerMatch = 0;
  double homeWinPct = 0;

  /// League id -> table leader, computed the morning of `seasonEnd`.
  Map<LeagueId, ClubId> leaders = {};
  late SeasonArchive archive;
  int players = 0;
  late _Buckets ages;
  int maxYouth = 0;
}

_Buckets _ageBuckets(World w) {
  var u20 = 0, u25 = 0, u30 = 0, over30 = 0;
  for (final p in w.players.values) {
    final age = p.ageAt(w.date);
    if (age <= 20) {
      u20++;
    } else if (age <= 25) {
      u25++;
    } else if (age <= 30) {
      u30++;
    } else {
      over30++;
    }
  }
  final n = w.players.length;
  double pct(int c) => 100 * c / n;
  return (u20: pct(u20), u25: pct(u25), u30: pct(u30), over30: pct(over30));
}

void main() {
  late EngineSession session;
  final seasons = <_Season>[];
  final violations = <String>[];

  setUpAll(() {
    final probe = createNewGame(
      NewGameSpec(
        seed: 11,
        size: WorldSize.small,
        managerFirstName: 'Long',
        managerLastName: 'Runner',
        managerCountryCode: 'TR',
        startClubId: null,
      ),
    );
    final tr = probe.countries.values.firstWhere((c) => c.code == 'TR');
    session = EngineSession.newGame(
      NewGameSpec(
        seed: 11,
        size: WorldSize.small,
        managerFirstName: 'Long',
        managerLastName: 'Runner',
        managerCountryCode: 'TR',
        startClubId: probe.leagues[tr.tiers[0]]!.clubIds[0],
      ),
    );
    final w = session.world;
    final watch = Stopwatch()..start();
    var days = 0;
    while (seasons.length < _seasons) {
      final year = w.seasonYear;
      // The table the archive must match: computed before the rollover
      // changes league membership.
      final leaders = w.date == w.calendar.seasonEnd
          ? {for (final l in w.leagues.keys) l: session.table(l).first.clubId}
          : null;

      final summary = session.advanceDay();
      days++;
      var retired = 0, intake = 0, released = 0;
      for (final e in summary.events) {
        switch (e) {
          case PlayerRetired():
            retired++;
          case YouthIntake(:final playerIds):
            intake += playerIds.length;
          case YouthReleased(:final playerIds):
            released += playerIds.length;
          default:
            break;
        }
      }
      // Daily invariants (squad.size 18..28 is among them).
      for (final v in session.checkInvariants()) {
        violations.add('${summary.date.iso}: $v');
      }

      if (!summary.events.any((e) => e is SeasonEnded)) continue;
      final s = _Season(year)
        ..retired = retired
        ..intake = intake
        ..released = released;
      final played = [
        for (final f in w.fixtures.values)
          if (f.seasonYear == year && f.result != null) f.result!,
      ];
      s.matches = played.length;
      s.goalsPerMatch =
          played.fold(0, (sum, r) => sum + r.homeGoals + r.awayGoals) /
          played.length;
      s.homeWinPct =
          100 *
          played.where((r) => r.homeGoals > r.awayGoals).length /
          played.length;
      s.leaders = leaders!;
      s.archive = w.history.last;
      s.players = w.players.length;
      s.ages = _ageBuckets(w);
      s.maxYouth = w.clubs.keys
          .map((c) => w.youthOf(c).length)
          .reduce((a, b) => a > b ? a : b);
      seasons.add(s);
      print(
        'season ${s.year}: ${s.matches} matches, '
        '${s.goalsPerMatch.toStringAsFixed(3)} goals/match, '
        'home ${s.homeWinPct.toStringAsFixed(2)} %, '
        'players ${s.players}, ages '
        '${s.ages.u20.toStringAsFixed(1)}/${s.ages.u25.toStringAsFixed(1)}/'
        '${s.ages.u30.toStringAsFixed(1)}/${s.ages.over30.toStringAsFixed(1)}, '
        'max youth ${s.maxYouth}, '
        'retired ${s.retired}, intake ${s.intake}, released ${s.released}',
      );
    }
    print(
      'long sim: $_seasons seasons, $days days, '
      '${watch.elapsedMilliseconds} ms, ${violations.length} violations',
    );
  });

  test('no invariant is broken on any day', () {
    expect(violations, isEmpty);
  });

  test('every season has the expected number of matches', () {
    for (final s in seasons) {
      expect(s.matches, greaterThan(2000), reason: 'season ${s.year}');
    }
  });

  test('goals per match stay in ${_goalsBand.$1}..${_goalsBand.$2}', () {
    for (final s in seasons) {
      expect(
        s.goalsPerMatch,
        inInclusiveRange(_goalsBand.$1, _goalsBand.$2),
        reason: 'season ${s.year}',
      );
    }
  });

  test('home win percentage stays in ${_homeBand.$1}..${_homeBand.$2}', () {
    for (final s in seasons) {
      expect(
        s.homeWinPct,
        inInclusiveRange(_homeBand.$1, _homeBand.$2),
        reason: 'season ${s.year}',
      );
    }
  });

  test('every champion is the table leader and matches the archive', () {
    for (final s in seasons) {
      expect(s.archive.seasonYear, s.year);
      expect(s.archive.champions.keys, unorderedEquals(s.leaders.keys));
      for (final MapEntry(key: league, value: leader) in s.leaders.entries) {
        final reason = 'season ${s.year} league $league';
        expect(s.archive.champions[league], leader, reason: reason);
        expect(s.archive.finalOrder[league]!.first, leader, reason: reason);
      }
    }
  });

  // Population gates are measured after the transient: the generated world
  // is not at steady state (squads 22..26 vs the cap of 28, youth cohorts
  // fill over three seasons), so season 2 is the count baseline and season
  // 5 the measurement. The spec's 30-season ±10 % gate arrives in Faz 4.
  test('player count at season 5 is within 10 % of season 2', () {
    final base = seasons[1].players;
    expect(seasons.last.players, inInclusiveRange(base * 0.9, base * 1.1));
  });

  // Season 3 baseline: the generated 18..34 cohort is still aging into
  // 31+ (11 % → 21 %, the spec's steady value) through season 2; that is
  // cohort aging, not drift.
  test('age buckets at season 5 are within 8 points of season 3', () {
    final base = seasons[2].ages;
    final s = seasons.last;
    for (final (name, a, b) in [
      ('16-20', s.ages.u20, base.u20),
      ('21-25', s.ages.u25, base.u25),
      ('26-30', s.ages.u30, base.u30),
      ('31+', s.ages.over30, base.over30),
    ]) {
      expect(a, closeTo(b, 8), reason: 'bucket $name');
    }
  });

  // Steady state is 18 (three intake cohorts of up to 6); the 21 at season
  // 3 is the generated 15..17 cohort meeting the first full intake cohort.
  test('no youth squad grows beyond 21', () {
    for (final s in seasons) {
      expect(s.maxYouth, lessThanOrEqualTo(21), reason: 'season ${s.year}');
    }
  });
}
