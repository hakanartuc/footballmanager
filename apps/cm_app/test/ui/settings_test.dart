import 'package:cm_app/engine/snapshots.dart';
import 'package:cm_app/l10n/formatters.dart';
import 'package:cm_app/ui/settings/settings_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_gateway.dart';
import '../support/pump_app.dart';

Future<void> _openFromShell(WidgetTester t) async {
  await t.tap(find.byIcon(Icons.settings_outlined));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('opens from the shell AppBar icon', (t) async {
    final l = await loadL10n();
    await pumpApp(t);
    await _openFromShell(t);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text(l.settings), findsOneWidget);
    expect(find.text(l.devStats), findsOneWidget);
  });

  testWidgets('opens from the start screen without dev stats', (t) async {
    final l = await loadL10n();
    await pumpApp(t, startReady: false);
    await _openFromShell(t);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text(l.language), findsOneWidget);
    expect(find.text(l.devStats), findsNothing);
    expect(find.text(l.about), findsOneWidget);
  });

  testWidgets('choosing English flips the app locale and persists it', (
    t,
  ) async {
    final tr = await loadL10n();
    final en = await loadL10n(const Locale('en'));
    await pumpApp(t);
    await _openFromShell(t);
    expect(find.text(tr.settings), findsOneWidget);
    await t.tap(find.text(en.english));
    await t.pumpAndSettle();
    expect(find.text(en.settings), findsOneWidget);
    expect(find.text(tr.settings), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('locale'), 'en');

    await t.tap(find.text(en.systemLanguage));
    await t.pumpAndSettle();
    expect(prefs.containsKey('locale'), isFalse);
    // Falls back to the app's TR locale.
    expect(find.text(tr.settings), findsOneWidget);
  });

  testWidgets('dev stats show controller timings, world size and season', (
    t,
  ) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    g.refsSnapshot = WorldRefs(
      countries: [
        ...g.refsSnapshot.countries,
        for (final code in ['ENG', 'ES', 'DE'])
          CountryRef(id: code.hashCode, code: code, name: code, leagueIds: []),
      ],
      leagues: g.refsSnapshot.leagues,
      clubs: g.refsSnapshot.clubs,
    );
    final c = await pumpApp(t, gateway: g);
    // Fixed values: the fake's real timings are ~0 ms and indistinct.
    c
      ..lastAdvanceMs = 1234
      ..lastSaveMs = 567;
    await _openFromShell(t);
    expect(find.text(l.lastAdvanceMs(1234)), findsOneWidget);
    expect(find.text(l.lastSaveMs(567)), findsOneWidget);
    expect(find.text(l.worldSizeSmall), findsOneWidget);
    expect(find.text(seasonLabel(g.homeSnapshot.seasonYear)), findsOneWidget);
    expect(find.text(l.engineVersion), findsOneWidget);
    expect(find.text(engineVersion), findsOneWidget);
  });

  testWidgets('about shows the app version', (t) async {
    final l = await loadL10n();
    await pumpApp(t);
    await _openFromShell(t);
    await t.scrollUntilVisible(find.text(l.version('0.1.0')), 100);
    expect(find.text(l.version('0.1.0')), findsOneWidget);
    expect(find.text(l.appTitle), findsOneWidget);
  });

  testWidgets('no overflow at 360x780', (t) async {
    await pumpApp(t, size: const Size(360, 780));
    await _openFromShell(t);
    expect(t.takeException(), isNull);
  });

  test('world size from country count', () {
    expect(sizeFromCountryCount(4), WorldSize.small);
    expect(sizeFromCountryCount(8), WorldSize.medium);
    expect(sizeFromCountryCount(16), WorldSize.large);
  });
}
