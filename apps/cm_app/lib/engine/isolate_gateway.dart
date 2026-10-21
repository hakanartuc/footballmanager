import 'dart:async';
import 'dart:isolate';

import 'package:engine/engine.dart';
import 'package:flutter/foundation.dart';

import 'engine_gateway.dart';
import 'in_process_gateway.dart';
import 'isolate_protocol.dart';
import 'snapshots.dart';

/// Entry point of the engine isolate: sends its [SendPort] to [toMain] as
/// the first message, then answers one [EngineRequest] at a time, in
/// arrival order, until a [ShutdownReq].
Future<void> engineWorkerMain(SendPort toMain) async {
  final port = ReceivePort();
  toMain.send(port.sendPort);
  final gateway = InProcessGateway();
  await for (final Object? message in port) {
    final request = message as EngineRequest;
    toMain.send(await _serve(gateway, request));
    if (request is ShutdownReq) break;
  }
  port.close();
}

Future<EngineResponse> _serve(InProcessGateway g, EngineRequest req) async {
  try {
    return OkRes(req.id, await _dispatch(g, req));
  } on GatewayError catch (e) {
    return FailRes(req.id, e.kind, e.message);
  } catch (e, stack) {
    return FailRes(req.id, GatewayErrorKind.engine, '$e\n$stack');
  }
}

Future<Object?> _dispatch(InProcessGateway g, EngineRequest req) =>
    switch (req) {
      NewGameReq(:final spec) => g.newGame(spec),
      LoadReq(:final bytes) => g.load(bytes),
      SaveReq() => g.save(),
      AdvanceToNextReq(:final maxDays) => g.advanceToNext(maxDays: maxDays),
      PlayTodayReq(:final commands) => g.playToday(commands),
      RefsReq() => g.refs(),
      HomeReq() => g.home(),
      SquadReq(:final clubId, :final youth) => g.squad(clubId, youth: youth),
      PlayerReq(:final playerId) => g.player(playerId),
      LineupReq(:final clubId) => g.lineup(clubId),
      TableReq(:final leagueId) => g.table(leagueId),
      ClubFixturesReq(:final clubId) => g.clubFixtures(clubId),
      InboxReq() => g.inbox(),
      MarkReadReq(:final inboxId) => g.markRead(inboxId),
      ShutdownReq() => g.dispose(),
    };

/// An [EngineGateway] whose engine runs on its own isolate, so the UI
/// isolate never blocks on a simulation.
///
/// Requests may overlap; the worker serves them in arrival order and each
/// future completes with its own response. There are no timeouts.
class IsolateGateway implements EngineGateway {
  IsolateGateway._(this._isolate, this._fromWorker, this._errors, this._exit);

  static Future<IsolateGateway> spawn() async {
    final fromWorker = ReceivePort();
    final errors = ReceivePort();
    final exit = ReceivePort();
    final isolate = await Isolate.spawn(
      engineWorkerMain,
      fromWorker.sendPort,
      onError: errors.sendPort,
      onExit: exit.sendPort,
      errorsAreFatal: true,
      debugName: 'engine',
    );
    final g = IsolateGateway._(isolate, fromWorker, errors, exit);
    final ready = Completer<SendPort>();
    fromWorker.listen(
      (Object? m) => m is SendPort ? ready.complete(m) : g._onResponse(m),
    );
    errors.listen(
      (Object? e) =>
          g._crash('engine isolate crashed: ${(e as List).join('\n')}'),
    );
    exit.listen((_) => g._crash('engine isolate crashed'));
    g._toWorker = await ready.future;
    return g;
  }

  final Isolate _isolate;
  final ReceivePort _fromWorker;
  final ReceivePort _errors;
  final ReceivePort _exit;
  late final SendPort _toWorker;
  final _pending = <int, Completer<Object?>>{};
  var _nextId = 0;
  var _broken = false;
  var _disposed = false;

  /// True once the worker died from an uncaught error or was killed; every
  /// call fails with `GatewayError(engine)` from then on.
  bool get isBroken => _broken;

  @visibleForTesting
  Isolate get isolate => _isolate;

  Future<T> _send<T>(EngineRequest Function(int id) make) async {
    if (_disposed) {
      throw const GatewayError(GatewayErrorKind.noGame, 'gateway disposed');
    }
    if (_broken) {
      throw const GatewayError(
        GatewayErrorKind.engine,
        'engine isolate crashed',
      );
    }
    final id = _nextId++;
    final completer = Completer<T>();
    _pending[id] = completer;
    _toWorker.send(make(id));
    return completer.future;
  }

  void _onResponse(Object? message) {
    final response = message as EngineResponse;
    final completer = _pending.remove(response.id);
    if (completer == null) return;
    switch (response) {
      case OkRes(:final value):
        completer.complete(value);
      case FailRes(:final kind, :final message):
        completer.completeError(GatewayError(kind, message));
    }
  }

  void _crash(String message) {
    if (_broken) return;
    _broken = true;
    _failPending(GatewayError(GatewayErrorKind.engine, message));
  }

  void _failPending(GatewayError error) {
    final pending = _pending.values.toList();
    _pending.clear();
    for (final c in pending) {
      c.completeError(error);
    }
  }

  @override
  Future<void> newGame(NewGameSpec spec) => _send((id) => NewGameReq(id, spec));

  @override
  Future<void> load(Uint8List bytes) => _send((id) => LoadReq(id, bytes));

  @override
  Future<Uint8List> save() => _send(SaveReq.new);

  @override
  Future<AdvanceOutcome> advanceToNext({int maxDays = 90}) =>
      _send((id) => AdvanceToNextReq(id, maxDays));

  @override
  Future<AdvanceOutcome> playToday(List<Command> commands) =>
      _send((id) => PlayTodayReq(id, commands));

  @override
  Future<WorldRefs> refs() => _send(RefsReq.new);

  @override
  Future<HomeSnapshot> home() => _send(HomeReq.new);

  @override
  Future<List<SquadRow>> squad(ClubId clubId, {bool youth = false}) =>
      _send((id) => SquadReq(id, clubId, youth: youth));

  @override
  Future<PlayerDetail> player(PlayerId id) =>
      _send((reqId) => PlayerReq(reqId, id));

  @override
  Future<LineupView> lineup(ClubId clubId) =>
      _send((id) => LineupReq(id, clubId));

  @override
  Future<List<TableRowView>> table(LeagueId leagueId) =>
      _send((id) => TableReq(id, leagueId));

  @override
  Future<List<FixtureRow>> clubFixtures(ClubId clubId) =>
      _send((id) => ClubFixturesReq(id, clubId));

  @override
  Future<List<InboxItem>> inbox() => _send(InboxReq.new);

  @override
  Future<void> markRead(int inboxId) => _send((id) => MarkReadReq(id, inboxId));

  /// Stops the worker. Pending calls fail with `GatewayError(noGame)`, as
  /// do all later ones. Idempotent.
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _fromWorker.close();
    _errors.close();
    _exit.close();
    if (!_broken) _toWorker.send(ShutdownReq(_nextId++));
    _isolate.kill(priority: Isolate.immediate);
    _failPending(
      const GatewayError(GatewayErrorKind.noGame, 'gateway disposed'),
    );
  }
}
