import 'package:cm_app/app.dart';
import 'package:cm_app/data/entitlements.dart';
import 'package:cm_app/data/settings_controller.dart';
import 'package:cm_app/l10n/generated/app_localizations.dart';
import 'package:cm_app/state/game_controller.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_gateway.dart';

Future<AppLocalizations> loadL10n([Locale locale = const Locale('tr')]) =>
    AppLocalizations.delegate.load(locale);

/// Any spec; [FakeGateway.newGame] only records the call.
final anySpec = NewGameSpec(
  seed: 1,
  size: WorldSize.small,
  managerFirstName: 'Test',
  managerLastName: 'Manager',
  managerCountryCode: 'TR',
  startClubId: 1,
);

/// Pumps [CmApp] on [gateway] (default [FakeGateway.ready]) at [size] and
/// returns its [GameController], driven to `Ready` when [startReady].
Future<GameController> pumpApp(
  WidgetTester t, {
  FakeGateway? gateway,
  SaveStore? store,
  Locale locale = const Locale('tr'),
  Size size = const Size(390, 844),
  bool startReady = true,
  Entitlements entitlements = Entitlements.dev,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  SharedPreferences.setMockInitialValues({});
  await t.pumpWidget(
    CmApp(
      gateway: gateway ?? FakeGateway.ready(),
      store: store ?? MemorySaveStore(),
      settings: SettingsController(),
      locale: locale,
      entitlements: entitlements,
    ),
  );
  await t.pumpAndSettle();
  final controller = Provider.of<GameController>(
    t.element(find.byType(Navigator)),
    listen: false,
  );
  if (startReady) {
    await controller.newGame(anySpec);
    await t.pumpAndSettle();
  }
  return controller;
}
