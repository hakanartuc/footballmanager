import 'dart:async';
import 'dart:typed_data';

import 'package:cm_app/data/game_repository.dart';
import 'package:cm_app/engine/engine_gateway.dart';
import 'package:cm_app/engine/snapshots.dart';
import 'package:cm_app/state/game_controller.dart';
import 'package:engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_gateway.dart';
import '../support/pump_app.dart';

/// Throws [SaveError] `io` on the next [write] when [failNextWrite].
class _FlakyStore extends MemorySaveStore {
  bool failNextWrite = false;

  @override
  Future<void> write(int slot, Uint8List bytes, SlotInfo meta) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw SaveError(SaveErrorKind.io, 'disk full');
    }
    await super.write(slot, bytes, meta);
  }
}

void main() {
  late FakeGateway gateway;
  late _FlakyStore store;
  late GameController c;
  late List<GameState> states;

  setUp(() {
    gateway = FakeGateway.ready();
    store = _FlakyStore();
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

  test(
    'previewWorld returns refs, stays NoGame and does not autosave',
    () async {
      final refs = await c.previewWorld(anySpec);
      expect(refs, same(gateway.refsSnapshot));
      expect(states.first, isA<Busy>());
      expect(c.state, isA<NoGame>());
      expect(gateway.lastSpec!.startClubId, isNull);
      expect(gateway.calls, ['newGame', 'refs']);
      expect(await store.list(), isEmpty);
    },
  );

  test('previewWorld needs NoGame', () async {
    await c.newGame(anySpec);
    expect(() => c.previewWorld(anySpec), throwsStateError);
  });

  test('a failed previewWorld returns null and retry does nothing', () async {
    gateway.failNext = boom;
    expect(await c.previewWorld(anySpec), isNull);
    expect((c.state as Failed).previous, isA<NoGame>());
    gateway.calls.clear();
    expect(await c.retry(), isNull);
    expect(gateway.calls, isEmpty);
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
    expect(failed.error.saveKind, SaveErrorKind.missingSlot);
    expect(failed.previous, isA<NoGame>());
  });

  test('manualSlots, autosaves and deleteSlot pass through', () async {
    await c.newGame(anySpec); // autosave in slot 6
    await c.saveToSlot(2);
    expect((await c.manualSlots()).map((s) => s.slot), [2]);
    expect((await c.autosaves()).map((s) => s.slot), [6]);
    states.clear();
    await c.deleteSlot(2);
    expect(await c.manualSlots(), isEmpty);
    expect(states, isEmpty, reason: 'deleteSlot is not a game action');
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

  test('starting, loading or previewing a game drops pendingLineup', () async {
    final lineup = Lineup(
      formation: Formation.f442,
      starters: List.generate(11, (i) => i + 1),
      bench: const [],
    );
    c.pendingLineup = lineup;
    await c.previewWorld(anySpec);
    expect(c.pendingLineup, isNull, reason: 'previewWorld');
    c.pendingLineup = lineup;
    await c.newGame(anySpec); // autosave in slot 6
    expect(c.pendingLineup, isNull, reason: 'newGame');
    c.pendingLineup = lineup;
    await c.loadSlot(6);
    expect(c.pendingLineup, isNull, reason: 'loadSlot');
    c.pendingLineup = lineup;
    await c.continueLast();
    expect(c.pendingLineup, isNull, reason: 'continueLast');
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

  test('markRead decrements the unread count', () async {
    await c.newGame(anySpec);
    expect((c.state as Ready).home.unreadCount, 2);
    await c.markRead(2);
    expect((c.state as Ready).home.unreadCount, 1);
    expect((await c.inbox()).map((i) => i.read), [true, false]);
  });

  test(
    'a non-busy action ending during a busy one leaves Busy to it',
    () async {
      await c.newGame(anySpec);
      // Every gateway call waits for `hold`; swapping it releases the calls
      // waiting so far and holds the next ones.
      Future<void> release() async {
        final held = gateway.hold!;
        gateway.hold = Completer();
        held.complete();
        await pumpEventQueue();
      }

      gateway.hold = Completer();
      final read = c.markRead(2); // markRead waits
      final adv = c.advance(); // advanceToNext waits
      expect(c.state, isA<Busy>());
      await release(); // markRead: home waits; advance: save waits
      await release(); // markRead ends; advance: home waits
      await read;
      expect(c.state, isA<Busy>(), reason: 'advance is still running');
      gateway.hold!.complete();
      gateway.hold = null;
      await adv;
      final ready = c.state as Ready;
      expect(ready.home.unreadCount, 1, reason: 'refreshed by advance');
    },
  );

  test('dismissError returns to previous without a gateway call', () async {
    await c.newGame(anySpec);
    gateway.failNext = boom;
    await c.advance();
    gateway.calls.clear();
    c.dismissError();
    expect(c.state, isA<Ready>());
    expect(gateway.calls, isEmpty);
  });

  test('retry returns the outcome of a retried advance', () async {
    await c.newGame(anySpec);
    gateway.failNext = boom;
    await c.advance();
    final outcome = await c.retry();
    expect(outcome!.reason, StopReason.reachedLimit);
  });

  test('autosave failure after advance keeps the new home and retry only '
      'saves', () async {
    await c.newGame(anySpec);
    final after = copyHome(
      gateway.homeSnapshot,
      date: gateway.homeSnapshot.date.addDays(1),
    );
    gateway.homeSnapshot = after;
    store.failNextWrite = true;
    await c.advance();
    final failed = c.state as Failed;
    expect(failed.error.kind, GatewayErrorKind.save);
    expect((failed.previous as Ready).home, same(after));

    gateway.calls.clear();
    await c.retry();
    expect(gateway.calls, contains('save'));
    expect(gateway.calls, isNot(contains('advanceToNext')));
    expect(c.state, isA<Ready>());
  });

  test('autosave failure after playMatch does not replay the day', () async {
    await c.newGame(anySpec);
    c.pendingLineup = Lineup(
      formation: Formation.f442,
      starters: List.generate(11, (i) => i + 1),
      bench: const [],
    );
    store.failNextWrite = true;
    await c.playMatch(const []);
    expect(c.state, isA<Failed>());
    expect(c.pendingLineup, isNull);

    gateway.calls.clear();
    await c.retry();
    expect(gateway.calls, contains('save'));
    expect(gateway.playTodayCommands, hasLength(1));
    expect(c.state, isA<Ready>());
  });
}
