import 'dart:math' as math;

import '../core/game_date.dart';
import '../core/ids.dart';
import '../core/rng.dart';
import '../model/club.dart';
import '../model/events.dart';
import '../model/world.dart';
import 'commands.dart';
import 'lineup.dart';
import 'match_simulator.dart';

/// Daily condition recovery applied to every player in [DayRunner.startOfDay].
const double conditionRecoveryPerDay = 12;

/// Oldest inbox messages are dropped beyond this many.
const int inboxLimit = 300;

/// What one [DayRunner.advanceDay] did.
class DaySummary {
  const DaySummary({
    required this.date,
    required this.events,
    required this.playedFixtures,
    required this.elapsed,
  });

  /// The date that was processed (the world is now on the next day).
  final GameDate date;
  final List<GameEvent> events;
  final List<FixtureId> playedFixtures;
  final Duration elapsed;
}

/// The engine's heartbeat: one game day in three phases.
///
/// Symmetry rule: [startOfDay] and [playMatches] treat every club alike and
/// never consult `isUser` or `userManagerId`; the user matters only when
/// [endOfDay] decides what goes to the inbox.
///
/// [rollover] is the season-rollover hook (Task 16's `rolloverSeason`). When
/// it is set, [endOfDay] calls it on `calendar.seasonEnd` with
/// `SeededRng(seed).fork('rollover:<seasonYear>')` and appends its events;
/// when null, nothing happens at season end.
class DayRunner {
  DayRunner(this.sim, {this.rollover});

  final MatchSimulator sim;
  final List<GameEvent> Function(World w, SeededRng rng)? rollover;

  /// Applies [commands] in order (an invalid `SetLineup` is ignored
  /// silently; a valid one is stored as a copy, so the caller's `Lineup`
  /// stays its own), recovers every player's condition, then gives each
  /// club with a fixture today a valid lineup, picking one automatically
  /// when the stored one is missing or no longer valid.
  void startOfDay(World w, List<Command> commands) {
    for (final cmd in commands) {
      switch (cmd) {
        case SetLineup(:final clubId, :final lineup):
          if (validateLineup(w, clubId, lineup).isEmpty) {
            w.clubs[clubId]!.lineup = Lineup(
              formation: lineup.formation,
              starters: List.of(lineup.starters),
              bench: List.of(lineup.bench),
            );
          }
        case ClearLineup(:final clubId):
          w.clubs[clubId]?.lineup = null;
      }
    }

    for (final id in w.players.keys.toList()..sort()) {
      final state = w.players[id]!.state;
      state.condition = math.min(
        100,
        state.condition + conditionRecoveryPerDay,
      );
    }

    final playing = <ClubId>{};
    for (final id in w.fixturesOn(w.date)) {
      final f = w.fixtures[id]!;
      playing
        ..add(f.homeId)
        ..add(f.awayId);
    }
    for (final clubId in playing.toList()..sort()) {
      final club = w.clubs[clubId]!;
      final lineup = club.lineup;
      if (lineup == null || validateLineup(w, clubId, lineup).isNotEmpty) {
        club.lineup = autoLineup(w, clubId);
      }
    }
  }

  /// Simulates every unplayed fixture dated today, sorted by id, storing
  /// the result and crediting appearances and goals. Each match draws from
  /// `SeededRng(seed).fork('match:<fixtureId>:<seasonYear>')`.
  List<FixtureId> playMatches(World w) {
    final played = <FixtureId>[];
    for (final id in w.fixturesOn(w.date)) {
      final f = w.fixtures[id]!;
      if (f.result != null) continue;
      final home = w.clubs[f.homeId]!.lineup ??= autoLineup(w, f.homeId);
      final away = w.clubs[f.awayId]!.lineup ??= autoLineup(w, f.awayId);
      final result = sim.simulate(
        MatchContext(
          world: w,
          fixture: f,
          home: home,
          away: away,
          rng: SeededRng(w.seed).fork('match:${f.id}:${w.seasonYear}'),
        ),
      );
      f.result = result;
      for (final p in [...home.starters, ...away.starters]) {
        w.players[p]!.season.apps += 1;
      }
      for (final g in result.goals) {
        w.players[g.scorerId]!.season.goals += 1;
      }
      played.add(id);
    }
    return played;
  }

  /// Runs [rollover] on the season's last day, delivers the user-relevant
  /// events of the day ([dayEvents] plus the rollover's) to the inbox,
  /// trims it to [inboxLimit], and moves the world to the next day.
  /// Returns the rollover events.
  List<GameEvent> endOfDay(World w, {List<GameEvent> dayEvents = const []}) {
    final hook = rollover;
    final rolled = hook != null && w.date == w.calendar.seasonEnd
        ? hook(w, SeededRng(w.seed).fork('rollover:${w.seasonYear}'))
        : <GameEvent>[];

    for (final e in [...dayEvents, ...rolled]) {
      if (isUserRelevant(w, e)) {
        w.inbox.add(InboxMessage(date: w.date, event: e));
      }
    }
    if (w.inbox.length > inboxLimit) {
      w.inbox.removeRange(0, w.inbox.length - inboxLimit);
    }

    w.date = w.date.addDays(1);
    return rolled;
  }

  /// [startOfDay], [playMatches] and [endOfDay] in order.
  DaySummary advanceDay(World w, List<Command> commands) {
    final watch = Stopwatch()..start();
    final date = w.date;
    startOfDay(w, commands);
    final played = playMatches(w);
    final matchEvents = <GameEvent>[
      for (final id in played) MatchPlayed(date: date, fixtureId: id),
    ];
    final rolled = endOfDay(w, dayEvents: matchEvents);
    return DaySummary(
      date: date,
      events: [...matchEvents, ...rolled],
      playedFixtures: played,
      elapsed: watch.elapsed,
    );
  }
}

/// Whether [e] belongs in the user's inbox: season-level events always;
/// otherwise only events involving the user's club (or, for
/// [LeagueChampion], the user's league). An unemployed user sees only
/// season-level events.
bool isUserRelevant(World w, GameEvent e) {
  final club = w.userClub;
  return switch (e) {
    SeasonEnded() || NewSeasonStarted() => true,
    _ when club == null => false,
    MatchPlayed(:final fixtureId) =>
      w.fixtures[fixtureId]!.homeId == club.id ||
          w.fixtures[fixtureId]!.awayId == club.id,
    LeagueChampion(:final leagueId, :final clubId) =>
      clubId == club.id || leagueId == club.leagueId,
    Promoted(:final clubId) => clubId == club.id,
    Relegated(:final clubId) => clubId == club.id,
    PlayerRetired(:final clubId) => clubId == club.id,
    YouthIntake(:final clubId) => clubId == club.id,
    YouthReleased(:final clubId) => clubId == club.id,
  };
}
