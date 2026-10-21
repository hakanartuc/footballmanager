/// Messages between [IsolateGateway] and its engine worker. One request
/// per [EngineGateway] method; every request gets exactly one response
/// with the same [EngineRequest.id].
library;

import 'dart:typed_data';

import 'package:engine/engine.dart';

import 'engine_gateway.dart';

sealed class EngineRequest {
  const EngineRequest(this.id);

  final int id;
}

final class NewGameReq extends EngineRequest {
  const NewGameReq(super.id, this.spec);

  final NewGameSpec spec;
}

final class LoadReq extends EngineRequest {
  const LoadReq(super.id, this.bytes);

  final Uint8List bytes;
}

final class SaveReq extends EngineRequest {
  const SaveReq(super.id);
}

final class AdvanceToNextReq extends EngineRequest {
  const AdvanceToNextReq(super.id, this.maxDays);

  final int maxDays;
}

final class PlayTodayReq extends EngineRequest {
  const PlayTodayReq(super.id, this.commands);

  final List<Command> commands;
}

final class RefsReq extends EngineRequest {
  const RefsReq(super.id);
}

final class HomeReq extends EngineRequest {
  const HomeReq(super.id);
}

final class SquadReq extends EngineRequest {
  const SquadReq(super.id, this.clubId, {required this.youth});

  final ClubId clubId;
  final bool youth;
}

final class PlayerReq extends EngineRequest {
  const PlayerReq(super.id, this.playerId);

  final PlayerId playerId;
}

final class LineupReq extends EngineRequest {
  const LineupReq(super.id, this.clubId, {required this.auto});

  final ClubId clubId;
  final bool auto;
}

final class TableReq extends EngineRequest {
  const TableReq(super.id, this.leagueId);

  final LeagueId leagueId;
}

final class ClubFixturesReq extends EngineRequest {
  const ClubFixturesReq(super.id, this.clubId);

  final ClubId clubId;
}

final class InboxReq extends EngineRequest {
  const InboxReq(super.id);
}

final class MarkReadReq extends EngineRequest {
  const MarkReadReq(super.id, this.inboxId);

  final int inboxId;
}

/// Drops the game and ends the worker.
final class ShutdownReq extends EngineRequest {
  const ShutdownReq(super.id);
}

sealed class EngineResponse {
  const EngineResponse(this.id);

  final int id;
}

final class OkRes extends EngineResponse {
  const OkRes(super.id, this.value);

  /// The method's result; null for void methods.
  final Object? value;
}

/// The [GatewayError] the request failed with.
final class FailRes extends EngineResponse {
  const FailRes(super.id, this.kind, this.message);

  final GatewayErrorKind kind;
  final String message;
}
