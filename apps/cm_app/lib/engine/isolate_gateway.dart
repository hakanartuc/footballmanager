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
    return FailRes(req.id, e.kind, e.message, saveKind: e.saveKind);
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
      LineupReq(:final clubId, :final auto) => g.lineup(clubId, auto: auto),
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

  /// [entry] replaces [engineWorkerMain] in tests only.
  static Future<IsolateGateway> spawn({
    @visibleForTesting void Function(SendPort)? entry,
  }) async {
    final fromWorker = ReceivePort();
    final errors = ReceivePort();
    final exit = ReceivePort();
    final isolate = await Isolate.spawn(
      entry ?? engineWorkerMain,
      fromWorker.sendPort,
      onError: errors.sendPort,
      onExit: exit.sendPort,
      errorsAreFatal: true,
      debugName: 'engine',
    );
    final g = IsolateGateway._(isolate, fromWorker, errors, exit);
    final ready = Completer<SendPort>();
    void crash(String message) {
      g._crash(message);
      if (!ready.isCompleted) {
        ready.completeError(GatewayError(GatewayErrorKind.engine, message));
      }
    }

    fromWorker.listen(
      (Object? m) => m is SendPort ? ready.complete(m) : g._onResponse(m),
    );
    errors.listen(
      (Object? e) => crash('engine isolate crashed: ${(e as List).join('\n')}'),
    );
    exit.listen((_) => crash('engine isolate crashed'));
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
  var _portsClosed = false;

  /// True once the worker died from an uncaught error or was killed; every
  /// call fails with `GatewayError(engine)` from then on.
  bool get isBroken => _broken;

  @visibleForTesting
  Isolate get isolate => _isolate;

  @visibleForTesting
  bool get portsClosed => _portsClosed;

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
        try {
          completer.complete(value);
        } on TypeError catch (e) {
          completer.completeError(
            GatewayError(GatewayErrorKind.engine, 'bad response type: $e'),
          );
        }
      case FailRes(:final kind, :final message, :final saveKind):
        completer.completeError(
          GatewayError(kind, message, saveKind: saveKind),
        );
    }
  }

  /// The worker is gone: release its ports and fail everything in flight.
  void _crash(String message) {
    if (_broken) return;
    _broken = true;
    _closePorts();
    _failPending(GatewayError(GatewayErrorKind.engine, message));
  }

  void _closePorts() {
    _fromWorker.close();
    _errors.close();
    _exit.close();
    _portsClosed = true;
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
  Future<LineupView> lineup(ClubId clubId, {bool auto = false}) =>
      _send((id) => LineupReq(id, clubId, auto: auto));

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
    _closePorts();
    if (!_broken) _toWorker.send(ShutdownReq(_nextId++));
    _isolate.kill(priority: Isolate.immediate);
    _failPending(
      const GatewayError(GatewayErrorKind.noGame, 'gateway disposed'),
    );
  }
}
