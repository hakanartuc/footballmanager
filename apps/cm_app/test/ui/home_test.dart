import 'dart:async';

import 'package:cm_app/engine/snapshots.dart';
import 'package:cm_app/l10n/event_text.dart';
import 'package:cm_app/l10n/formatters.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_gateway.dart';
import '../support/pump_app.dart';

/// A played 2-1 for club 1 at home to club 2.
FixtureRow _result() => FixtureRow(
  id: 1,
  round: 1,
  date: GameDate.ymd(2026, 7, 8),
  homeId: 1,
  awayId: 2,
  homeName: 'Alpha FC',
  awayName: 'Beta SK',
  homeGoals: 2,
  awayGoals: 1,
  goals: const [
    GoalRow(minute: 12, scorerId: 11, scorerName: 'Home Scorer', clubId: 1),
    GoalRow(minute: 45, scorerId: 21, scorerName: 'Away Scorer', clubId: 2),
    GoalRow(minute: 80, scorerId: 12, scorerName: 'Late Scorer', clubId: 1),
  ],
);

AdvanceOutcome _outcome({FixtureRow? userMatch, bool seasonEnded = false}) =>
    AdvanceOutcome(
      daysAdvanced: 1,
      reason: StopReason.played,
      date: GameDate.ymd(2026, 7, 8),
      userMatch: userMatch,
      seasonEnded: seasonEnded,
      newInboxCount: 0,
    );

InboxItem _youth(int id) => InboxItem(
  id: id,
  date: GameDate.ymd(2026, 7, 1),
  read: true,
  event: YouthIntake(
    date: GameDate.ymd(2026, 7, 1),
    clubId: 1,
    playerIds: List.filled(id, 0),
  ),
  labels: const InboxLabels(clubName: 'Alpha FC'),
);

