import 'package:engine/engine.dart';
import 'package:test/test.dart';

Club _club({List<Tactic>? tactics, int activeTactic = 0}) => Club(
  id: 1,
  name: 'Club',
  shortName: 'CLB',
  countryId: 1,
  leagueId: 1,
  reputation: 50,
  home: Kit(primary: 0xFFFF0000, secondary: 0xFFFFFFFF),
  away: Kit(primary: 0xFFFFFFFF, secondary: 0xFF0000FF),
  logo: LogoSpec(shape: 0, color1: 0xFF00FF00, color2: 0xFF000000),
  stadiumName: 'Stadium',
  stadiumCapacity: 20000,
  balance: 0,
  transferBudget: 0,
  wageBudget: 0,
  facilities: Facilities(training: 5, medical: 5, youth: 5),
  expectation: BoardExpectation.mid,
  tactics: tactics,
  activeTactic: activeTactic,
);

const _custom343 = [
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

void main() {
  test('laneOf maps every position to its lane', () {
    expect(laneOf(Position.gk), Lane.centre);
    expect(laneOf(Position.dl), Lane.left);
    expect(laneOf(Position.dc), Lane.centre);
    expect(laneOf(Position.dr), Lane.right);
    expect(laneOf(Position.dm), Lane.centre);
    expect(laneOf(Position.ml), Lane.left);
    expect(laneOf(Position.mc), Lane.centre);
    expect(laneOf(Position.mr), Lane.right);
    expect(laneOf(Position.aml), Lane.left);
    expect(laneOf(Position.amc), Lane.centre);
    expect(laneOf(Position.amr), Lane.right);
    expect(laneOf(Position.st), Lane.centre);
  });

  group('Tactic.preset', () {
    test('takes the formation slots and balanced defaults', () {
      final t = Tactic.preset(Formation.f442, name: 'A');
      expect(t.name, 'A');
      expect(t.formation, Formation.f442);
      expect(t.slots, formationSlots(Formation.f442));
      expect(t.mentality, Mentality.balanced);
      expect(t.passing, PassingStyle.mixed);
      expect(t.tempo, Tempo.normal);
      expect(t.width, Width.normal);
      expect(t.pressing, Pressing.normal);
      expect(t.tackling, Tackling.normal);
      expect(t.marking, Marking.zonal);
      expect(t.offsideTrap, isFalse);
      expect(t.counterAttack, isFalse);
      expect(t.playmaker, isNull);
      expect(t.targetMan, isNull);
      expect(t.captain, isNull);
      expect(t.viceCaptain, isNull);
      expect(t.setPieces.penalty, isNull);
      expect(t.instructions, isEmpty);
      expect(t.arrows, isEmpty);
    });

    test('is named after the formation by default', () {
      expect(Tactic.preset(Formation.f433).name, 'f433');
    });

    test('rejects Formation.custom', () {
      expect(() => Tactic.preset(Formation.custom), throwsArgumentError);
      expect(() => formationSlots(Formation.custom), throwsArgumentError);
    });

    test('every preset slot list is a fresh copy', () {
      final t = Tactic.preset(Formation.f442);
      t.slots[1] = Position.dc;
      expect(formationSlots(Formation.f442)[1], Position.dl);
    });
  });

  group('Tactic.custom', () {
    test('keeps the given slots under Formation.custom', () {
      final t = Tactic.custom(_custom343, name: 'X');
      expect(t.name, 'X');
      expect(t.formation, Formation.custom);
      expect(t.slots, _custom343);
    });

    test('requires 11 slots with the goalkeeper first', () {
      expect(
        () => Tactic.custom(_custom343.sublist(0, 10)),
        throwsArgumentError,
      );
      expect(
        () => Tactic.custom([..._custom343.skip(1), Position.gk]),
        throwsArgumentError,
      );
    });
  });

  group('Club tactics', () {
    test('default to three presets with the first active', () {
      final c = _club();
      expect(c.tactics.map((t) => t.name), ['1', '2', '3']);
      expect(c.tactics.map((t) => t.formation), [
        Formation.f442,
        Formation.f433,
        Formation.f532,
      ]);
      expect(c.activeTactic, 0);
      expect(c.tactic, same(c.tactics[0]));
      expect(c.formation, Formation.f442);
    });

    test('formation reads the active tactic', () {
      final c = _club(activeTactic: 2);
      expect(c.formation, Formation.f532);
      expect(c.tactic, same(c.tactics[2]));
    });

    test('setting formation replaces the active tactic keeping its name', () {
      final c = _club(activeTactic: 1);
      c.formation = Formation.f352;
      expect(c.tactics[1].name, '2');
      expect(c.tactics[1].formation, Formation.f352);
      expect(c.tactics[1].slots, formationSlots(Formation.f352));
      expect(c.tactics[0].formation, Formation.f442);
    });

    test('require exactly three tactics and an active index in 0..2', () {
      expect(
        () => _club(tactics: [Tactic.preset(Formation.f442)]),
        throwsArgumentError,
      );
      expect(() => _club(activeTactic: 3), throwsArgumentError);
    });
  });
}
