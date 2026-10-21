import 'package:cm_app/engine/engine_gateway.dart';
import 'package:cm_app/engine/snapshots.dart';
import 'package:cm_app/l10n/formatters.dart';
import 'package:cm_app/ui/squad/player_screen.dart';
import 'package:cm_app/ui/squad/squad_screen.dart';
import 'package:cm_app/ui/widgets/empty_state.dart';
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
  bool injured = false,
  int suspension = 0,
  bool youth = false,
}) => SquadRow(
  id: id,
  name: name,
  position: position,
  age: youth ? 16 : 25,
  ca: 100 + id,
  condition: 90,
  injured: injured,
  suspension: suspension,
  status: youth ? PlayerStatus.youth : PlayerStatus.firstTeam,
  isYouth: youth,
);

final _rows = [
  _row(1, 'Keeper One', Position.gk),
  _row(2, 'Hurt Back', Position.dc, injured: true),
  _row(3, 'Banned Back', Position.dc, suspension: 2),
  _row(4, 'Mid One', Position.mc),
  _row(5, 'Striker One', Position.st),
  _row(6, 'Youth Kid', Position.st, youth: true),
];

PlayerDetail _detail(Position position) => PlayerDetail(
  id: 1,
  name: 'Keeper One',
  countryCode: 'TR',
  position: position,
  familiarity: {position: 20},
  age: 25,
  heightCm: 188,
  attrs: [for (var i = 0; i < Attr.values.length; i++) 1 + i % 20],
  ca: 132,
  pa: 160,
  condition: 95,
  morale: 70,
  sharpness: 80,
  form: 6.5,
  wageWeekly: 12000,
  contractEnd: GameDate.ymd(2028, 6, 30),
  status: PlayerStatus.keyPlayer,
  apps: 7,
  goals: 3,
  assists: 2,
);

Finder _inSquad(Finder f) =>
    find.descendant(of: find.byType(SquadScreen), matching: f);

Future<FakeGateway> _openSquad(
  WidgetTester t, {
  Size size = const Size(390, 844),
}) async {
  final l = await loadL10n();
  final g = FakeGateway.ready()..squadRows = _rows;
  await pumpApp(t, gateway: g, size: size);
  await t.tap(find.text(l.tabSquad));
  await t.pumpAndSettle();
  return g;
}