void main() {
  testWidgets('non-match day shows advance and tapping it advances', (t) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    await pumpApp(t, gateway: g);
    expect(find.text(l.playMatch), findsNothing);
    await t.tap(find.text(l.advance));
    await t.pumpAndSettle();
    expect(g.calls, contains('advanceToNext'));
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('header shows date, season, league and position', (t) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    await pumpApp(t, gateway: g);
    final home = g.homeSnapshot;
    expect(find.text(formatDate(home.date, const Locale('tr'))), findsOne);
    expect(find.text('${l.season} ${seasonLabel(2026)}'), findsOne);
    expect(find.textContaining(leagueDisplayName('TR', 1, l)), findsOneWidget);
    expect(find.textContaining(l.leaguePositionLabel(1)), findsOneWidget);
    expect(find.textContaining(l.playerCount(22)), findsOneWidget);
    expect(find.textContaining(l.squadStatus(0, 0)), findsOneWidget);
  });

  testWidgets('next match card shows the opponent, date and venue', (t) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    await pumpApp(t, gateway: g);
    final card = find.byKey(const Key('nextMatchCard'));
    expect(
      find.descendant(of: card, matching: find.text(l.nextMatch)),
      findsOne,
    );
    expect(find.descendant(of: card, matching: find.text('BET')), findsOne);
    expect(
      find.descendant(of: card, matching: find.textContaining(l.homeLabel)),
      findsOne,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.textContaining(
          formatDate(g.homeSnapshot.nextMatch!.date, const Locale('tr')),
        ),
      ),
      findsOne,
    );
  });

  testWidgets('match day plays and shows the result sheet', (t) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    g.homeSnapshot = copyHome(g.homeSnapshot, isMatchDay: true);
    g.playOutcome = _outcome(userMatch: _result());
    await pumpApp(t, gateway: g);
    expect(find.text(l.advance), findsNothing);
    expect(find.text(l.lineup), findsNothing, reason: 'no lineup handler');
    await t.tap(find.text(l.playMatch));
    await t.pumpAndSettle();
    expect(g.calls, contains('playToday'));
    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    Finder inSheet(Finder f) => find.descendant(of: sheet, matching: f);
    expect(inSheet(find.text('2 - 1')), findsOneWidget);
    expect(inSheet(find.text('Alpha FC')), findsOneWidget);
    expect(inSheet(find.text('Beta SK')), findsOneWidget);
    expect(inSheet(find.text("12' Home Scorer")), findsOneWidget);
    expect(inSheet(find.text("45' Away Scorer")), findsOneWidget);
    expect(inSheet(find.text("80' Late Scorer")), findsOneWidget);
    await t.tap(inSheet(find.text(l.ok)));
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('a season-ended outcome shows the season end dialog', (t) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    g.advanceOutcome = _outcome(seasonEnded: true);
    await pumpApp(t, gateway: g);
    await t.tap(find.text(l.advance));
    await t.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text(l.seasonEnded)),
      findsOne,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.text(l.seasonEndBody(seasonLabel(2026), 1)),
      ),
      findsOne,
    );
    await t.tap(find.descendant(of: dialog, matching: find.text(l.ok)));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a match that ends the season shows the sheet, then dialog', (
    t,
  ) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    g.homeSnapshot = copyHome(g.homeSnapshot, isMatchDay: true);
    g.playOutcome = _outcome(userMatch: _result(), seasonEnded: true);
    await pumpApp(t, gateway: g);
    await t.tap(find.text(l.playMatch));
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await t.tap(
      find.descendant(of: find.byType(BottomSheet), matching: find.text(l.ok)),
    );
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('dismissing the sheet by tapping outside shows the dialog', (
    t,
  ) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    g.homeSnapshot = copyHome(g.homeSnapshot, isMatchDay: true);
    g.playOutcome = _outcome(userMatch: _result(), seasonEnded: true);
    await pumpApp(t, gateway: g);
    await t.tap(find.text(l.playMatch));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('unemployed shows the unemployed text and advance', (t) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    g.homeSnapshot = copyHome(g.homeSnapshot, unemployed: true);
    g.advanceOutcome = _outcome(seasonEnded: true);
    await pumpApp(t, gateway: g);
    expect(find.text(l.noClubUnemployed), findsOneWidget);
    expect(find.byKey(const Key('nextMatchCard')), findsNothing);
    await t.tap(find.text(l.advance));
    await t.pumpAndSettle();
    expect(g.calls, contains('advanceToNext'));
    expect(
      find.text(l.seasonEndBodyUnemployed(seasonLabel(2026))),
      findsOneWidget,
    );
  });

  testWidgets('latest news shows the 3 newest titles; tap opens inbox', (
    t,
  ) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    g.inboxItems = [for (var id = 5; id >= 1; id--) _youth(id)];
    await pumpApp(t, gateway: g);
    expect(find.text(l.latestNews), findsOneWidget);
    String title(int id) => EventText.describe(_youth(id), l).title;
    for (final id in [5, 4, 3]) {
      expect(find.text(title(id)), findsOneWidget);
    }
    for (final id in [2, 1]) {
      expect(find.text(title(id)), findsNothing);
    }
    await t.ensureVisible(find.text(title(4)));
    await t.tap(find.text(title(4)));
    await t.pumpAndSettle();
    expect(
      t.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
  });

  testWidgets('unread news is bold', (t) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    await pumpApp(t, gateway: g);
    final title = EventText.describe(g.inboxItems.first, l).title;
    final text = t.widget<Text>(find.text(title));
    expect(text.style?.fontWeight, FontWeight.bold);
  });

  testWidgets('buttons are disabled while busy', (t) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    final c = await pumpApp(t, gateway: g);
    g.hold = Completer();
    final pending = c.advance();
    await t.pump();
    final button = find.ancestor(
      of: find.text(l.advance),
      matching: find.byType(FilledButton),
    );
    expect(t.widget<FilledButton>(button).onPressed, isNull);
    g.hold!.complete();
    await pending;
    await t.pumpAndSettle();
    expect(t.widget<FilledButton>(button).onPressed, isNotNull);
  });

  for (final matchDay in [false, true]) {
    testWidgets('360x780 renders without overflow (match day: $matchDay)', (
      t,
    ) async {
      final g = FakeGateway.ready();
      g.homeSnapshot = copyHome(g.homeSnapshot, isMatchDay: matchDay);
      await pumpApp(t, gateway: g, size: const Size(360, 780));
      expect(t.takeException(), isNull);
    });
  }
}
