import 'dart:io';

import 'package:cm_app/app.dart';
import 'package:cm_app/data/app_save_store.dart';
import 'package:cm_app/l10n/generated/app_localizations.dart';
import 'package:cm_app/state/game_controller.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The integration tests drive the real app (real IsolateGateway, real file
// store in a temp dir) through the UI, so unlike `test/support` they cannot
// use the fake gateway. `pumpAndSettle` does not work while the engine
// works either (the busy spinner keeps scheduling frames), so `waitFor` /
// `waitUntil` poll with bounded `pump`s instead.

Future<AppLocalizations> loadL10n([Locale locale = const Locale('tr')]) =>
    AppLocalizations.delegate.load(locale);

/// A fresh saves directory, deleted after the test.
Future<SaveStore> tempStore() async {
  final dir = await Directory.systemTemp.createTemp('cm_it_');
  addTearDown(() => dir.delete(recursive: true));
  return AppSaveStore.open(root: dir);
}

/// Pumps a fresh [CmApp] over [store] (a new key, so a second call replaces
/// the previous tree and disposes its gateway) and waits for the start
/// screen, which shows once the gateway isolate is up.
Future<void> pumpFreshApp(
  WidgetTester t,
  AppLocalizations l,
  SaveStore store,
) async {
  SharedPreferences.setMockInitialValues({});
  await t.pumpWidget(
    CmApp(key: UniqueKey(), locale: const Locale('tr'), store: store),
  );
  await waitFor(t, find.text(l.newGame));
}

GameController controllerOf(WidgetTester t) => Provider.of<GameController>(
  t.element(find.byType(Navigator).first),
  listen: false,
);

/// Pumps until [finder] matches; fails after [timeout].
Future<void> waitFor(
  WidgetTester t,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) => waitUntil(
  t,
  () => finder.evaluate().isNotEmpty,
  timeout: timeout,
  what: '$finder',
);

/// Pumps until [condition] holds; fails after [timeout].
Future<void> waitUntil(
  WidgetTester t,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
  String what = 'condition',
}) async {
  final sw = Stopwatch()..start();
  while (!condition()) {
    if (sw.elapsed > timeout) {
      fail('Timed out after $timeout waiting for $what');
    }
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// Pumps until the controller leaves [Busy] (not [Failed]), then settles.
Future<void> waitIdle(
  WidgetTester t, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final c = controllerOf(t);
  await waitUntil(t, () => c.state is! Busy, timeout: timeout, what: 'idle');
  expect(c.state, isNot(isA<Failed>()), reason: 'action failed');
  await t.pumpAndSettle();
}

void step(String message) => debugPrint('[it] $message');
