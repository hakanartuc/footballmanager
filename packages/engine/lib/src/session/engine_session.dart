import 'dart:typed_data';

import '../competition/standings.dart';
import '../core/game_date.dart';
import '../core/ids.dart';
import '../invariants/invariants.dart' as invariants;
import '../model/events.dart';
import '../model/fixture.dart';
import '../model/player.dart';
import '../model/world.dart';
import '../persistence/save_codec.dart';
import '../sim/commands.dart';
import '../sim/day_loop.dart';
import '../sim/match/match_session.dart';
import '../sim/match/possession_match_simulator.dart';
import '../sim/match_simulator.dart';
import '../sim/new_game.dart';
import '../sim/season_rollover.dart';

/// The engine's only entry point for hosts: the Flutter app's isolate and
/// the CLI. Owns one [World] and one [DayRunner] and holds no static state,
/// so any number of sessions can live side by side.
///
/// [sim] defaults to [PossessionMatchSimulator], [codec] to
/// [JsonGzipSaveCodec].
///
/// The user's match can be played interactively: [startUserMatch] begins
/// the day and hands out a [MatchSession] on the user's fixture;
/// [finishUserMatch] takes its result and runs the rest of the day.
/// Without commands to the session (and the AI left on with
/// `userManaged: false`) the pair gives the same world as [advanceDay].
class EngineSession {
  EngineSession._(this._world, MatchSimulator? sim, SaveCodec? codec)
    : _codec = codec ?? const JsonGzipSaveCodec(),
      _runner = DayRunner(
        sim: sim ?? const PossessionMatchSimulator(),
        rollover: rolloverSeason,
      );

  /// A session on the world of [createNewGame].
  EngineSession.newGame(
    NewGameSpec spec, {
    MatchSimulator? sim,
    SaveCodec? codec,
    int startSeasonYear = 2026,
  }) : this._(
         createNewGame(spec, startSeasonYear: startSeasonYear),
         sim,
         codec,
       );

  /// A session on the world decoded from [bytes] by [codec]. Throws
  /// [SaveError] for corrupt or newer-schema bytes.
  EngineSession.fromBytes(
    Uint8List bytes, {
    MatchSimulator? sim,
    SaveCodec? codec,
  }) : this._((codec ?? const JsonGzipSaveCodec()).decode(bytes), sim, codec);

  final World _world;
  final SaveCodec _codec;
  final DayRunner _runner;
  (Fixture, MatchSession)? _userMatch;

  /// The live world. Callers must treat it as read-only; mutate it only
  /// through [advanceDay], [advanceUntil], [startUserMatch],
  /// [finishUserMatch], [markRead] and [markReadById].
  World get world => _world;

  /// Whether a [startUserMatch] awaits its [finishUserMatch].
  bool get userMatchInProgress => _userMatch != null;

  /// Processes the current day with [commands] (see [DayRunner.advanceDay]).
  /// Throws [StateError] while a user match is in progress.
  DaySummary advanceDay([List<Command> commands = const []]) {
    _noUserMatch();
    return _runner.advanceDay(_world, commands);
  }

  /// Starts today as [advanceDay] would (`DayRunner.startOfDay` with
  /// [commands]) and returns a [MatchSession] on the user club's fixture,
  /// built exactly as the day loop builds it (`DayRunner.contextFor`) at
  /// [detail]. With [userManaged] the user's side gets no AI decisions:
  /// the caller steps the session and issues its commands. The world
  /// stays at the state after `startOfDay` (recovery, injury countdown,
  /// lineups) until [finishUserMatch].
  ///
  /// Throws [StateError] unless today is the user's next match day
  /// ([nextUserMatchDate]) and no user match is in progress.
  MatchSession startUserMatch({
    List<Command> commands = const [],
    MatchDetail detail = MatchDetail.events,
    bool userManaged = true,
  }) {
    _noUserMatch();
    final club = _world.userClub;
    if (club == null || nextUserMatchDate() != _world.date) {
      throw StateError('no user match on ${_world.date.iso}');
    }
    _runner.startOfDay(_world, commands);
    final f = _world
        .fixturesOn(_world.date)
        .map((id) => _world.fixtures[id]!)
        .firstWhere((f) => f.homeId == club.id || f.awayId == club.id);
    final session = MatchSession(_runner.contextFor(_world, f, detail: detail));
    if (userManaged) session.setUserManaged(club.id, true);
    _userMatch = (f, session);
    return session;
  }

