import 'package:cm_app/engine/engine_gateway.dart';
import 'package:cm_app/engine/snapshots.dart';
import 'package:cm_app/l10n/formatters.dart';
import 'package:cm_app/ui/league/league_screen.dart';
import 'package:cm_app/ui/widgets/error_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_gateway.dart';
import '../support/pump_app.dart';

Finder _inLeague(Finder f) =>
    find.descendant(of: find.byType(LeagueScreen), matching: f);

ClubRef _club(int id, String name, int leagueId) => ClubRef(
  id: id,
  name: name,
  shortName: name.substring(0, 3).toUpperCase(),
  kitPrimary: 0xFF000000,
  kitSecondary: 0xFFFFFFFF,
  leagueId: leagueId,
  countryId: leagueId < 20 ? 100 : 200,
);

/// [FakeGateway.ready] plus a TR second tier (league 11) and an English
/// league (20), with fixture 1 played 2-1 and fixture 2 upcoming.
FakeGateway _gateway({bool englandFirst = false}) {
  final g = FakeGateway.ready();
  final base = g.refsSnapshot;
  final tr = CountryRef(
    id: 100,
    code: 'TR',
    name: 'Türkiye',
    leagueIds: const [10, 11],
  );
  const eng = CountryRef(
    id: 200,
    code: 'ENG',
    name: 'England',
    leagueIds: [20],
  );
  const tr2 = LeagueRef(
    id: 11,
    name: 'TR_tier2',
    countryCode: 'TR',
    tier: 2,
    clubIds: [5, 6],
  );
  const eng1 = LeagueRef(
    id: 20,
    name: 'ENG_tier1',
    countryCode: 'ENG',
    tier: 1,
    clubIds: [7, 8],
  );
  g.refsSnapshot = WorldRefs(
    countries: englandFirst ? [eng, tr] : [tr, eng],
    leagues: englandFirst
        ? [eng1, ...base.leagues, tr2]
        : [...base.leagues, tr2, eng1],
    clubs: [
      ...base.clubs,
      _club(5, 'Epsilon', 11),
      _club(6, 'Zeta', 11),
      _club(7, 'Eta Town', 20),
      _club(8, 'Theta City', 20),
    ],
  );
  final f = g.fixtureRows;
  g.fixtureRows = [
    FixtureRow(
      id: f[0].id,
      round: f[0].round,
      date: f[0].date,
      homeId: f[0].homeId,
      awayId: f[0].awayId,
      homeName: f[0].homeName,
      awayName: f[0].awayName,
      homeGoals: 2,
      awayGoals: 1,
      goals: [
        GoalRow(minute: 12, scorerId: 11, scorerName: 'Home Scorer', clubId: 1),
        GoalRow(minute: 45, scorerId: 21, scorerName: 'Away Scorer', clubId: 2),
        GoalRow(minute: 80, scorerId: 12, scorerName: 'Late Hero', clubId: 1),
      ],
    ),
    ...f.skip(1),
  ];
  return g;
}

Future<void> _openLeague(WidgetTester t) async {
  final l = await loadL10n();
  await t.tap(find.text(l.tabLeague));
  await t.pumpAndSettle();
}

