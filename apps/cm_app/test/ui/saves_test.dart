import 'dart:typed_data';

import 'package:cm_app/engine/engine_gateway.dart';
import 'package:cm_app/l10n/generated/app_localizations.dart';
import 'package:cm_app/state/game_controller.dart';
import 'package:cm_app/ui/saves/saves_screen.dart';
import 'package:cm_app/ui/shell/game_shell.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_gateway.dart';
import '../support/pump_app.dart';

Future<void> _write(
  MemorySaveStore store,
  int slot,
  String club,
  DateTime savedAt,
) => store.write(
  slot,
  Uint8List(1),
  SlotInfo(
    slot: slot,
    managerName: 'Test Manager',
    clubName: club,
    date: GameDate.ymd(2026, 9, 12),
    seasonYear: 2026,
    savedAt: savedAt,
    bytes: 1,
  ),
);

/// Beta SK in manual slot 2; autosaves of Gamma Spor (slot 7, older) and
/// Delta United (slot 8). Starting a game adds Alpha FC in slot 6, newest.
Future<MemorySaveStore> _store() async {
  final store = MemorySaveStore();
  await _write(store, 2, 'Beta SK', DateTime(2020, 5, 1, 14, 30));
  await _write(store, 7, 'Gamma Spor', DateTime(2020, 1, 1));
  await _write(store, 8, 'Delta United', DateTime(2020, 1, 2));
  return store;
}

Finder _row(String key) => find.byKey(Key(key));

Finder _in(String key, Finder f) => find.descendant(of: _row(key), matching: f);

