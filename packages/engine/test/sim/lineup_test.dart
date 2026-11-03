import 'package:engine/engine.dart';
import 'package:test/test.dart';

World _world() => createNewGame(
  NewGameSpec(
    seed: 1,
    size: WorldSize.small,
    managerFirstName: 'Test',
    managerLastName: 'Manager',
    managerCountryCode: 'TR',
    startClubId: null,
  ),
);

void main() {
  late World w;
  late ClubId c;

  setUp(() {
    w = _world();
    c = w.clubs.keys.first;
  });

  Player p(PlayerId id) => w.players[id]!;
  Set<PlayerId> clubPlayers() => {...w.squadOf(c), ...w.youthOf(c)};

  group('autoLineup', () {
    test('picks 11 unique club players with a goalkeeper in goal', () {
      final l = autoLineup(w, c);
      expect(l.formation, w.clubs[c]!.formation);
      expect(l.starters, hasLength(11));
      expect(l.starters.toSet(), hasLength(11));
      expect(clubPlayers().containsAll(l.starters), isTrue);
      expect(p(l.starters[0]).mainPosition, Position.gk);
    });

    test('uses the given formation', () {
      final l = autoLineup(w, c, formation: Formation.f433);
      expect(l.formation, Formation.f433);
      expect(p(l.starters[0]).mainPosition, Position.gk);
    });

    test('prefers natural positions over raw ability', () {
      final seniors = w.squadOf(c);
      final dc = seniors.firstWhere((id) => p(id).mainPosition == Position.dc);
      final st = seniors.firstWhere((id) => p(id).mainPosition == Position.st);
      for (final id in seniors) {
        p(id).ca = 50;
      }
      p(dc)
        ..ca = 120
        ..familiarity = {Position.dc: 20};
      p(st)
        ..ca = 125
        ..familiarity = {Position.st: 20, Position.dc: 1};

      final l = autoLineup(w, c);
      final slots = formationSlots(l.formation);
      expect(slots[l.starters.indexOf(dc)], Position.dc);
      expect(slots[l.starters.indexOf(st)], Position.st);
    });

    test('fills the slots of a custom active tactic', () {
      const slots = [
        Position.gk,
        Position.dc,
        Position.dc,
        Position.dc,
        Position.ml,
        Position.mc,
        Position.mc,
        Position.mr,
        Position.aml,
        Position.amr,
        Position.st,
      ];
      final club = w.clubs[c]!;
      club.tactics[club.activeTactic] = Tactic.custom(slots, name: '343');
      final seniors = w.squadOf(c);
      for (final id in seniors) {
        p(id).ca = 50;
      }
      final winger = seniors[5];
      final wideMid = seniors[6];
      p(winger)
        ..ca = 120
        ..familiarity = {Position.aml: 20};
      p(wideMid)
        ..ca = 120
        ..familiarity = {Position.mr: 20};

      final l = autoLineup(w, c);
      expect(l.formation, Formation.custom);
      expect(l.starters, hasLength(11));
      expect(l.starters.toSet(), hasLength(11));
      expect(p(l.starters[0]).mainPosition, Position.gk);
      expect(slots[l.starters.indexOf(winger)], Position.aml);
      expect(slots[l.starters.indexOf(wideMid)], Position.mr);
      expect(validateLineup(w, c, l), isEmpty);
    });

    test('lower condition lowers the pick', () {
      final l = autoLineup(w, c);
      final keeper = l.starters[0];
      final backup = w
          .squadOf(c)
          .where((id) => id != keeper && p(id).mainPosition == Position.gk)
          .first;
      for (final id in w.squadOf(c)) {
        if (p(id).mainPosition == Position.gk) p(id).ca = 1;
      }
      p(keeper).ca = 100;
      p(backup).ca = 90;
      p(keeper).state.condition = 0; // 100 * 0.75 < 90
      expect(autoLineup(w, c).starters[0], backup);
    });

    test('excludes suspended and injured players', () {
      final first = autoLineup(w, c);
      final suspended = first.starters[5];
      final injured = first.starters[6];
      p(suspended).state.suspensionMatches = 1;
      p(injured).state.injury = InjuryStub(daysLeft: 10, type: 'knock');

      final l = autoLineup(w, c);
      expect(l.starters, isNot(contains(suspended)));
      expect(l.starters, isNot(contains(injured)));
      expect(l.bench, isNot(contains(suspended)));
      expect(l.bench, isNot(contains(injured)));
      expect(l.starters, hasLength(11));
    });

    test('fills from youth when only 9 seniors are eligible', () {
      final seniors = w.squadOf(c);
      for (final id in seniors.skip(9)) {
        p(id).state.injury = InjuryStub(daysLeft: 10, type: 'knock');
      }
      final l = autoLineup(w, c);
      expect(l.starters, hasLength(11));
      expect(l.starters.toSet(), hasLength(11));
      final allowed = {...seniors.take(9), ...w.youthOf(c)};
      expect(allowed.containsAll(l.starters), isTrue);
      expect(
        l.starters.where(w.youthOf(c).contains).length,
        greaterThanOrEqualTo(2),
      );
    });

    test('fit players always outrank unavailable ones', () {
      final seniors = w.squadOf(c);
      final youth = w.youthOf(c);
      final fit = {...seniors.take(8), ...youth.take(2)};
      for (final id in clubPlayers().difference(fit)) {
        p(id).state.injury = InjuryStub(daysLeft: 10, type: 'knock');
      }
      final star = seniors.last;
      p(star).ca = 200;

      final l = autoLineup(w, c);
      expect(l.starters, hasLength(11));
      expect(l.starters.toSet().containsAll(fit), isTrue);
      expect(l.starters.toSet().difference(fit), {star});
    });

    test('falls back to unavailable players rather than fielding < 11', () {
      for (final id in clubPlayers()) {
        p(id).state.injury = InjuryStub(daysLeft: 10, type: 'knock');
      }
      final l = autoLineup(w, c);
      expect(l.starters, hasLength(11));
      expect(l.starters.toSet(), hasLength(11));
      expect(clubPlayers().containsAll(l.starters), isTrue);
      expect(l.bench, isEmpty);
    });

    test('bench has at most 7 unused eligible players and a goalkeeper', () {
      final l = autoLineup(w, c);
      expect(l.bench.length, lessThanOrEqualTo(7));
      expect(l.bench.toSet(), hasLength(l.bench.length));
      expect(l.bench.any(l.starters.contains), isFalse);
      expect(w.squadOf(c).toSet().containsAll(l.bench), isTrue);
      expect(l.bench.any((id) => p(id).mainPosition == Position.gk), isTrue);
    });

    test('bench keeps a goalkeeper even when keepers rank lowest', () {
      final keepers = w
          .squadOf(c)
          .where((id) => p(id).mainPosition == Position.gk)
          .toList();
      final starter = keepers.first;
      p(starter).ca = 200;
      for (final id in keepers.skip(1)) {
        p(id).ca = 1;
      }
      final l = autoLineup(w, c);
      expect(l.starters[0], starter);
      expect(l.bench, hasLength(7));
      expect(l.bench.where(keepers.contains), hasLength(1));
    });

    test('is deterministic', () {
      final a = autoLineup(_world(), c);
      final b = autoLineup(_world(), c);
      expect(a.starters, b.starters);
      expect(a.bench, b.bench);
    });
  });

  group('validateLineup', () {
    late Lineup l;
    setUp(() => l = autoLineup(w, c));

    Lineup copy({List<PlayerId>? starters, List<PlayerId>? bench}) => Lineup(
      formation: l.formation,
      starters: starters ?? [...l.starters],
      bench: bench ?? [...l.bench],
    );

    test('accepts the auto lineup', () {
      expect(validateLineup(w, c, l), isEmpty);
    });

    test('notEleven', () {
      final s = [...l.starters]..removeLast();
      expect(validateLineup(w, c, copy(starters: s)), [LineupError.notEleven]);
    });

    test('duplicate', () {
      final b = [...l.bench, l.starters[3]];
      expect(validateLineup(w, c, copy(bench: b)), [LineupError.duplicate]);
    });

    test('notInClub', () {
      final other = w.clubs.keys.firstWhere((k) => k != c);
      final s = [...l.starters]..[10] = w.squadOf(other).last;
      expect(validateLineup(w, c, copy(starters: s)), [LineupError.notInClub]);
    });

    test('noGoalkeeper', () {
      final outfield = w
          .squadOf(c)
          .firstWhere(
            (id) =>
                !l.starters.contains(id) &&
                !l.bench.contains(id) &&
                p(id).mainPosition != Position.gk,
          );
      final s = [...l.starters]..[0] = outfield;
      expect(validateLineup(w, c, copy(starters: s)), [
        LineupError.noGoalkeeper,
      ]);
    });

    test('ineligible', () {
      p(l.starters[4]).state.suspensionMatches = 2;
      expect(validateLineup(w, c, l), [LineupError.ineligible]);
      p(l.starters[4]).state.suspensionMatches = 0;
      p(l.starters[7]).state.injury = InjuryStub(daysLeft: 3, type: 'knock');
      expect(validateLineup(w, c, l), [LineupError.ineligible]);
    });

    test('reports every applicable error in enum order', () {
      final other = w.clubs.keys.firstWhere((k) => k != c);
      final stranger = w
          .squadOf(other)
          .firstWhere((id) => p(id).mainPosition != Position.gk);
      final s = [l.starters[1], l.starters[1], stranger];
      expect(validateLineup(w, c, copy(starters: s)), [
        LineupError.notEleven,
        LineupError.duplicate,
        LineupError.notInClub,
        LineupError.noGoalkeeper,
      ]);
    });
  });

  test('commands carry their payload', () {
    final l = autoLineup(w, c);
    final Command set = SetLineup(clubId: c, lineup: l);
    const Command clear = ClearLineup(clubId: 7);
    String describe(Command cmd) => switch (cmd) {
      SetLineup(:final clubId) => 'set $clubId',
      ClearLineup(:final clubId) => 'clear $clubId',
    };
    expect(describe(set), 'set $c');
    expect(describe(clear), 'clear 7');
  });

  test('conditionFactor spans 0.75..1.0', () {
    expect(conditionFactor(100), 1.0);
    expect(conditionFactor(0), 0.75);
    expect(conditionFactor(50), 0.875);
  });
}
