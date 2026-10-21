@Tags(['golden'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:cm_app/ui/saves/saves_screen.dart';
import 'package:cm_app/ui/settings/settings_screen.dart';
import 'package:cm_app/ui/squad/lineup_screen.dart';
import 'package:cm_app/ui/squad/player_screen.dart';
import 'package:cm_app/ui/squad/squad_screen.dart';
import 'package:cm_app/ui/start/new_game_screen.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_gateway.dart';
import '../support/golden.dart';
import '../support/pump_app.dart';

/// Local, not UTC: the saves screen shows `savedAt.toLocal()`, so a UTC
/// instant would render differently in each time zone.
final _savedAt = DateTime(2026, 8, 1, 12);

Future<void> _write(MemorySaveStore store, int slot, String club) =>
    store.write(
      slot,
      Uint8List(1),
      SlotInfo(
        slot: slot,
        managerName: 'Test Manager',
        clubName: club,
        date: GameDate.ymd(2026, 7, 1),
        seasonYear: 2026,
        savedAt: _savedAt,
        bytes: 1,
      ),
    );

/// A manual save of Beta SK in slot 2 and an autosave of Alpha FC in slot 6.
Future<MemorySaveStore> _store() async {
  final store = MemorySaveStore();
  await _write(store, 2, 'Beta SK');
  await _write(store, 6, 'Alpha FC');
  return store;
}

/// Rewrites every slot of [store] with the fixed [_savedAt].
Future<void> _pinSavedAt(MemorySaveStore store) async {
  for (final s in await store.list()) {
    await store.write(
      s.slot,
      await store.read(s.slot),
      SlotInfo(
        slot: s.slot,
        managerName: s.managerName,
        clubName: s.clubName,
        date: s.date,
        seasonYear: s.seasonYear,
        savedAt: _savedAt,
        bytes: s.bytes,
      ),
    );
  }
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.tap(f);
  await t.pumpAndSettle();
}

/// Pumps the app and navigates to a screen, as the widget tests do.
typedef _Open =
    Future<void> Function(WidgetTester t, Locale locale, _Pump pump);

typedef _Pump = Future<void> Function({bool startReady});

final Map<String, _Open> _screens = {
  'start': (t, locale, pump) => pump(startReady: false),
  'newGame': (t, locale, pump) async {
    final l = await loadL10n(locale);
    await pump(startReady: false);
    await _tap(t, find.text(l.newGame));
    expect(find.byType(NewGameScreen), findsOneWidget);
    // The seed (wall clock) is under the collapsed advanced section.
  },
  'home': (t, locale, pump) => pump(),
  'squad': (t, locale, pump) async {
    final l = await loadL10n(locale);
    await pump();
    await _tap(t, find.text(l.tabSquad));
  },
  'player': (t, locale, pump) async {
    final l = await loadL10n(locale);
    await pump();
    await _tap(t, find.text(l.tabSquad));
    Finder inSquad(Finder f) =>
        find.descendant(of: find.byType(SquadScreen), matching: f);
    final name = inSquad(find.text('Hakan Polat'));
    await t.scrollUntilVisible(
      name,
      100,
      scrollable: inSquad(find.byType(Scrollable)).last,
    );
    // Off the bottom navigation bar.
    await t.ensureVisible(name);
    await t.pumpAndSettle();
    await _tap(t, name);
    expect(find.byType(PlayerScreen), findsOneWidget);
  },
  'lineup': (t, locale, pump) async {
    final l = await loadL10n(locale);
    await pump();
    await _tap(t, find.text(l.lineup));
    expect(find.byType(LineupScreen), findsOneWidget);
  },
  'leagueTable': (t, locale, pump) async {
    final l = await loadL10n(locale);
    await pump();
    await _tap(t, find.text(l.tabLeague));
  },
  'inbox': (t, locale, pump) async {
    final l = await loadL10n(locale);
    await pump();
    await _tap(t, find.text(l.tabInbox));
  },
  'saves': (t, locale, pump) async {
    await pump();
    await _tap(t, find.byIcon(Icons.save_outlined));
    expect(find.byType(SavesScreen), findsOneWidget);
  },
  'settings': (t, locale, pump) async {
    await pump();
    await _tap(t, find.byIcon(Icons.settings_outlined));
    expect(find.byType(SettingsScreen), findsOneWidget);
  },
};

const _locales = [Locale('tr'), Locale('en')];
const _themes = {'light': ThemeMode.light, 'dark': ThemeMode.dark};
const _sizes = [Size(390, 844), Size(360, 780)];

void main() {
  setUpAll(() async {
    await loadTestFonts();
    // The DEBUG ribbon would cover the AppBar actions.
    WidgetsApp.debugAllowBannerOverride = false;
  });

  group(
    'screens',
    skip: !Platform.isMacOS ? 'goldens are rendered on macOS only' : false,
    () {
      for (final MapEntry(key: screen, value: open) in _screens.entries) {
        for (final locale in _locales) {
          for (final MapEntry(key: theme, value: themeMode)
              in _themes.entries) {
            for (final size in _sizes) {
              final name =
                  '${screen}_${locale.languageCode}_${theme}_'
                  '${size.width.toInt()}x${size.height.toInt()}';
              testWidgets(name, (t) async {
                final store = await _store();
                await open(t, locale, ({bool startReady = true}) async {
                  await pumpApp(
                    t,
                    gateway: FakeGateway.rich(),
                    store: store,
                    locale: locale,
                    size: size,
                    themeMode: themeMode,
                    startReady: startReady,
                  );
                  // Starting a game autosaves with the wall clock.
                  if (startReady) await _pinSavedAt(store);
                });
                expect(t.takeException(), isNull);
                await expectLater(
                  find.byType(MaterialApp),
                  matchesGoldenFile('goldens/$name.png'),
                );
              });
            }
          }
        }
      }
    },
  );
}
