import 'dart:typed_data';

import 'package:engine/engine.dart';

import 'snapshots.dart';

enum GatewayErrorKind {
  /// No game is loaded.
  noGame,

  /// Bad save bytes (an engine `SaveError`).
  save,

  /// Anything else the engine threw.
  engine,
}

/// The only exception a gateway method's future fails with.
class GatewayError implements Exception {
  const GatewayError(this.kind, this.message);

  final GatewayErrorKind kind;
  final String message;

  @override
  String toString() => 'GatewayError(${kind.name}): $message';
}

/// The UI's only door to the engine. Every method fails with a
/// [GatewayError]; all but [newGame], [load] and [dispose] need a game.
abstract interface class EngineGateway {
  /// Starts a new game, replacing any loaded one.
  Future<void> newGame(NewGameSpec spec);

  /// Loads a game from save bytes, replacing any loaded one.
  Future<void> load(Uint8List bytes);

  Future<Uint8List> save();

  /// Advances up to [maxDays] days, stopping on the morning of a user match
  /// day ([StopReason.matchDay]) or after the season's last day
  /// ([StopReason.seasonEnded]); otherwise [StopReason.reachedLimit].
  /// Returns at once with [StopReason.matchDay] when today already is one.
  Future<AdvanceOutcome> advanceToNext({int maxDays = 90});

  /// Processes today with [commands] (reason [StopReason.played]), with
  /// the user's fixture of the day in [AdvanceOutcome.userMatch].
  Future<AdvanceOutcome> playToday(List<Command> commands);

  Future<WorldRefs> refs();

  Future<HomeSnapshot> home();

  /// [clubId]'s seniors, or its youth squad with [youth].
  Future<List<SquadRow>> squad(ClubId clubId, {bool youth = false});

  Future<PlayerDetail> player(PlayerId id);

  /// The club's stored lineup with its validation errors, or the auto
  /// lineup (no errors) when none is stored.
  Future<LineupView> lineup(ClubId clubId);

  Future<List<TableRowView>> table(LeagueId leagueId);

  /// [clubId]'s fixtures of the current season in date order.
  Future<List<FixtureRow>> clubFixtures(ClubId clubId);

  /// Newest first.
  Future<List<InboxItem>> inbox();

  Future<void> markRead(int inboxId);

  /// Drops the game. The gateway is unusable afterwards.
  Future<void> dispose();
}
