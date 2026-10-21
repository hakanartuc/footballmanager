import 'dart:async';

import 'package:cm_app/engine/engine_gateway.dart';
import 'package:cm_app/state/game_controller.dart';
import 'package:cm_app/ui/widgets/busy_overlay.dart';
import 'package:cm_app/ui/widgets/error_card.dart';
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
    final c = await pumpApp(t);
    IndexedStack stack() => t.widget(find.byType(IndexedStack));
    expect(stack().index, 0);
    await t.tap(find.text(l.tabLeague));
    await t.pumpAndSettle();
    expect(stack().index, 2);
    await t.tap(find.text(l.tabInbox));
    await t.pumpAndSettle();
    expect(stack().index, 3);
    await c.advance();
    await t.pumpAndSettle();
    expect(stack().index, 3, reason: 'tab survives Busy');
    expect(
      find.byKey(const Key('homeTab'), skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('NoGame shows the start screen placeholder', (t) async {
    await pumpApp(t, startReady: false);
    expect(find.byKey(const Key('startScreen')), findsOneWidget);
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
}
