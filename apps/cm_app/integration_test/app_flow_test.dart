import 'package:cm_app/l10n/formatters.dart';
import 'package:cm_app/state/game_controller.dart';
import 'package:cm_app/ui/shell/game_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support.dart';

/// The real app end to end on a small world: new game → advance to match
/// day → auto lineup → play → result → inbox → manual save → restart →
/// continue (autosave) → load slot 1. Each step logs `[it] …`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // A tap that misses its widget (e.g. during a route transition) fails
  // instead of silently landing elsewhere.
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets('new game, match, save, restart, continue, load', (t) async {
    final l = await loadL10n();
    final store = await tempStore();
    const tr = Locale('tr');

    step('1 bootstrap');
    await pumpFreshApp(t, l, store);

    step('2 new game (small, TR, first club)');
    await t.tap(find.text(l.newGame));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('firstName')), 'Hakan');
    await t.enterText(find.byKey(const Key('lastName')), 'Artuc');
    await t.tap(find.text(l.pickClub));
    // Country, league, club: the first option of each sheet (index 0 is
    // the sheet's title tile).
    for (var i = 0; i < 3; i++) {
      await waitFor(t, find.byType(BottomSheet));
      await t.pumpAndSettle();
      await t.tap(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(ListTile),
            )
            .at(1),
      );
      await t.pumpAndSettle();
    }
    await t.ensureVisible(find.text(l.startGame));
    await t.tap(find.text(l.startGame));
    await waitFor(t, find.byType(GameShell));
    await waitIdle(t);
    final controller = controllerOf(t);

    step('3 advance to match day');
    for (var i = 0; i < 5 && find.text(l.playMatch).evaluate().isEmpty; i++) {
      await t.tap(find.text(l.advance));
      await waitIdle(t);
    }
    expect(find.text(l.playMatch), findsOneWidget);

    step('4 auto lineup');
    await t.tap(find.text(l.lineup));
    await waitFor(t, find.text(l.autoLineup));
    await t.pumpAndSettle(); // the route transition
    await t.tap(find.text(l.autoLineup));
    // The auto lineup is one gateway call; the screen has no loading state
    // for it, so give it a moment.
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.tap(find.text(l.saveLineup));
    await waitFor(t, find.text(l.playMatch));
    await t.pumpAndSettle(); // the route transition
    expect(controller.pendingLineup, isNotNull);

    step('5 play match');
    await t.tap(find.text(l.playMatch));
    final score = find.textContaining(RegExp(r'^\d+ - \d+$'));
    await waitFor(t, score, timeout: const Duration(seconds: 60));
    await t.pumpAndSettle();
    await t.tap(find.text(l.ok));
    await waitIdle(t);

    step('6 inbox has the match item');
    await t.tap(find.text(l.tabInbox));
    await t.pumpAndSettle();
    await waitFor(t, find.textContaining(RegExp(r'\d+ - \d+')));

    step('7 save to slot 1');
    await t.tap(find.byIcon(Icons.save_outlined));
    await waitFor(t, find.byKey(const Key('slot1')));
    await t.pumpAndSettle();
    await t.tap(
      find.descendant(
        of: find.byKey(const Key('slot1')),
        matching: find.text(l.save),
      ),
    );
    await t.pump();
    if (find.byType(AlertDialog).evaluate().isNotEmpty) {
      await t.tap(find.text(l.ok));
    }
    await waitFor(t, find.text(l.saved));
    await waitIdle(t);
    final date = (controller.state as Ready).home.date;
    step('saved at ${formatDate(date, tr)}');

    step('8 restart → continue (autosave)');
    await pumpFreshApp(t, l, store);
    // The continue button enables once the newest autosave is read.
    await waitUntil(t, () => find.text(l.noSavedGame).evaluate().isEmpty);
    await t.tap(find.text(l.continueGame));
    await waitFor(t, find.byType(GameShell));
    await waitIdle(t);
    final restarted = controllerOf(t);
    expect((restarted.state as Ready).home.date, date);
    expect(find.text(formatDate(date, tr)), findsOneWidget);

    step('9 load slot 1');
    await t.tap(find.byIcon(Icons.save_outlined));
    await waitFor(t, find.byKey(const Key('slot1')));
    await t.pumpAndSettle();
    await t.tap(
      find.descendant(
        of: find.byKey(const Key('slot1')),
        matching: find.text(l.load),
      ),
    );
    await waitFor(t, find.byType(GameShell));
    await waitIdle(t);
    expect((restarted.state as Ready).home.date, date);
    expect(find.text(formatDate(date, tr)), findsOneWidget);
    step('done');
  });
}
