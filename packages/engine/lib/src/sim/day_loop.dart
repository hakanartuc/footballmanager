import 'dart:math' as math;

import '../core/game_date.dart';
import '../core/ids.dart';
import '../core/rng.dart';
import '../model/club.dart';
import '../model/events.dart';
import '../model/fixture.dart';
import '../model/world.dart';
import 'commands.dart';
import 'discipline.dart';
import 'lineup.dart';
import 'match/conditions.dart';
import 'match/possession_match_simulator.dart';
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
  DayRunner({this.sim = const PossessionMatchSimulator(), this.rollover});

  final MatchSimulator sim;
  final List<GameEvent> Function(World w, SeededRng rng)? rollover;

  /// Applies [commands] in order (an invalid `SetLineup` is ignored
  /// silently; a valid one is stored as a copy, so the caller's `Lineup`
  /// stays its own), recovers every player's condition, runs
  /// [dailyRecovery], then gives each club with a fixture today a valid
  /// lineup on its active tactic's formation, picking one automatically
  /// when the stored one is missing, on another formation or no longer
  /// valid.
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
    dailyRecovery(w);

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
      if (lineup == null ||
          lineup.formation != club.tactic.formation ||
          validateLineup(w, clubId, lineup).isNotEmpty) {
        club.lineup = autoLineup(w, clubId);
      }
    }
  }

  /// The context [f] is played with: the clubs' stored lineups (picked
  /// automatically when missing), the league's rules, conditions sampled
  /// from `SeededRng(seed).fork('conditions:<fixtureId>:<seasonYear>')`,
  /// both clubs' active tactics and the match stream
  /// `SeededRng(seed).fork('match:<fixtureId>:<seasonYear>')`.
  MatchContext contextFor(
    World w,
    Fixture f, {
    MatchDetail detail = MatchDetail.result,
  }) {
    final home = w.clubs[f.homeId]!;
    final away = w.clubs[f.awayId]!;
    return MatchContext(
      world: w,
      fixture: f,
      home: home.lineup ??= autoLineup(w, f.homeId),
      away: away.lineup ??= autoLineup(w, f.awayId),
      rng: SeededRng(w.seed).fork('match:${f.id}:${w.seasonYear}'),
      rules: w.leagues[f.leagueId]!.rules,
      conditions: sampleConditions(
        w: w,
        f: f,
        rng: SeededRng(w.seed).fork('conditions:${f.id}:${w.seasonYear}'),
      ),
      homeTactic: home.tactic,
      awayTactic: away.tactic,
      detail: detail,
    );
  }

  /// Stores [r] as [f]'s result, serves a match of every ban of a player
  /// of either club (seniors and youth) who was in neither the starters
  /// nor the bench of the stored lineup, runs [applyPostMatch] under the
  /// league's rules (bans issued by this match are served from the next
  /// one) and drops a stored lineup the match made invalid (an injured or
  /// banned player in it). Returns a [MatchPlayed] followed by the
  /// post-match events.
  List<GameEvent> settleMatch(World w, Fixture f, MatchResult r) {
    f.result = r;
    for (final clubId in [f.homeId, f.awayId]) {
      final lineup = w.clubs[clubId]!.lineup;
      final named = {...?lineup?.starters, ...?lineup?.bench};
      for (final id in [...w.squadOf(clubId), ...w.youthOf(clubId)]) {
        final state = w.players[id]!.state;
        if (state.suspensionMatches > 0 && !named.contains(id)) {
          state.suspensionMatches--;
        }
      }
    }
    final events = applyPostMatch(w, f, r, w.leagues[f.leagueId]!.rules);
    for (final clubId in [f.homeId, f.awayId]) {
      final club = w.clubs[clubId]!;
      final lineup = club.lineup;
      if (lineup != null && validateLineup(w, clubId, lineup).isNotEmpty) {
        club.lineup = null;
      }
    }
    return [MatchPlayed(date: w.date, fixtureId: f.id), ...events];
  }

  /// Simulates every unplayed fixture dated today, sorted by id, with
  /// [contextFor] and settles each with [settleMatch]. Returns the day
  /// events per fixture, in fixture id order.
  Map<FixtureId, List<GameEvent>> playMatches(World w) {
    final played = <FixtureId, List<GameEvent>>{};
    for (final id in w.fixturesOn(w.date)) {
      final f = w.fixtures[id]!;
      if (f.result != null) continue;
      played[id] = settleMatch(w, f, sim.simulate(contextFor(w, f)));
    }
    return played;
  }

  /// Runs [rollover] on the season's last day, delivers the user-relevant
  /// events of the day ([dayEvents] plus the rollover's) to the inbox,
  /// trims it to [inboxLimit], and moves the world to the next day.
  /// Returns the rollover events.
  ///
  /// Relevance is judged against the league the user's club was in before
  /// the rollover, so a promoted or relegated user gets the champion of
  /// the league the club actually played in.
  List<GameEvent> endOfDay(World w, {List<GameEvent> dayEvents = const []}) {
    final userLeagueId = w.userClub?.leagueId;
    final hook = rollover;
    final rolled = hook != null && w.date == w.calendar.seasonEnd
        ? hook(w, SeededRng(w.seed).fork('rollover:${w.seasonYear}'))
        : <GameEvent>[];

    for (final e in [...dayEvents, ...rolled]) {
      if (isUserRelevant(w, e, userLeagueId: userLeagueId)) {
        w.inbox.add(
          InboxMessage(id: w.ids.next('inbox'), date: w.date, event: e),
        );
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
    final matchEvents = [for (final events in played.values) ...events];
    final rolled = endOfDay(w, dayEvents: matchEvents);
    return DaySummary(
      date: date,
      events: [...matchEvents, ...rolled],
      playedFixtures: played.keys.toList(),
      elapsed: watch.elapsed,
    );
  }
}

/// Whether [e] belongs in the user's inbox: season-level events always;
/// otherwise only events involving the user's club (or, for
/// [LeagueChampion], the user's league: [userLeagueId], defaulting to the
/// club's current league). An unemployed user sees only season-level
/// events.
bool isUserRelevant(World w, GameEvent e, {LeagueId? userLeagueId}) {
  final club = w.userClub;
  return switch (e) {
    SeasonEnded() || NewSeasonStarted() => true,
    _ when club == null => false,
    MatchPlayed(:final fixtureId) =>
      w.fixtures[fixtureId]!.homeId == club.id ||
          w.fixtures[fixtureId]!.awayId == club.id,
    LeagueChampion(:final leagueId, :final clubId) =>
      clubId == club.id || leagueId == (userLeagueId ?? club.leagueId),
    Promoted(:final clubId) => clubId == club.id,
    Relegated(:final clubId) => clubId == club.id,
    PlayerRetired(:final clubId) => clubId == club.id,
    YouthIntake(:final clubId) => clubId == club.id,
    YouthReleased(:final clubId) => clubId == club.id,
    PlayerInjured(:final clubId) => clubId == club.id,
    PlayerSentOff(:final clubId) => clubId == club.id,
    PlayerSuspended(:final clubId) => clubId == club.id,
  };
}
