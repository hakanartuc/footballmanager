import 'package:cm_app/data/entitlements.dart';
import 'package:cm_app/l10n/generated/app_localizations.dart';
import 'package:cm_app/state/game_controller.dart';
import 'package:cm_app/ui/start/new_game_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_gateway.dart';
import '../support/pump_app.dart';

/// Pumps the app with no game and opens the new game screen.
Future<GameController> _open(
  WidgetTester t, {
  FakeGateway? gateway,
  Locale locale = const Locale('tr'),
  Entitlements entitlements = Entitlements.dev,
  Size size = const Size(390, 844),
}) async {
  final l = await loadL10n(locale);
  final c = await pumpApp(
    t,
    gateway: gateway,
    locale: locale,
    entitlements: entitlements,
    size: size,
    startReady: false,
  );
  await t.tap(find.text(l.newGame));
  await t.pumpAndSettle();
  return c;
}

Future<void> _enterNames(WidgetTester t) async {
  await t.enterText(find.byKey(const Key('firstName')), 'Hakan');
  await t.enterText(find.byKey(const Key('lastName')), 'Artuc');
}

Future<void> _tapStart(WidgetTester t, AppLocalizations l) async {
  await t.ensureVisible(find.text(l.startGame));
  await t.tap(find.text(l.startGame));
  await t.pumpAndSettle();
}

Future<void> _selectSize(WidgetTester t, String label) async {
  await t.tap(find.text(label));
  await t.pumpAndSettle();
}

/// Taps the option [text] in the open bottom sheet.
Future<void> _pickInSheet(WidgetTester t, String text) async {
  await t.tap(
    find.descendant(of: find.byType(BottomSheet), matching: find.text(text)),
  );
  await t.pumpAndSettle();
}

/// Runs the club picker down to Gamma Spor (id 3).
Future<void> _pickGamma(WidgetTester t, AppLocalizations l) async {
  await t.tap(find.text(l.pickClub));
  await t.pumpAndSettle();
  await _pickInSheet(t, l.countryTR);
  await _pickInSheet(t, l.leagueDisplayName(l.countryTR, 1));
  await _pickInSheet(t, 'Gamma Spor');
}

void main() {
  testWidgets('empty names block the start', (t) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    await _open(t, gateway: g);
    await t.tap(find.text(l.startUnemployed));
    await t.pumpAndSettle();
    await _tapStart(t, l);
    expect(find.text(l.fieldRequired), findsNWidgets(2));
    expect(g.calls, isNot(contains('newGame')));
    expect(find.byType(NewGameScreen), findsOneWidget);
  });

  testWidgets('sizes beyond the entitlements are hidden', (t) async {
    final l = await loadL10n();
    await _open(
      t,
      entitlements: const Entitlements(allowedSizes: {WorldSize.small}),
    );
    expect(find.text(l.worldSizeSmall), findsOneWidget);
    expect(find.text(l.worldSizeMedium), findsNothing);
    expect(find.text(l.worldSizeLarge), findsNothing);
  });

  testWidgets('nationality offers only the countries of the world size', (
    t,
  ) async {
    final l = await loadL10n();
    await _open(t);
    await t.tap(find.text(l.countryTR));
    await t.pumpAndSettle();
    expect(find.text(l.countryDE), findsWidgets);
    expect(find.text(l.countryJP), findsNothing);
    await t.tap(find.text(l.countryDE).last);
    await t.pumpAndSettle();
    await _selectSize(t, l.worldSizeLarge);
    await t.tap(find.text(l.countryDE));
    await t.pumpAndSettle();
    expect(find.text(l.countryJP), findsWidgets);
  });

  testWidgets('start unemployed sends startClubId null and opens the game', (
    t,
  ) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    final c = await _open(t, gateway: g);
    await _enterNames(t);
    await t.tap(find.text(l.startUnemployed));
    await t.pumpAndSettle();
    await _tapStart(t, l);
    final spec = g.lastSpec!;
    expect(spec.startClubId, isNull);
    expect(spec.managerFirstName, 'Hakan');
    expect(spec.managerLastName, 'Artuc');
    expect(spec.managerCountryCode, 'TR');
    expect(spec.size, WorldSize.small);
    expect(g.calls.where((c) => c == 'newGame'), hasLength(1));
    expect(c.state, isA<Ready>());
    expect(find.byType(NewGameScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('start needs a club unless unemployed', (t) async {
    final l = await loadL10n();
    await _open(t);
    final start = find.ancestor(
      of: find.text(l.startGame),
      matching: find.byType(FilledButton),
    );
    expect(t.widget<FilledButton>(start).onPressed, isNull);
    await t.tap(find.text(l.startUnemployed));
    await t.pumpAndSettle();
    expect(t.widget<FilledButton>(start).onPressed, isNotNull);
  });

  testWidgets('club flow: country, league, club fill the spec', (t) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    await _open(t, gateway: g);
    await _enterNames(t);
    await _pickGamma(t, l);
    expect(g.lastSpec!.startClubId, isNull, reason: 'preview is unemployed');
    expect(find.text('Gamma Spor'), findsOneWidget);
    await _tapStart(t, l);
    expect(g.lastSpec!.startClubId, 3);
    expect(g.calls.where((c) => c == 'newGame'), hasLength(2));
    expect(find.byType(NewGameScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('changing the world size or seed clears the picked club', (
    t,
  ) async {
    final l = await loadL10n();
    await _open(t);
    await _enterNames(t);
    await _pickGamma(t, l);
    await _selectSize(t, l.worldSizeMedium);
    expect(find.text('Gamma Spor'), findsNothing);

    await _pickGamma(t, l);
    await t.tap(find.text(l.advanced));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('seed')), '42');
    await t.pumpAndSettle();
    expect(find.text('Gamma Spor'), findsNothing);
  });

  testWidgets('EN labels', (t) async {
    const en = Locale('en');
    final l = await loadL10n(en);
    await _open(t, locale: en);
    for (final s in [
      l.managerFirstName,
      l.managerLastName,
      l.nationality,
      l.worldSize,
      l.startUnemployed,
      l.pickClub,
      l.advanced,
      l.startGame,
      l.countryTR,
    ]) {
      expect(find.text(s), findsOneWidget, reason: s);
    }
  });

  testWidgets('no overflow at 360x780', (t) async {
    final l = await loadL10n();
    await _open(t, size: const Size(360, 780));
    await _enterNames(t);
    await _pickGamma(t, l);
    await t.tap(find.text(l.advanced));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