void main() {
  testWidgets('lists seniors under position group headers', (t) async {
    final l = await loadL10n();
    await _openSquad(t);
    for (final header in [
      l.groupGoalkeepers,
      l.groupDefenders,
      l.groupMidfielders,
      l.groupForwards,
    ]) {
      expect(_inSquad(find.text(header)), findsOneWidget);
    }
    for (final name in ['Keeper One', 'Hurt Back', 'Mid One', 'Striker One']) {
      expect(_inSquad(find.text(name)), findsOneWidget);
    }
    expect(_inSquad(find.text('Youth Kid')), findsNothing);
    expect(_inSquad(find.text(positionCode(Position.dc))), findsNWidgets(2));
    expect(_inSquad(find.byIcon(Icons.healing)), findsOneWidget);
    expect(_inSquad(find.byIcon(Icons.block)), findsOneWidget);
    expect(_inSquad(find.byType(LinearProgressIndicator)), findsNWidgets(5));
    final keeper = t.getTopLeft(_inSquad(find.text('Keeper One'))).dy;
    final striker = t.getTopLeft(_inSquad(find.text('Striker One'))).dy;
    expect(keeper, lessThan(striker));
  });

  testWidgets('youth toggle lists the youth squad', (t) async {
    final l = await loadL10n();
    await _openSquad(t);
    await t.tap(_inSquad(find.text(l.youthSquad)));
    await t.pumpAndSettle();
    expect(_inSquad(find.text('Youth Kid')), findsOneWidget);
    expect(_inSquad(find.text('Keeper One')), findsNothing);
    await t.tap(_inSquad(find.text(l.seniorSquad)));
    await t.pumpAndSettle();
    expect(_inSquad(find.text('Keeper One')), findsOneWidget);
  });

  testWidgets('a squad load error shows an ErrorCard; retry loads', (t) async {
    final l = await loadL10n();
    final g = await _openSquad(t);
    g.failNext = const GatewayError(GatewayErrorKind.engine, 'boom');
    await t.tap(_inSquad(find.text(l.youthSquad)));
    await t.pumpAndSettle();
    expect(_inSquad(find.byType(ErrorCard)), findsOneWidget);
    expect(_inSquad(find.byType(CircularProgressIndicator)), findsNothing);
    await t.tap(_inSquad(find.text(l.retry)));
    await t.pumpAndSettle();
    expect(_inSquad(find.byType(ErrorCard)), findsNothing);
    expect(_inSquad(find.text('Youth Kid')), findsOneWidget);
  });

  testWidgets('a player load error shows an ErrorCard; retry loads, ok pops', (
    t,
  ) async {
    final l = await loadL10n();
    final g = await _openSquad(t);
    g.playerDetail = _detail(Position.gk);
    g.failNext = const GatewayError(GatewayErrorKind.engine, 'boom');
    await t.tap(_inSquad(find.text('Keeper One')));
    await t.pumpAndSettle();
    await t.tap(find.text(l.ok));
    await t.pumpAndSettle();
    expect(find.byType(PlayerScreen), findsNothing);
    g.failNext = const GatewayError(GatewayErrorKind.engine, 'boom');
    await t.tap(_inSquad(find.text('Keeper One')));
    await t.pumpAndSettle();
    expect(find.byType(ErrorCard), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await t.tap(find.text(l.retry));
    await t.pumpAndSettle();
    expect(find.text('${l.ca} 132 · ${l.pa} 160'), findsOneWidget);
  });

  testWidgets('unemployed shows the empty state', (t) async {
    final l = await loadL10n();
    final g = FakeGateway.ready();
    g.homeSnapshot = copyHome(g.homeSnapshot, unemployed: true);
    await pumpApp(t, gateway: g);
    await t.tap(find.text(l.tabSquad));
    await t.pumpAndSettle();
    expect(_inSquad(find.byType(EmptyState)), findsOneWidget);
    expect(_inSquad(find.text(l.noClubUnemployed)), findsOneWidget);
    expect(g.calls, isNot(contains('squad')));
  });

  for (final position in [Position.gk, Position.mc]) {
    testWidgets('player screen of a ${position.name} shows every attribute '
        'in its tab, contract and stats', (t) async {
      final l = await loadL10n();
      const locale = Locale('tr');
      final g = await _openSquad(t);
      g.playerDetail = _detail(position);
      await t.tap(_inSquad(find.text('Keeper One')));
      await t.pumpAndSettle();
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(find.text('${l.ca} 132 · ${l.pa} 160'), findsOneWidget);
      expect(find.textContaining(positionName(position, l)), findsWidgets);
      expect(find.textContaining(countryName('TR', l)), findsOneWidget);
      expect(find.textContaining(l.heightCm(188)), findsOneWidget);

      final groups = [
        if (position == Position.gk) AttrGroup.goalkeeping,
        AttrGroup.technical,
        AttrGroup.mental,
        AttrGroup.physical,
      ];
      expect(
        find.text(l.attrGroupGoalkeeping),
        position == Position.gk ? findsOneWidget : findsNothing,
      );
      for (final group in groups) {
        await t.tap(find.text(attrGroupName(group, l)));
        await t.pumpAndSettle();
        for (final a in Attr.values.where((a) => attrGroupOf(a) == group)) {
          expect(find.text(attrName(a, l)), findsOneWidget, reason: a.name);
        }
      }
      expect(find.text(l.attrPassing), findsNothing, reason: 'tab switched');

      await t.tap(find.text(l.info));
      await t.pumpAndSettle();
      expect(find.text(l.wage), findsOneWidget);
      expect(find.text(money(12000, locale)), findsOneWidget);
      expect(find.text(l.contractEnd), findsOneWidget);
      expect(
        find.text(formatDate(GameDate.ymd(2028, 6, 30), locale)),
        findsOneWidget,
      );
      expect(find.text(statusName(PlayerStatus.keyPlayer, l)), findsOneWidget);
      expect(find.text(l.apps), findsOneWidget);
      expect(find.text(l.goals), findsOneWidget);
      expect(find.text(l.assists), findsOneWidget);
      expect(find.text(l.morale), findsOneWidget);
      expect(find.text(l.form), findsOneWidget);
    });
  }

  testWidgets('squad and player screens fit 360x780', (t) async {
    final l = await loadL10n();
    final g = await _openSquad(t, size: const Size(360, 780));
    expect(t.takeException(), isNull);
    await t.tap(_inSquad(find.text(l.youthSquad)));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.tap(_inSquad(find.text(l.seniorSquad)));
    await t.pumpAndSettle();
    g.playerDetail = _detail(Position.gk);
    await t.tap(_inSquad(find.text('Keeper One')));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.ensureVisible(find.text(l.info));
    await t.pumpAndSettle();
    await t.tap(find.text(l.info));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
