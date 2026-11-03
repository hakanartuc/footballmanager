import 'package:cm_app/engine/engine_gateway.dart';
import 'package:cm_app/engine/snapshots.dart';
import 'package:cm_app/l10n/formatters.dart';
import 'package:cm_app/state/game_controller.dart';
import 'package:cm_app/ui/squad/lineup_screen.dart';
import 'package:cm_app/ui/widgets/error_card.dart';
import 'package:engine/engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_gateway.dart';
import '../support/pump_app.dart';

SquadRow _row(
  int id,
  String name,
  Position position, {
  int ca = 100,
  bool injured = false,
  int suspension = 0,
  bool youth = false,
}) => SquadRow(
  id: id,
  name: name,
  position: position,
  age: 25,
  ca: ca,
  condition: 90,
  injured: injured,
  suspension: suspension,
  status: PlayerStatus.firstTeam,
  isYouth: youth,
);

final _rows = [
  _row(1, 'Keeper One', Position.gk, ca: 120),
  _row(2, 'Left Back', Position.dl),
  _row(3, 'Centre One', Position.dc),
  _row(4, 'Centre Two', Position.dc),
  _row(5, 'Right Back', Position.dr),
  _row(6, 'Left Mid', Position.ml),
  _row(7, 'Mid One', Position.mc),
  _row(8, 'Mid Two', Position.mc),
  _row(9, 'Right Mid', Position.mr),
  _row(10, 'Striker One', Position.st),
  _row(11, 'Striker Two', Position.st),
  _row(12, 'Keeper Two', Position.gk, ca: 90),
  _row(13, 'Spare Striker', Position.st, ca: 95),
  _row(14, 'Injured Mid', Position.mc, ca: 150, injured: true),
  _row(15, 'Banned Back', Position.dc, ca: 150, suspension: 1),
  _row(16, 'Youth Kid', Position.st, ca: 60, youth: true),
];

const _valid = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];

LineupView _view(List<PlayerId> starters) => LineupView(
  formation: Formation.f442,
  slots: formationSlots(Formation.f442),
  starters: starters,
  bench: const [12, 13],
  errors: const [],
);

Finder _inSheet(String name) =>
    find.descendant(of: find.byType(BottomSheet), matching: find.text(name));

/// Opens the lineup screen from home on a match day with [starters].
Future<(FakeGateway, GameController)> _open(
  WidgetTester t,
  List<PlayerId> starters, {
  Size size = const Size(390, 844),
}) async {
  final l = await loadL10n();
  final g = FakeGateway.ready()
    ..squadRows = _rows
    ..lineupView = _view(starters);
  g.homeSnapshot = copyHome(g.homeSnapshot, isMatchDay: true);
  final c = await pumpApp(t, gateway: g, size: size);
  await t.tap(find.text(l.lineup));
  await t.pumpAndSettle();
  expect(find.byType(LineupScreen), findsOneWidget);
  return (g, c);
}

