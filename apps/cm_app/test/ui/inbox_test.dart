import 'dart:async';

import 'package:cm_app/data/settings_controller.dart';
import 'package:cm_app/engine/engine_gateway.dart';
import 'package:cm_app/engine/snapshots.dart';
import 'package:cm_app/l10n/event_text.dart';
import 'package:cm_app/state/game_controller.dart';
import 'package:cm_app/ui/inbox/inbox_detail_screen.dart';
import 'package:cm_app/ui/inbox/inbox_screen.dart';
import 'package:cm_app/ui/widgets/error_card.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/fake_gateway.dart';
import '../support/pump_app.dart';

Finder _inInbox(Finder f) =>
    find.descendant(of: find.byType(InboxScreen), matching: f);

Finder get _dots => _inInbox(find.byKey(const Key('unreadDot')));

Future<void> _openInbox(WidgetTester t) async {
  final l = await loadL10n();
  await t.tap(find.text(l.tabInbox));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('items render TR titles, bodies and unread dots', (t) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    g.inboxItems = [
      g.inboxItems.first,
      InboxItem(
        id: 1,
        date: g.inboxItems.last.date,
        read: true,
        event: g.inboxItems.last.event,
        labels: g.inboxItems.last.labels,
      ),
    ];
    await pumpApp(t, gateway: g);
    await _openInbox(t);
    for (final item in g.inboxItems) {
      final text = EventText.describe(item, l);
      expect(_inInbox(find.text(text.title)), findsOneWidget);
      expect(_inInbox(find.text(text.body)), findsOneWidget);
    }
    expect(_dots, findsOneWidget);
    final unreadTitle = EventText.describe(g.inboxItems.first, l).title;
    final readTitle = EventText.describe(g.inboxItems.last, l).title;
    expect(
      t.widget<Text>(_inInbox(find.text(unreadTitle))).style?.fontWeight,
      FontWeight.bold,
    );
    expect(
      t.widget<Text>(_inInbox(find.text(readTitle))).style?.fontWeight,
      isNot(FontWeight.bold),
    );
    // Newest first, as returned.
    expect(
      t.getTopLeft(_inInbox(find.text(unreadTitle))).dy,
      lessThan(t.getTopLeft(_inInbox(find.text(readTitle))).dy),
    );
  });

  testWidgets('tap marks read, opens the detail and clears the dot', (t) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    final item = g.inboxItems.first;
    final text = EventText.describe(item, l);
    await pumpApp(t, gateway: g);
    await _openInbox(t);
    expect(_dots, findsNWidgets(2));
    await t.tap(_inInbox(find.text(text.title)));
    await t.pumpAndSettle();
    expect(g.calls, contains('markRead'));
    expect(g.inboxItems.first.read, isTrue);
    final detail = find.byType(InboxDetailScreen);
    expect(detail, findsOneWidget);
    expect(
      find.descendant(of: detail, matching: find.text(text.title)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detail, matching: find.text(text.body)),
      findsOneWidget,
    );
    await t.tap(
      find.byTooltip(
        MaterialLocalizations.of(t.element(detail)).backButtonTooltip,
      ),
    );
    await t.pumpAndSettle();
    expect(_dots, findsOneWidget);
  });

  testWidgets('switching the app locale re-renders items in EN', (t) async {
    final lTr = await loadL10n();
    final lEn = await loadL10n(const Locale('en'));
    final g = FakeGateway.ready();
    final item = g.inboxItems.first;
    await pumpApp(t, gateway: g);
    await _openInbox(t);
    final tr = EventText.describe(item, lTr).title;
    final en = EventText.describe(item, lEn).title;
    expect(tr, isNot(en));
    expect(_inInbox(find.text(tr)), findsOneWidget);
    final settings = Provider.of<SettingsController>(
      t.element(find.byType(Navigator)),
      listen: false,
    );
    await settings.setLocale(const Locale('en'));
    await t.pumpAndSettle();
    expect(_inInbox(find.text(en)), findsOneWidget);
    expect(_inInbox(find.text(tr)), findsNothing);
    expect(_inInbox(find.text(lEn.markAllRead)), findsOneWidget);
  });

  testWidgets('mark all reads every unread item and clears the badge', (
    t,
  ) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    final c = await pumpApp(t, gateway: g);
    await _openInbox(t);
    expect(find.byType(Badge), findsOneWidget);
    await t.tap(_inInbox(find.text(l.markAllRead)));
    await t.pumpAndSettle();
    expect(g.calls.where((m) => m == 'markRead'), hasLength(2));
    expect(g.inboxItems.every((i) => i.read), isTrue);
    expect((c.state as Ready).home.unreadCount, 0);
    expect(find.byType(Badge), findsNothing);
    expect(_dots, findsNothing);
    final button = t.widget<TextButton>(
      _inInbox(find.widgetWithText(TextButton, l.markAllRead)),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('mark all stops when a busy action starts meanwhile', (t) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    final c = await pumpApp(t, gateway: g);
    await _openInbox(t);
    g.hold = Completer();
    await t.tap(_inInbox(find.text(l.markAllRead))); // markRead(2) waits
    await t.pump();
    final adv = c.advance(); // advanceToNext waits
    await t.pump();
    // Releasing lets markRead(2) run to its end while advance saves.
    for (var i = 0; i < 2; i++) {
      final held = g.hold!;
      g.hold = Completer();
      held.complete();
      await t.pump();
    }
    expect(c.state, isA<Busy>());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    g.hold!.complete();
    g.hold = null;
    await adv;
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(c.state, isA<Ready>());
    expect(g.calls.where((m) => m == 'markRead'), hasLength(1));
  });

  testWidgets('an empty inbox shows the empty state', (t) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    g.inboxItems = const [];
    await pumpApp(t, gateway: g);
    await _openInbox(t);
    expect(_inInbox(find.text(l.noMessages)), findsOneWidget);
  });

  testWidgets('a load error shows an ErrorCard; retry loads', (t) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    g.inboxError = const GatewayError(GatewayErrorKind.engine, 'boom');
    await pumpApp(t, gateway: g);
    await _openInbox(t);
    expect(_inInbox(find.byType(ErrorCard)), findsOneWidget);
    expect(_inInbox(find.byType(CircularProgressIndicator)), findsNothing);
    g.inboxError = null;
    await t.tap(_inInbox(find.text(l.retry)));
    await t.pumpAndSettle();
    expect(_inInbox(find.byType(ErrorCard)), findsNothing);
    expect(
      _inInbox(find.text(EventText.describe(g.inboxItems.first, l).title)),
      findsOneWidget,
    );
  });

  testWidgets('a long title fits 360x780 in the list and the detail', (
    t,
  ) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    final day = g.inboxItems.first.date;
    final long = 'Very Long Club Name Athletic Football Club ' * 3;
    g.inboxItems = [
      InboxItem(
        id: 3,
        date: day,
        read: false,
        event: LeagueChampion(date: day, clubId: 1, leagueId: 10),
        labels: InboxLabels(
          clubName: long,
          leagueCountryCode: 'TR',
          leagueTier: 1,
        ),
      ),
    ];
    await pumpApp(t, gateway: g, size: const Size(360, 780));
    await _openInbox(t);
    expect(t.takeException(), isNull);
    await t.tap(
      _inInbox(find.text(EventText.describe(g.inboxItems.first, l).title)),
    );
    await t.pumpAndSettle();
    expect(find.byType(InboxDetailScreen), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
