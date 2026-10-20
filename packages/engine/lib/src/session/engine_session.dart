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
import '../sim/match_simulator.dart';
import '../sim/new_game.dart';
import '../sim/poisson_match.dart';
import '../sim/season_rollover.dart';

/// The engine's only entry point for hosts: the Flutter app's isolate and
/// the CLI. Owns one [World] and one [DayRunner] and holds no static state,
/// so any number of sessions can live side by side.
///
/// [sim] defaults to [PoissonMatchSimulator], [codec] to [JsonGzipSaveCodec].
class EngineSession {
  EngineSession._(this._world, MatchSimulator? sim, SaveCodec? codec)
    : _codec = codec ?? const JsonGzipSaveCodec(),
      _runner = DayRunner(
        sim ?? const PoissonMatchSimulator(),
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

  /// The live world. Callers must treat it as read-only; mutate it only
  /// through [advanceDay], [advanceUntil] and [markRead].
  World get world => _world;

  /// Processes the current day with [commands] (see [DayRunner.advanceDay]).
  DaySummary advanceDay([List<Command> commands = const []]) =>
      _runner.advanceDay(_world, commands);

  /// Advances day by day while `world.date` is before [date], stopping
  /// early on the morning of a user match day (before it is played, so a
  /// lineup can still be set; the caller plays it with [advanceDay]) and
  /// right after the day whose summary contains a [SeasonEnded].
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

  /// The world encoded by the session's codec.
  Uint8List save() => _codec.encode(_world);

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

  /// Every invariant the world currently breaks.
  List<invariants.Violation> checkInvariants() =>
      invariants.checkInvariants(_world);
}