/// Scrolls [key]'s row into view and taps its [label] button.
Future<void> _tapIn(WidgetTester t, String key, String label) async {
  final button = _in(key, find.text(label));
  await t.scrollUntilVisible(
    button,
    100,
    scrollable: find
        .descendant(
          of: find.byType(SavesScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await t.ensureVisible(button);
  await t.pumpAndSettle();
  await t.tap(button);
  await t.pumpAndSettle();
}

/// The app with a game loaded and the saves screen opened from the shell.
Future<(GameController, FakeGateway)> _open(
  WidgetTester t, {
  Locale locale = const Locale('tr'),
  Size size = const Size(390, 844),
}) async {
  final gateway = FakeGateway.ready();
  final controller = await pumpApp(
    t,
    gateway: gateway,
    store: await _store(),
    locale: locale,
    size: size,
  );
  await t.tap(find.byIcon(Icons.save_outlined));
  await t.pumpAndSettle();
  expect(find.byType(SavesScreen), findsOneWidget);
  gateway.calls.clear();
  return (controller, gateway);
}

void main() {
  late AppLocalizations l;

  setUp(() async => l = await loadL10n());

  testWidgets('the title is Saves from both entry points', (t) async {
    Finder title() => find.descendant(
      of: find.byType(AppBar),
      matching: find.text(l.manualSaves),
    );
    await _open(t);
    expect(title(), findsOneWidget);
    expect(find.text(l.manualSaves), findsOneWidget, reason: 'no header');

    await t.pumpWidget(const SizedBox());
    await pumpApp(t, store: await _store(), startReady: false);
    await t.tap(find.text(l.loadGame));
    await t.pumpAndSettle();
    expect(title(), findsOneWidget);
    expect(find.text(l.loadGame), findsNothing);
  });

  testWidgets('lists five manual slots, empty and occupied', (t) async {
    await _open(t);
    expect(find.text(l.manualSaves), findsOneWidget);
    for (final n in [1, 2, 3, 4, 5]) {
      await t.scrollUntilVisible(
        _row('slot$n'),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(_in('slot$n', find.text(l.slot(n))), findsOneWidget);
      expect(
        _in('slot$n', find.text(l.emptySlot)),
        n == 2 ? findsNothing : findsOneWidget,
      );
    }
    await t.scrollUntilVisible(
      _row('slot2'),
      -100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(_in('slot2', find.textContaining('Beta SK')), findsOneWidget);
    expect(_in('slot2', find.textContaining('2026-27')), findsOneWidget);
    expect(_in('slot2', find.text(l.load)), findsOneWidget);
    expect(_in('slot2', find.text(l.delete)), findsOneWidget);
    expect(_in('slot1', find.text(l.load)), findsNothing);
    expect(_in('slot1', find.text(l.delete)), findsNothing);
    expect(_in('slot1', find.text(l.save)), findsOneWidget);
  });

  testWidgets('save to an empty slot saves and fills the row', (t) async {
    final (_, gateway) = await _open(t);
    await _tapIn(t, 'slot1', l.save);
    expect(gateway.calls, contains('save'));
    expect(find.text(l.saved), findsOneWidget);
    expect(_in('slot1', find.text(l.emptySlot)), findsNothing);
    expect(_in('slot1', find.textContaining('Alpha FC')), findsOneWidget);
  });

  testWidgets('save to an occupied slot asks to overwrite', (t) async {
    final (_, gateway) = await _open(t);
    await _tapIn(t, 'slot2', l.save);
    expect(find.text(l.overwriteConfirm), findsOneWidget);
    await t.tap(find.text(l.cancel));
    await t.pumpAndSettle();
    expect(gateway.calls, isNot(contains('save')));

    await _tapIn(t, 'slot2', l.save);
    await t.tap(find.text(l.ok));
    await t.pumpAndSettle();
    expect(gateway.calls, contains('save'));
    expect(_in('slot2', find.textContaining('Alpha FC')), findsOneWidget);
  });

  testWidgets('load loads the slot and returns to the game', (t) async {
    final (controller, gateway) = await _open(t);
    await _tapIn(t, 'slot2', l.load);
    expect(gateway.calls, contains('load'));
    expect(find.byType(SavesScreen), findsNothing);
    expect(find.byType(GameShell), findsOneWidget);
    expect(controller.state, isA<Ready>());
  });

  testWidgets('a newer-schema save shows the error inline', (t) async {
    final (controller, gateway) = await _open(t);
    gateway.failNext = const GatewayError(
      GatewayErrorKind.save,
      'newer',
      saveKind: SaveErrorKind.newerSchema,
    );
    await _tapIn(t, 'slot2', l.load);
    expect(find.byType(SavesScreen), findsOneWidget);
    expect(_in('slot2', find.text(l.newerSaveError)), findsOneWidget);
    expect(_in('slot2', find.textContaining('Beta SK')), findsOneWidget);
    expect(controller.state, isA<Ready>());
  });

  testWidgets('a corrupt save shows the load error inline', (t) async {
    final (controller, gateway) = await _open(t);
    gateway.failNext = const GatewayError(
      GatewayErrorKind.save,
      'corrupt',
      saveKind: SaveErrorKind.corrupt,
    );
    await _tapIn(t, 'slot2', l.load);
    expect(_in('slot2', find.text(l.loadError)), findsOneWidget);
    expect(_in('slot2', find.textContaining('Beta SK')), findsOneWidget);
    expect(controller.state, isA<Ready>());
  });

  testWidgets('delete asks, then empties the slot', (t) async {
    await _open(t);
    await _tapIn(t, 'slot2', l.delete);
    expect(find.text(l.deleteConfirm), findsOneWidget);
    await t.tap(find.text(l.cancel));
    await t.pumpAndSettle();
    expect(_in('slot2', find.textContaining('Beta SK')), findsOneWidget);

    await _tapIn(t, 'slot2', l.delete);
    await t.tap(find.text(l.ok));
    await t.pumpAndSettle();
    expect(_in('slot2', find.text(l.emptySlot)), findsOneWidget);
    expect(_in('slot2', find.text(l.delete)), findsNothing);
  });

  testWidgets('autosaves are listed newest first with load only', (t) async {
    final (_, gateway) = await _open(t);
    await t.scrollUntilVisible(
      _row('autosave7'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text(l.autosaves), findsOneWidget);
    final ys = [
      for (final n in [6, 8, 7]) t.getTopLeft(_row('autosave$n')).dy,
    ];
    expect(ys[0] < ys[1] && ys[1] < ys[2], isTrue, reason: '$ys');
    expect(
      _in('autosave8', find.textContaining('Delta United')),
      findsOneWidget,
    );
    expect(_in('autosave7', find.text(l.save)), findsNothing);
    expect(_in('autosave7', find.text(l.delete)), findsNothing);

    await _tapIn(t, 'autosave7', l.load);
    expect(gateway.calls, contains('load'));
    expect(find.byType(GameShell), findsOneWidget);
  });

  testWidgets('from the start screen: load and delete, no save', (t) async {
    final gateway = FakeGateway.ready();
    final controller = await pumpApp(
      t,
      gateway: gateway,
      store: await _store(),
      startReady: false,
    );
    await t.tap(find.text(l.loadGame));
    await t.pumpAndSettle();
    expect(find.byType(SavesScreen), findsOneWidget);
    expect(find.text(l.save), findsNothing);
    expect(_in('slot2', find.text(l.delete)), findsOneWidget);

    gateway.failNext = const GatewayError(
      GatewayErrorKind.save,
      'corrupt',
      saveKind: SaveErrorKind.corrupt,
    );
    await _tapIn(t, 'slot2', l.load);
    expect(_in('slot2', find.text(l.loadError)), findsOneWidget);
    expect(controller.state, isA<NoGame>());

    await _tapIn(t, 'slot2', l.load);
    expect(find.byType(GameShell), findsOneWidget);
    expect(controller.state, isA<Ready>());
  });

  testWidgets('no overflow at 360x780', (t) async {
    final en = await loadL10n(const Locale('en'));
    await _open(t, locale: const Locale('en'), size: const Size(360, 780));
    await t.scrollUntilVisible(
      _row('autosave7'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text(en.autosaves), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