  /// Finishes the session of [startUserMatch] (`MatchSession.finish`),
  /// settles its fixture, plays the day's other fixtures and ends the day
  /// as [advanceDay] would; the summary lists the day's fixtures in id
  /// order, the user's among them. Throws [StateError] when no user match
  /// is in progress.
  DaySummary finishUserMatch() {
    final (f, session) =
        _userMatch ?? (throw StateError('no user match in progress'));
    final watch = Stopwatch()..start();
    final date = _world.date;
    final Map<FixtureId, List<GameEvent>> played;
    final List<GameEvent> rolled;
    final List<GameEvent> matchEvents;
    final List<FixtureId> ids;
    try {
      played = {
        f.id: _runner.settleMatch(_world, f, session.finish()),
        ..._runner.playMatches(_world),
      };
      ids = played.keys.toList()..sort();
      matchEvents = [for (final id in ids) ...played[id]!];
      rolled = _runner.endOfDay(_world, dayEvents: matchEvents);
    } finally {
      // A failure must not leave the session locked in "match in progress".
      _userMatch = null;
    }
    return DaySummary(
      date: date,
      events: [...matchEvents, ...rolled],
      playedFixtures: ids,
      elapsed: watch.elapsed,
    );
  }

  void _noUserMatch() {
    if (_userMatch != null) throw StateError('a user match is in progress');
  }

  /// Advances day by day while `world.date` is before [date], stopping
  /// early on the morning of a user match day (before it is played, so a
  /// lineup can still be set; the caller plays it with [advanceDay] or
  /// [startUserMatch]) and right after the day whose summary contains a
  /// [SeasonEnded]. Throws [StateError] while a user match is in progress.
  ///
  /// [commands] apply to the first processed day only. When the loop stops
  /// before processing any day (today is already a user match day, or
  /// [date] is not after today) it returns an empty list and [commands]
  /// are dropped without being applied; pass them to [advanceDay] instead.
  /// Returns the summaries of the days processed, in order.
  List<DaySummary> advanceUntil(
    GameDate date, {
    List<Command> commands = const [],
  }) {
    _noUserMatch();
    final out = <DaySummary>[];
    var pending = commands;
    while (_world.date.isBefore(date)) {
      if (nextUserMatchDate() == _world.date) break;
      final summary = advanceDay(pending);
      pending = const [];
      out.add(summary);
      if (summary.events.any((e) => e is SeasonEnded)) break;
    }
    return out;
  }

  /// The date of the user club's earliest unplayed fixture on or after
  /// today in the current season; null when the user is unemployed or the
  /// club has no such fixture.
  GameDate? nextUserMatchDate() {
    final club = _world.userClub;
    if (club == null) return null;
    for (final id in _world.fixturesOfClub(club.id, _world.seasonYear)) {
      final f = _world.fixtures[id]!;
      if (f.result == null && !f.date.isBefore(_world.date)) return f.date;
    }
    return null;
  }

  /// The world encoded by the session's codec. The world is saved only
  /// between days: throws [StateError] while a user match is in progress
  /// (hosts guard their autosave with [userMatchInProgress]), so a quit
  /// mid-match resumes from that morning.
  Uint8List save() {
    _noUserMatch();
    return _codec.encode(_world);
  }

  /// [computeTable] of [l] for the current season.
  List<TableRow> table(LeagueId l) =>
      computeTable(_world, l, _world.seasonYear);

  /// [c]'s fixtures of the current season in date order.
  List<Fixture> clubFixtures(ClubId c) => [
    for (final id in _world.fixturesOfClub(c, _world.seasonYear))
      _world.fixtures[id]!,
  ];

  /// [c]'s senior players, sorted by id.
  List<Player> squad(ClubId c) => [
    for (final id in _world.squadOf(c)) _world.players[id]!,
  ];

  /// [c]'s youth players, sorted by id.
  List<Player> youth(ClubId c) => [
    for (final id in _world.youthOf(c)) _world.players[id]!,
  ];

  /// Inbox messages newest first, optionally only the unread ones.
  List<InboxMessage> inbox({bool unreadOnly = false}) => [
    for (final m in _world.inbox.reversed)
      if (!unreadOnly || !m.read) m,
  ];

  /// Marks [message] read. [inbox] returns the stored instances, so any
  /// message it handed out can be passed here; positions in the stored
  /// list are not stable (it is trimmed from the front daily).
  void markRead(InboxMessage message) => message.read = true;

  /// Marks the message with [id] read; a no-op when no stored message has
  /// it (e.g. it was trimmed). For hosts that hold ids, not instances.
  void markReadById(int id) {
    for (final m in _world.inbox) {
      if (m.id == id) {
        m.read = true;
        return;
      }
    }
  }

  /// Every invariant the world currently breaks.
  List<invariants.Violation> checkInvariants() =>
      invariants.checkInvariants(_world);
}