Future<void> _pick(WidgetTester t, String current, String next) async {
  await t.tap(_inLeague(find.text(current)));
  await t.pumpAndSettle();
  await t.tap(find.text(next).last);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('defaults to the user league and highlights the user row', (
    t,
  ) async {
    final l = await loadL10n();
    final g = _gateway();
    await pumpApp(t, gateway: g);
    await _openLeague(t);
    expect(g.tableArgs.last, g.homeSnapshot.leagueId);
    expect(_inLeague(find.text(leagueDisplayName('TR', 1, l))), findsOneWidget);
    expect(_inLeague(find.text(countryName('TR', l))), findsOneWidget);
    for (final h in [l.played, l.won, l.drawn, l.lost, l.goalDifference]) {
      expect(_inLeague(find.text(h)), findsOneWidget, reason: h);
    }
    for (final name in ['Alpha FC', 'Beta SK', 'Gamma Spor', 'Delta United']) {
      expect(_inLeague(find.text(name)), findsOneWidget);
    }
    final user = _inLeague(find.byKey(const Key('userRow')));
    expect(user, findsOneWidget);
    expect(
      find.descendant(of: user, matching: find.text('Alpha FC')),
      findsOneWidget,
    );
    final ctx = t.element(user);
    expect(
      t.widget<ColoredBox>(user).color,
      Theme.of(ctx).colorScheme.primaryContainer,
    );
  });

  testWidgets('the picker switches league and country and refetches', (
    t,
  ) async {
    final l = await loadL10n();
    final g = _gateway();
    await pumpApp(t, gateway: g);
    await _openLeague(t);
    await _pick(
      t,
      leagueDisplayName('TR', 1, l),
      leagueDisplayName('TR', 2, l),
    );
    expect(g.tableArgs.last, 11);
    await _pick(t, countryName('TR', l), countryName('ENG', l));
    expect(g.tableArgs.last, 20);
    expect(
      _inLeague(find.text(leagueDisplayName('ENG', 1, l))),
      findsOneWidget,
    );
    expect(g.calls.where((m) => m == 'table'), hasLength(3));
  });

  testWidgets('fixtures show scores, dashes and expandable scorers', (t) async {
    final l = await loadL10n();
    final g = _gateway();
    await pumpApp(t, gateway: g);
    await _openLeague(t);
    await t.tap(_inLeague(find.text(l.fixtures)));
    await t.pumpAndSettle();
    expect(g.clubFixturesArgs.last, 1);
    expect(_inLeague(find.text('2 - 1')), findsOneWidget);
    expect(_inLeague(find.text('–')), findsNWidgets(2));
    expect(_inLeague(find.textContaining(l.roundLabel(1))), findsOneWidget);
    expect(_inLeague(find.textContaining('Home Scorer')), findsNothing);
    await t.tap(_inLeague(find.text('2 - 1')));
    await t.pumpAndSettle();
    expect(_inLeague(find.text("12' Home Scorer")), findsOneWidget);
    expect(_inLeague(find.text("80' Late Hero")), findsOneWidget);
    expect(_inLeague(find.text("45' Away Scorer")), findsOneWidget);
    final home = t.getTopLeft(_inLeague(find.text("12' Home Scorer"))).dx;
    final away = t.getTopLeft(_inLeague(find.text("45' Away Scorer"))).dx;
    expect(home, lessThan(away));
    await t.tap(_inLeague(find.text('–')).first);
    await t.pumpAndSettle();
    expect(_inLeague(find.byType(ExpansionTile)), findsOneWidget);
  });

  testWidgets('unemployed: first league, no highlight, club picker', (t) async {
    final l = await loadL10n();
    final g = _gateway(englandFirst: true);
    g.homeSnapshot = copyHome(g.homeSnapshot, unemployed: true);
    g.tableRows = [
      for (final r in g.tableRows)
        TableRowView(
          rank: r.rank,
          clubId: r.clubId,
          clubName: r.clubName,
          played: r.played,
          won: r.won,
          drawn: r.drawn,
          lost: r.lost,
          gf: r.gf,
          ga: r.ga,
          gd: r.gd,
          points: r.points,
          isUser: false,
        ),
    ];
    await pumpApp(t, gateway: g);
    await _openLeague(t);
    expect(g.tableArgs.last, 20);
    expect(
      _inLeague(find.text(leagueDisplayName('ENG', 1, l))),
      findsOneWidget,
    );
    expect(_inLeague(find.byKey(const Key('userRow'))), findsNothing);
    await t.tap(_inLeague(find.text(l.fixtures)));
    await t.pumpAndSettle();
    expect(g.clubFixturesArgs.last, 7);
    await _pick(t, 'Eta Town', 'Theta City');
    expect(g.clubFixturesArgs.last, 8);
  });

  testWidgets('a table load error shows an ErrorCard; retry loads', (t) async {
    final l = await loadL10n();
    final g = _gateway();
    await pumpApp(t, gateway: g);
    await _openLeague(t);
    g.failNext = const GatewayError(GatewayErrorKind.engine, 'boom');
    await _pick(
      t,
      leagueDisplayName('TR', 1, l),
      leagueDisplayName('TR', 2, l),
    );
    expect(_inLeague(find.byType(ErrorCard)), findsOneWidget);
    expect(_inLeague(find.byType(CircularProgressIndicator)), findsNothing);
    await t.tap(_inLeague(find.text(l.retry)));
    await t.pumpAndSettle();
    expect(_inLeague(find.byType(ErrorCard)), findsNothing);
    expect(_inLeague(find.text('Alpha FC')), findsOneWidget);
    expect(g.tableArgs.last, 11);
  });

  testWidgets('both tabs fit 360x780', (t) async {
    final l = await loadL10n();
    final g = _gateway();
    await pumpApp(t, gateway: g, size: const Size(360, 780));
    await _openLeague(t);
    expect(t.takeException(), isNull);
    await t.tap(_inLeague(find.text(l.fixtures)));
    await t.pumpAndSettle();
    await t.tap(_inLeague(find.text('2 - 1')));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
