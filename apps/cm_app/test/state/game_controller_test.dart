import 'package:cm_app/data/game_repository.dart';
import 'package:cm_app/engine/engine_gateway.dart';
import 'package:cm_app/engine/snapshots.dart';
import 'package:cm_app/state/game_controller.dart';
import 'package:engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_gateway.dart';
import '../support/pump_app.dart';

void main() {
  late FakeGateway gateway;
  late MemorySaveStore store;
  late GameController c;
  late List<GameState> states;

  setUp(() {
    gateway = FakeGateway.ready();
    store = MemorySaveStore();
    c = GameController(GameRepository(gateway, store), gateway);
    states = [];
    c.addListener(() => states.add(c.state));
  });

  const boom = GatewayError(GatewayErrorKind.engine, 'boom');

  test('newGame goes NoGame -> Busy -> Ready', () async {
    expect(c.state, isA<NoGame>());
    await c.newGame(anySpec);
    expect(states.first, isA<Busy>());
    final ready = c.state as Ready;
    expect(ready.home, same(gateway.homeSnapshot));
    expect(ready.refs, same(gateway.refsSnapshot));
    expect(gateway.calls, contains('newGame'));
  });

  test('advance autosaves once and measures lastAdvanceMs', () async {
    await c.newGame(anySpec);
    final before = (await store.list()).length;
    final outcome = await c.advance();
    expect(outcome!.reason, StopReason.reachedLimit);
    expect((await store.list()).length, before + 1);
    expect(gateway.calls.where((m) => m == 'advanceToNext'), hasLength(1));
    expect(c.lastAdvanceMs, greaterThanOrEqualTo(0));
    expect(c.state, isA<Ready>());
  });

  test('a gateway failure yields Failed keeping the Ready previous', () async {
    await c.newGame(anySpec);
    gateway.failNext = boom;
    final outcome = await c.advance();
    expect(outcome, isNull);
    final failed = c.state as Failed;
    expect(failed.error, same(boom));
    expect(failed.previous, isA<Ready>());
  });

  test('a SaveError is wrapped as GatewayError(save)', () async {
    await c.loadSlot(3);
    final failed = c.state as Failed;
    expect(failed.error.kind, GatewayErrorKind.save);
    expect(failed.previous, isA<NoGame>());
  });

  test('retry re-runs the last action', () async {
    await c.newGame(anySpec);
    gateway.failNext = boom;
    await c.advance();
    expect(c.state, isA<Failed>());
    await c.retry();
    expect(gateway.calls.where((m) => m == 'advanceToNext'), hasLength(2));
    expect(c.state, isA<Ready>());
  });

  test('continueLast without autosaves stays NoGame', () async {
    await c.continueLast();
    expect(c.state, isA<NoGame>());
  });

  test('playMatch sends SetLineup for pendingLineup and clears it', () async {
    await c.newGame(anySpec);
    final lineup = Lineup(
      formation: Formation.f442,
      starters: List.generate(11, (i) => i + 1),
      bench: const [],
    );
    c.pendingLineup = lineup;
    const extra = ClearLineup(clubId: 2);
    await c.playMatch([extra]);
    final sent = gateway.playTodayCommands.single;
    expect(sent, hasLength(2));
    final set = sent.first as SetLineup;
    expect(set.clubId, 1);
    expect(set.lineup, same(lineup));
    expect(sent.last, same(extra));
    expect(c.pendingLineup, isNull);

    await c.playMatch(const []);
    expect(gateway.playTodayCommands.last, isEmpty);
  });

  test('actions throw StateError while busy', () async {
    await c.newGame(anySpec);
    final first = c.advance();
    expect(c.state, isA<Busy>());
    expect(() => c.advance(), throwsStateError);
    await first;
  });

  test(
    'saveToSlot writes the slot, measures lastSaveMs, stays Ready',
    () async {
      await c.newGame(anySpec);
      await c.saveToSlot(2);
      expect((await store.list()).map((s) => s.slot), contains(2));
      expect(c.lastSaveMs, greaterThanOrEqualTo(0));
      expect(c.state, isA<Ready>());
    },
  );

  test('markRead calls the gateway and refreshes home', () async {
    await c.newGame(anySpec);
    gateway.calls.clear();
    await c.markRead(2);
    expect(gateway.calls, ['markRead', 'home']);
  });
}
