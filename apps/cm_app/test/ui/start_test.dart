import 'dart:typed_data';

import 'package:cm_app/data/game_repository.dart';
import 'package:cm_app/l10n/generated/app_localizations.dart';
import 'package:cm_app/state/game_controller.dart';
import 'package:cm_app/ui/start/new_game_screen.dart';
import 'package:cm_app/ui/start/start_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/fake_gateway.dart';
import '../support/pump_app.dart';

/// A store holding an autosave of Alpha FC in slot 6.
Future<MemorySaveStore> _storeWithAutosave() async {
  final store = MemorySaveStore();
  await store.write(
    6,
    Uint8List.fromList([1]),
    SlotInfo(
      slot: 6,
      managerName: 'Test Manager',
      clubName: 'Alpha FC',
      date: GameDate.ymd(2026, 7, 1),
      seasonYear: 2026,
      savedAt: DateTime.utc(2026, 10, 1),
      bytes: 1,
    ),
  );
  return store;
}

FilledButton _continueButton(WidgetTester t, AppLocalizations l) => t.widget(
  find.ancestor(
    of: find.text(l.continueGame),
    matching: find.byType(FilledButton),
  ),
);

/// [StartScreen] alone, to control [StartScreen.onLoadGame].
Future<void> _pumpStart(WidgetTester t, {VoidCallback? onLoadGame}) async {
  final gateway = FakeGateway.ready();
  await t.pumpWidget(
    ChangeNotifierProvider(
      create: (_) =>
          GameController(GameRepository(gateway, MemorySaveStore()), gateway),
      child: MaterialApp(
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: StartScreen(onLoadGame: onLoadGame),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('NoGame shows the start screen; continue disabled when empty', (
    t,
  ) async {
    final l = await loadL10n();
    await pumpApp(t, startReady: false);
    expect(find.byType(StartScreen), findsOneWidget);
    expect(find.text(l.continueGame), findsOneWidget);
    expect(find.text(l.newGame), findsOneWidget);
    expect(find.text(l.noSavedGame), findsOneWidget);
    expect(find.text(l.loadGame), findsOneWidget);
    expect(_continueButton(t, l).onPressed, isNull);
  });

  testWidgets('load button shows only with onLoadGame and calls it', (t) async {
    final l = await loadL10n();
    await _pumpStart(t);
    expect(find.text(l.loadGame), findsNothing);
    var loads = 0;
    await _pumpStart(t, onLoadGame: () => loads++);
    await t.tap(find.text(l.loadGame));
    expect(loads, 1);
  });

  testWidgets('an autosave enables continue, which loads it', (t) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    await pumpApp(
      t,
      gateway: g,
      store: await _storeWithAutosave(),
      startReady: false,
    );
    expect(_continueButton(t, l).onPressed, isNotNull);
    expect(find.textContaining('Alpha FC'), findsOneWidget);
    expect(find.text(l.noSavedGame), findsNothing);
    await t.tap(find.text(l.continueGame));
    await t.pumpAndSettle();
    expect(g.calls, contains('load'));
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('new game opens the new game screen', (t) async {
    final l = await loadL10n();
    await pumpApp(t, startReady: false);
    await t.tap(find.text(l.newGame));
    await t.pumpAndSettle();
    expect(find.byType(NewGameScreen), findsOneWidget);
  });

  testWidgets('EN labels', (t) async {
    final l = await loadL10n(const Locale('en'));
    await pumpApp(t, startReady: false, locale: const Locale('en'));
    expect(find.text(l.continueGame), findsOneWidget);
    expect(find.text(l.newGame), findsOneWidget);
    expect(find.text(l.noSavedGame), findsOneWidget);
  });

  testWidgets('no overflow at 360x780', (t) async {
    await pumpApp(
      t,
      store: await _storeWithAutosave(),
      startReady: false,
      size: const Size(360, 780),
    );
    expect(t.takeException(), isNull);
  });
}
