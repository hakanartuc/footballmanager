import 'dart:async';

import 'package:cm_app/app.dart';
import 'package:cm_app/data/settings_controller.dart';
import 'package:cm_app/engine/engine_gateway.dart';
import 'package:cm_app/engine/snapshots.dart';
import 'package:cm_app/l10n/formatters.dart';
import 'package:cm_app/state/game_controller.dart';
import 'package:cm_app/ui/start/start_screen.dart';
import 'package:cm_app/ui/widgets/busy_overlay.dart';
import 'package:cm_app/ui/widgets/error_card.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_gateway.dart';
import '../support/pump_app.dart';

void main() {
  testWidgets('four destinations with TR labels and an unread badge', (
    t,
  ) async {
    final l = await loadL10n();
    await pumpApp(t);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    for (final label in [l.tabHome, l.tabSquad, l.tabLeague, l.tabInbox]) {
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: find.byType(Badge), matching: find.text('2')),
      findsOneWidget,
    );
  });

  testWidgets('tapping tabs switches the IndexedStack', (t) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    final c = await pumpApp(t, gateway: g);
    // The shell's stack; dropdowns on the tabs hold IndexedStacks too.
    IndexedStack stack() => t.widget(
      find.ancestor(
        of: find.byKey(const Key('homeTab'), skipOffstage: false),
        matching: find.byType(IndexedStack),
      ),
    );
    expect(stack().index, 0);
    await t.tap(find.text(l.tabLeague));
    await t.pumpAndSettle();
    expect(stack().index, 2);
    await t.tap(find.text(l.tabInbox));
    await t.pumpAndSettle();
    expect(stack().index, 3);
    g.hold = Completer();
    final pending = c.advance();
    await t.pump();
    expect(t.widget<BusyOverlay>(find.byType(BusyOverlay)).busy, isTrue);
    expect(stack().index, 3, reason: 'tab survives Busy');
    g.hold!.complete();
    await pending;
    await t.pumpAndSettle();
    expect(stack().index, 3);
    expect(
      find.byKey(const Key('homeTab'), skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('loading a different game resets the tab state', (t) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    final c = await pumpApp(t, gateway: g);
    await t.tap(find.text(l.tabLeague));
    await t.pumpAndSettle();
    expect(g.tableArgs.last, 10);
    // The autosave in slot 6 is reloaded as a world with one other league.
    const eta = ClubRef(
      id: 7,
      name: 'Eta Town',
      shortName: 'ETA',
      kitPrimary: 0xFF000000,
      kitSecondary: 0xFFFFFFFF,
      leagueId: 20,
      countryId: 200,
    );
    g.refsSnapshot = const WorldRefs(
      countries: [
        CountryRef(id: 200, code: 'ENG', name: 'England', leagueIds: [20]),
      ],
      leagues: [
        LeagueRef(
          id: 20,
          name: 'ENG_tier1',
          countryCode: 'ENG',
          tier: 1,
          clubIds: [7],
        ),
      ],
      clubs: [eta],
    );
    g.homeSnapshot = HomeSnapshot(
      date: g.homeSnapshot.date,
      seasonYear: 2026,
      clubId: 7,
      clubName: 'Eta Town',
      leagueId: 20,
      leaguePosition: 1,
      nextMatch: null,
      isMatchDay: false,
      unreadCount: 0,
      seniorCount: 20,
      injuredCount: 0,
      suspendedCount: 0,
      managerName: 'Test Manager',
    );
    g.tableRows = const [
      TableRowView(
        rank: 1,
        clubId: 7,
        clubName: 'Eta Town',
        played: 0,
        won: 0,
        drawn: 0,
        lost: 0,
        gf: 0,
        ga: 0,
        gd: 0,
        points: 0,
        isUser: true,
      ),
    ];
    g.fixtureRows = const [];
    await c.loadSlot(6);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(g.tableArgs.last, 20);
    await t.tap(find.text(l.tabLeague));
    await t.pumpAndSettle();
    expect(find.text(leagueDisplayName('ENG', 1, l)), findsOneWidget);
  });

  testWidgets('NoGame shows the start screen', (t) async {
    await pumpApp(t, startReady: false);
    expect(find.byType(StartScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('Busy shows the BusyOverlay over the shell', (t) async {
    final g = FakeGateway.ready();
    final c = await pumpApp(t, gateway: g);
    g.hold = Completer();
    final pending = c.advance();
    await t.pump();
    expect(c.state, isA<Busy>());
    expect(t.widget<BusyOverlay>(find.byType(BusyOverlay)).busy, isTrue);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    g.hold!.complete();
    await pending;
    await t.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Failed shows an ErrorCard whose retry calls again', (t) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    final c = await pumpApp(t, gateway: g);
    g.failNext = const GatewayError(GatewayErrorKind.engine, 'boom');
    await c.advance();
    await t.pumpAndSettle();
    expect(find.byType(ErrorCard), findsOneWidget);
    expect(find.text(l.error), findsWidgets);
    expect(find.text('boom'), findsNothing);
    await t.tap(find.text(l.retry));
    await t.pumpAndSettle();
    expect(g.calls.where((m) => m == 'advanceToNext'), hasLength(2));
    expect(find.byType(ErrorCard), findsNothing);
    expect(c.state, isA<Ready>());
  });

  testWidgets('ok on the ErrorCard dismisses without a gateway call', (
    t,
  ) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    final c = await pumpApp(t, gateway: g);
    g.failNext = const GatewayError(GatewayErrorKind.engine, 'boom');
    await c.advance();
    await t.pumpAndSettle();
    g.calls.clear();
    await t.tap(find.text(l.ok));
    await t.pumpAndSettle();
    expect(find.byType(ErrorCard), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(g.calls, isEmpty);
  });

  testWidgets('app bar shows the club name when employed', (t) async {
    final g = FakeGateway.ready();
    await pumpApp(t, gateway: g);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(g.homeSnapshot.clubName!),
      ),
      findsOneWidget,
    );
  });

  testWidgets('app bar shows the manager name when unemployed', (t) async {
    final g = FakeGateway.ready();
    g.homeSnapshot = copyHome(g.homeSnapshot, unemployed: true);
    await pumpApp(t, gateway: g);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(g.homeSnapshot.managerName),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a bootstrap failure shows an ErrorCard, not a spinner', (
    t,
  ) async {
    await t.pumpWidget(
      CmApp(
        gateway: FakeGateway.ready(),
        store: MemorySaveStore(),
        settings: _BrokenSettings(),
        locale: const Locale('tr'),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(ErrorCard), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

class _BrokenSettings extends SettingsController {
  @override
  Future<void> load() async => throw StateError('prefs unavailable');
}
