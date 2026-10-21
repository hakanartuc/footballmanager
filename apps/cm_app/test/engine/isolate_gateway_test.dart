import 'dart:isolate';
import 'dart:typed_data';

import 'package:cm_app/engine/engine_gateway.dart';
import 'package:cm_app/engine/isolate_gateway.dart';
import 'package:cm_app/engine/isolate_protocol.dart';
import 'package:engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/gateway_contract.dart';

NewGameSpec _spec({WorldSize size = WorldSize.small}) => NewGameSpec(
  seed: 1,
  size: size,
  managerFirstName: 'Test',
  managerLastName: 'Manager',
  managerCountryCode: 'TR',
  startClubId: null,
);

Matcher _fails(GatewayErrorKind kind) =>
    throwsA(isA<GatewayError>().having((e) => e.kind, 'kind', kind));

/// A worker that dies before sending its port.
void _crashingWorker(SendPort toMain) => throw StateError('boom');

/// A worker that answers every request with a value of the wrong type.
void _wrongTypeWorker(SendPort toMain) {
  final port = ReceivePort();
  toMain.send(port.sendPort);
  port.listen((Object? m) => toMain.send(OkRes((m as EngineRequest).id, 42)));
}

void main() {
  group('contract', () {
    runGatewayContract(IsolateGateway.spawn);
  });

  late IsolateGateway g;

  setUp(() async {
    g = await IsolateGateway.spawn();
    addTearDown(g.dispose);
  });

  test(
    'two concurrent home() calls both resolve to the same snapshot',
    () async {
      await g.newGame(_spec());
      final (a, b) = await (g.home(), g.home()).wait;
      expect(a.date, b.date);
      expect(a.seasonYear, b.seasonYear);
      expect(a.managerName, b.managerName);
      expect(a.unreadCount, b.unreadCount);
    },
  );

  test('load(garbage) fails with save and the worker keeps serving', () async {
    await g.newGame(_spec());
    await expectLater(
      g.load(Uint8List.fromList([1, 2, 3])),
      _fails(GatewayErrorKind.save),
    );
    expect((await g.refs()).countries, isNotEmpty);
  });

  test('newGame(large) completes in under 10 s', () async {
    final sw = Stopwatch()..start();
    await g.newGame(_spec(size: WorldSize.large));
    sw.stop();
    printOnFailure('newGame(large) took ${sw.elapsedMilliseconds} ms');
    expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
    expect((await g.refs()).countries, hasLength(WorldSize.large.countryCount));
  });

  test('dispose() twice is fine; calls afterwards fail with noGame', () async {
    await g.newGame(_spec());
    await g.dispose();
    await g.dispose();
    await expectLater(g.refs(), _fails(GatewayErrorKind.noGame));
  });

  test('a dead worker fails the pending call and all later ones', () async {
    await g.newGame(_spec());
    // Kill before sending so the request is still pending when the exit
    // notification arrives; the ordering is deterministic either way.
    g.isolate.kill(priority: Isolate.immediate);
    final pending = g.home();
    await expectLater(pending, _fails(GatewayErrorKind.engine));
    expect(g.isBroken, isTrue);
    expect(g.portsClosed, isTrue);
    await expectLater(g.refs(), _fails(GatewayErrorKind.engine));
    await g.dispose();
    await expectLater(g.refs(), _fails(GatewayErrorKind.noGame));
  });

  test('spawn() fails instead of hanging when the worker dies early', () async {
    await expectLater(
      IsolateGateway.spawn(
        entry: _crashingWorker,
      ).timeout(const Duration(seconds: 5)),
      _fails(GatewayErrorKind.engine),
    );
  });

  test('a response of the wrong type fails the call', () async {
    final g2 = await IsolateGateway.spawn(entry: _wrongTypeWorker);
    addTearDown(g2.dispose);
    await expectLater(
      g2.home().timeout(const Duration(seconds: 5)),
      _fails(GatewayErrorKind.engine),
    );
  });
}