void main() {
  testWidgets('shows the formation and the 11 slots', (t) async {
    final (g, _) = await _open(t, _valid);
    expect(find.text('4-4-2'), findsOneWidget);
    for (final r in _rows.take(11)) {
      expect(find.text(r.name), findsOneWidget);
    }
    expect(find.text(positionCode(Position.st)), findsNWidgets(2));
    expect(g.lineupAutoArgs, [false]);
  });

  testWidgets('picker lists eligible players by fit; a valid lineup is '
      'saved, popped and sent with playMatch', (t) async {
    final l = await loadL10n();
    final (g, c) = await _open(t, _valid);
    await t.tap(find.text('Striker Two'));
    await t.pumpAndSettle();
    for (final name in ['Injured Mid', 'Banned Back', 'Striker One']) {
      expect(_inSheet(name), findsNothing, reason: name);
    }
    double y(String name) => t.getTopLeft(_inSheet(name)).dy;
    expect(y('Spare Striker'), lessThan(y('Youth Kid')));
    expect(y('Youth Kid'), lessThan(y('Keeper Two')));
    await t.tap(_inSheet('Spare Striker'));
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Spare Striker'), findsOneWidget);
    expect(find.text('Striker Two'), findsNothing);

    await t.tap(find.text(l.saveLineup));
    await t.pumpAndSettle();
    expect(find.byType(LineupScreen), findsNothing);
    const chosen = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 13];
    expect(c.pendingLineup!.starters, chosen);
    expect(c.pendingLineup!.formation, Formation.f442);
    expect(c.pendingLineup!.bench, [11, 12]);

    await t.tap(find.text(l.playMatch));
    await t.pumpAndSettle();
    final set = g.playTodayCommands.first.whereType<SetLineup>().single;
    expect(set.clubId, 1);
    expect(set.lineup.starters, chosen);
  });

  final invalid = {
    'injured starter': (
      [1, 2, 3, 4, 5, 6, 14, 8, 9, 10, 11],
      LineupError.ineligible,
    ),
    'ten players': ([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], LineupError.notEleven),
    'outfielder in goal': (
      [2, 1, 3, 4, 5, 6, 7, 8, 9, 10, 11],
      LineupError.noGoalkeeper,
    ),
  };
  for (final MapEntry(key: name, value: (starters, error)) in invalid.entries) {
    testWidgets('save refuses a lineup with $name', (t) async {
      final l = await loadL10n();
      final (_, c) = await _open(t, starters);
      await t.tap(find.text(l.saveLineup));
      await t.pump();
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(lineupErrorText(error, l)),
        ),
        findsOneWidget,
      );
      expect(find.byType(LineupScreen), findsOneWidget);
      expect(c.pendingLineup, isNull);
    });
  }

  testWidgets('auto lineup reloads the auto suggestion', (t) async {
    final l = await loadL10n();
    final (g, _) = await _open(t, [1, 2, 3, 4, 5, 6, 14, 8, 9, 10, 11]);
    g.autoLineupView = _view(_valid);
    expect(find.text('Injured Mid'), findsOneWidget);
    await t.tap(find.text(l.autoLineup));
    await t.pumpAndSettle();
    expect(g.lineupAutoArgs, [false, true]);
    expect(find.text('Injured Mid'), findsNothing);
    expect(find.text('Mid One'), findsOneWidget);
  });

  testWidgets('reopening after save shows the pending lineup', (t) async {
    final l = await loadL10n();
    final (g, c) = await _open(t, _valid);
    await t.tap(find.text('Striker Two'));
    await t.pumpAndSettle();
    await t.tap(_inSheet('Spare Striker'));
    await t.pumpAndSettle();
    await t.tap(find.text(l.saveLineup));
    await t.pumpAndSettle();
    expect(find.byType(LineupScreen), findsNothing);

    await t.tap(find.text(l.lineup));
    await t.pumpAndSettle();
    expect(find.text('Spare Striker'), findsOneWidget);
    expect(find.text('Striker Two'), findsNothing);
    expect(g.lineupAutoArgs, [false], reason: 'seeded from pendingLineup');
    expect(c.pendingLineup, isNotNull);
  });

  testWidgets('a load error shows an ErrorCard; retry loads, ok pops', (
    t,
  ) async {
    final l = await loadL10n();
    final g = FakeGateway.ready()
      ..squadRows = _rows
      ..lineupView = _view(_valid);
    g.homeSnapshot = copyHome(g.homeSnapshot, isMatchDay: true);
    await pumpApp(t, gateway: g);
    g.failNext = const GatewayError(GatewayErrorKind.engine, 'boom');
    await t.tap(find.text(l.lineup));
    await t.pumpAndSettle();
    await t.tap(find.text(l.ok));
    await t.pumpAndSettle();
    expect(find.byType(LineupScreen), findsNothing);
    g.failNext = const GatewayError(GatewayErrorKind.engine, 'boom');
    await t.tap(find.text(l.lineup));
    await t.pumpAndSettle();
    expect(find.byType(ErrorCard), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await t.tap(find.text(l.retry));
    await t.pumpAndSettle();
    expect(find.byType(ErrorCard), findsNothing);
    expect(find.text('Keeper One'), findsOneWidget);
  });

  testWidgets('unemployed home has no lineup button', (t) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    g.homeSnapshot = copyHome(
      g.homeSnapshot,
      unemployed: true,
      isMatchDay: true,
    );
    await pumpApp(t, gateway: g);
    expect(find.text(l.lineup), findsNothing);
  });

  testWidgets('lineup screen and picker fit 360x780', (t) async {
    await _open(t, _valid, size: const Size(360, 780));
    expect(t.takeException(), isNull);
    await t.tap(find.text('Striker Two'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
