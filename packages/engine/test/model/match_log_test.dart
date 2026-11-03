import 'package:engine/engine.dart';
import 'package:test/test.dart';

void main() {
  test('a possession step carries its micro events and match events', () {
    const a = Pt(50, 40);
    const b = Pt(30, 70);
    final step = PossessionStep(
      minute: 23,
      half: 1,
      attackingId: 1,
      lane: Lane.left,
      counter: true,
      chance: ChanceType.cross,
      xg: 0.12,
      outcome: ShotOutcome.goal,
      shooter: 9,
      assister: 7,
      micro: const [
        Pass(0, 4, 7, a, b),
        Dribble(1.5, 7, b, Pt(20, 85)),
        Cross(2.5, 7, 9, Pt(20, 85), Pt(50, 94)),
        Shot(3, 9, Pt(50, 94), Pt(48, 100), ShotOutcome.goal, 21),
        Tackle(0.5, 12, 4, a),
        Foul(0.7, 12, 4, a),
        Save(3.1, 21, Pt(48, 99)),
        Clearance(3.2, 15, Pt(50, 95), Pt(60, 60)),
      ],
      events: [
        Goal(
          minute: 23,
          half: 1,
          clubId: 1,
          scorerId: 9,
          assistId: 7,
          type: ChanceType.cross,
          isPenalty: false,
        ),
      ],
    );
    final log = MatchLog(steps: [step]);
    expect(log.steps.single.micro.map((m) => m.t), [
      0,
      1.5,
      2.5,
      3,
      0.5,
      0.7,
      3.1,
      3.2,
    ]);
    expect((step.micro[3] as Shot).keeperId, 21);
    expect(step.events.single, isA<Goal>());
  });

  test('lists default to empty', () {
    final step = PossessionStep(
      minute: 1,
      half: 1,
      attackingId: 2,
      lane: Lane.centre,
      counter: false,
    );
    expect(step.micro, isEmpty);
    expect(step.events, isEmpty);
    expect(step.chance, isNull);
    expect(MatchLog().steps, isEmpty);
  });
}
