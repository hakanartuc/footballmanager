import 'package:engine/engine.dart';
import 'package:test/test.dart';

import 'match_helpers.dart';

MatchRules rules({required bool extraTime, required bool penalties}) =>
    MatchRules(
      substitutions: 5,
      benchSize: 7,
      extraTime: extraTime,
      penalties: penalties,
      yellowThresholds: const [5, 10, 15],
      redBanSecondYellow: 1,
      redBanFoul: 3,
      redBanViolent: 4,
    );

/// A 60-second home possession without a chance.
PossessionStep quietStep() => PossessionStep(
  minute: 91,
  half: 3,
  attackingId: 1,
  lane: Lane.centre,
  counter: false,
  seconds: 60,
);

/// Draws that score (0.0) or miss (0.99) for every probability in range.
const g = 0.0;
const m = 0.99;

List<ShootoutKick> kicks(MatchState s) =>
    s.events.whereType<ShootoutKick>().toList();

List<PlayerId> kickers(MatchState s, ClubId club) => [
  for (final k in kicks(s))
    if (k.clubId == club) k.playerId,
];

/// Whether the first shootout kick (home) scored with [draw] first.
bool firstKickScores(MatchState s, World w, double draw) {
  playShootout(
    s,
    w,
    ScriptedRng([
      draw,
      m,
      for (var i = 0; i < 10; i++) ...[g, m],
    ]),
  );
  return kicks(s).first.scored;
}

void main() {
  group('needsExtraTime / needsShootout', () {
    test('extra time only when the rules allow it and the score is level', () {
      final s = startMatch(uniformWorld());
      for (final et in [false, true]) {
        for (final pens in [false, true]) {
          final r = rules(extraTime: et, penalties: pens);
          s.home.goals = 1;
          s.away.goals = 1;
          expect(needsExtraTime(s, r), et);
          expect(needsShootout(s, r), pens);
          s.away.goals = 2;
          expect(needsExtraTime(s, r), isFalse);
          expect(needsShootout(s, r), isFalse);
        }
      }
      expect(needsExtraTime(s, MatchRules.league), isFalse);
    });
  });

  group('halfEnd', () {
    test('45, 90, 105, 120 and throws on anything else', () {
      expect([for (var h = 1; h <= 4; h++) halfEnd(h)], [45, 90, 105, 120]);
      expect(() => halfEnd(0), throwsArgumentError);
      expect(() => halfEnd(5), throwsArgumentError);
    });
  });

  group('startExtraTime', () {
    test('sets the clock to 90, half 3 and logs ExtraTimeStart once', () {
      final s = startMatch(uniformWorld());
      s.minute = 94;
      s.half = 2;
      s.addedTime = 4;
      s.clockSeconds = 94 * 60;
      startExtraTime(s);
      expect(s.extraTime, isTrue);
      expect(s.half, 3);
      expect(s.minute, 90);
      expect(s.clockSeconds, 90 * 60);
      expect(s.addedTime, 0);
      final e = s.events.single as ExtraTimeStart;
      expect((e.minute, e.half, e.clubId), (90, 3, 1));

      s.minute = 100;
      startExtraTime(s);
      expect(s.minute, 100);
      expect(s.events, hasLength(1));
    });
  });

  group('extra-time substitution', () {
    World world() {
      final w = uniformWorld();
      for (var id = 12; id <= 17; id++) {
        w.players[id] = uniformPlayer(id, Position.mc);
      }
      return w;
    }

    MatchState match(World w) =>
        startMatch(w, homeBench: const [12, 13, 14, 15, 16, 17]);

    test('subsAllowed adds one in extra time', () {
      final s = match(world());
      expect(subsAllowed(s, MatchRules.league), 5);
      startExtraTime(s);
      expect(subsAllowed(s, MatchRules.league), 6);
    });

    test('the sixth substitution is rejected at 90, accepted in ET', () {
      final w = world();
      final s = match(w);
      for (var i = 0; i < 5; i++) {
        applyCommand(
          s,
          w,
          MatchRules.league,
          Substitute(1, outId: 2 + i, inId: 12 + i),
        );
      }
      const sixth = Substitute(1, outId: 7, inId: 17);
      expect(
        () => applyCommand(s, w, MatchRules.league, sixth),
        throwsA(
          isA<CommandError>().having(
            (e) => e.kind,
            'kind',
            CommandErrorKind.noSubsLeft,
          ),
        ),
      );
      startExtraTime(s);
      applyCommand(s, w, MatchRules.league, sixth);
      expect(s.home.subsUsed, 6);
      expect(s.home.onPitch[6], 17);
    });

    test('aiDecide uses the extra-time budget', () {
      final w = world();
      final s = match(w);
      for (var i = 0; i < 5; i++) {
        applyCommand(
          s,
          w,
          MatchRules.league,
          Substitute(1, outId: 2 + i, inId: 12 + i),
        );
      }
      s.home.injuredOff.add(8);
      s.home.removeFromPitch(8);
      expect(aiDecide(s, s.home, w, MatchRules.league), isEmpty);
      startExtraTime(s);
      final c = aiDecide(s, s.home, w, MatchRules.league).single as Substitute;
      expect((c.outId, c.inId), (8, 17));
    });
  });

  group('extra-time condition drain', () {
    test('is the normal drain × extraTimeDrainMul', () {
      const d = 0.35 - 0.17 / 3;
      final w = uniformWorld();
      final normal = startMatch(w);
      applySideEffects(normal, quietStep(), w, ScriptedRng([m, m]));
      expect(normal.home.condition[2], closeTo(100 - d, 1e-9));

      final et = startMatch(w);
      startExtraTime(et);
      applySideEffects(et, quietStep(), w, ScriptedRng([m, m]));
      expect(EngineTuning.extraTimeDrainMul, 1.2);
      expect(et.home.condition[2], closeTo(100 - d * 1.2, 1e-9));
      expect(et.away.condition[105], closeTo(100 - d * 1.2, 1e-9));
    });
  });

  group('playShootout', () {
    test('logs ShootoutStart, home kicks first, sides alternate', () {
      final w = uniformWorld();
      final s = startMatch(w)..minute = 120;
      playShootout(s, w, ScriptedRng([g, g, g, g, g, g, g, g, g, m]));
      final start = s.events.first as ShootoutStart;
      expect((start.minute, start.half, start.clubId), (120, 5, 1));
      expect(s.half, 5);
      expect(
        [for (final k in kicks(s)) k.clubId],
        [
          for (var i = 0; i < 5; i++) ...[1, 2],
        ],
      );
      for (final k in kicks(s)) {
        expect((k.minute, k.half), (120, 5));
      }
    });

    test('5–4 after the away side misses its fifth kick', () {
      final w = uniformWorld();
      final s = startMatch(w);
      final rng = ScriptedRng([g, g, g, g, g, g, g, g, g, m, g, g]);
      playShootout(s, w, rng);
      expect((s.homeShootout, s.awayShootout), (5, 4));
      expect(rng.used, 10);
      expect(s.shootoutWinner, 1);
    });

    test('3–0 ends after three rounds at the unreachable margin', () {
      final w = uniformWorld();
      final s = startMatch(w);
      final rng = ScriptedRng([g, m, g, m, g, m, g, g, g, g]);
      playShootout(s, w, rng);
      expect((s.homeShootout, s.awayShootout), (3, 0));
      expect(rng.used, 6);
    });

    test('0–3 ends after the away side scores its third', () {
      final w = uniformWorld();
      final s = startMatch(w);
      final rng = ScriptedRng([m, g, m, g, m, g, g, g, g, g]);
      playShootout(s, w, rng);
      expect((s.homeShootout, s.awayShootout), (0, 3));
      expect(rng.used, 6);
      expect(s.shootoutWinner, 2);
    });

    test('ends straight after a home kick the away side cannot answer', () {
      final w = uniformWorld();
      final s = startMatch(w);
      // After three rounds 3–1; home's fourth makes 4–1 with two away left.
      final rng = ScriptedRng([g, g, g, m, g, m, g, g, g]);
      playShootout(s, w, rng);
      expect((s.homeShootout, s.awayShootout), (4, 1));
      expect(rng.used, 7);
      expect(kicks(s).last.clubId, 1);
    });

    test('sudden death: 5–5, then 6–5', () {
      final w = uniformWorld();
      final s = startMatch(w);
      final rng = ScriptedRng([for (var i = 0; i < 10; i++) g, g, m, g]);
      playShootout(s, w, rng);
      expect((s.homeShootout, s.awayShootout), (6, 5));
      expect(rng.used, 12);
    });

    test('sudden death goes on while both score or both miss', () {
      final w = uniformWorld();
      final s = startMatch(w);
      final rng = ScriptedRng([
        for (var i = 0; i < 10; i++) g,
        m,
        m,
        g,
        g,
        m,
        g,
      ]);
      playShootout(s, w, rng);
      expect((s.homeShootout, s.awayShootout), (6, 7));
      expect(rng.used, 16);
      expect(s.shootoutWinner, 2);
    });

    test('kicker order: taker, composure + finishing, lower id, cycling', () {
      final w = uniformWorld();
      w.players[9]!.attrs
        ..set(Attr.finishing, 15)
        ..set(Attr.composure, 15);
      w.players[3]!.attrs
        ..set(Attr.finishing, 16)
        ..set(Attr.composure, 12);
      w.players[7]!.attrs.set(Attr.finishing, 18);
      w.players[4]!.attrs.set(Attr.composure, 18);
      final homeTactic = Tactic.preset(Formation.f442)..setPieces.penalty = 5;
      final awayTactic = Tactic.preset(Formation.f442)..setPieces.penalty = 105;
      final s = startMatch(w, homeTactic: homeTactic, awayTactic: awayTactic);
      // The away taker was sent off; the home bench never kicks.
      s.away.sentOff.add(105);
      s.away.removeFromPitch(105);
      // Eleven rounds all scored, then home scores and away misses.
      playShootout(s, w, ScriptedRng([for (var i = 0; i < 23; i++) g, m]));
      const homeOrder = [5, 9, 3, 4, 7, 1, 2, 6, 8, 10, 11];
      expect(kickers(s, 1), [...homeOrder, 5]);
      expect(kickers(s, 2), [
        101,
        102,
        103,
        104,
        106,
        107,
        108,
        109,
        110,
        111,
        101,
        102,
      ]);
      expect((s.homeShootout, s.awayShootout), (12, 11));
    });

    test(
      'an injured-off player never kicks; a taker off the pitch is skipped',
      () {
        final w = uniformWorld();
        final s = startMatch(
          w,
          homeTactic: Tactic.preset(Formation.f442)..setPieces.penalty = 99,
        );
        s.home.injuredOff.add(1);
        s.home.removeFromPitch(1);
        playShootout(s, w, ScriptedRng([for (var i = 0; i < 21; i++) g, m]));
        expect(kickers(s, 1), [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 2]);
      },
    );

    test(
      'probability: 0.76 × finishing factor × keeper factor, drawn against p',
      () {
        MatchState setUp(World w) => startMatch(
          w,
          homeTactic: Tactic.preset(Formation.f442)..setPieces.penalty = 9,
        );
        World world() {
          final w = uniformWorld();
          w.players[9]!.attrs
            ..set(Attr.finishing, 16)
            ..set(Attr.composure, 12);
          w.players[101]!.attrs.set(Attr.reflexes, 14);
          return w;
        }

        const p = 0.76 * (1 + 0.02 * 8) * (1 - 0.015 * 4);
        final w = world();
        expect(firstKickScores(setUp(w), w, p - 1e-9), isTrue);
        expect(firstKickScores(setUp(w), w, p + 1e-9), isFalse);

        // Uniform sides: 0.76 exactly.
        final u = uniformWorld();
        expect(firstKickScores(startMatch(u), u, 0.76 - 1e-9), isTrue);
        expect(firstKickScores(startMatch(u), u, 0.76 + 1e-9), isFalse);
      },
    );

    test('an empty keeper slot counts as gk 5', () {
      const p = 0.76 * (1 + 0.015 * 5);
      final w = uniformWorld();
      MatchState noKeeper() {
        final s = startMatch(w);
        s.away.sentOff.add(101);
        s.away.removeFromPitch(101);
        return s;
      }

      expect(firstKickScores(noKeeper(), w, p - 1e-9), isTrue);
      expect(firstKickScores(noKeeper(), w, p + 1e-9), isFalse);
    });

    test('the probability is clamped to 0.95 at the top', () {
      final w = uniformWorld();
      w.players[9]!.attrs
        ..set(Attr.finishing, 20)
        ..set(Attr.composure, 20);
      w.players[101]!.attrs.set(Attr.reflexes, 1);
      MatchState setUp() => startMatch(
        w,
        homeTactic: Tactic.preset(Formation.f442)..setPieces.penalty = 9,
      );
      expect(firstKickScores(setUp(), w, 0.95 - 1e-9), isTrue);
      expect(firstKickScores(setUp(), w, 0.95), isFalse);
    });

    test('the probability is clamped to 0.4 at the bottom', () {
      final w = uniformWorld();
      w.players[9]!.attrs
        ..set(Attr.finishing, 1)
        ..set(Attr.composure, 1);
      final keeper = w.players[101]!;
      keeper.attrs.set(Attr.reflexes, 20);
      keeper.state
        ..morale = 100
        ..form = 10;
      MatchState setUp() {
        final s = startMatch(
          w,
          homeTactic: Tactic.preset(Formation.f442)..setPieces.penalty = 9,
        );
        s.home.condition[9] = 0;
        return s;
      }

      // Effective values: kicker 0.5 + 0.5 at condition 0, keeper 22.05.
      final kicker = w.players[9]!;
      final slot = kicker.mainPosition;
      final sum =
          playerEffectiveness(kicker, Attr.finishing, slot, condition: 0) +
          playerEffectiveness(kicker, Attr.composure, slot, condition: 0);
      final gk = playerEffectiveness(keeper, Attr.reflexes, Position.gk);
      final raw = 0.76 * (1 + 0.02 * (sum - 20)) * (1 - 0.015 * (gk - 10));
      expect(raw, lessThan(0.4));
      expect(firstKickScores(setUp(), w, 0.4 - 1e-9), isTrue);
      expect(firstKickScores(setUp(), w, 0.4), isFalse);
    });

    test('leaves goals, stats and ratings untouched', () {
      final w = uniformWorld();
      final s = startMatch(w);
      s.home.goals = 2;
      s.away.goals = 2;
      s.ratings[3]!.value = 7.5;
      final before = {for (final e in s.ratings.entries) e.key: e.value.value};
      playShootout(s, w, ScriptedRng([g, g, g, g, g, g, g, g, g, m]));
      expect((s.home.goals, s.away.goals), (2, 2));
      for (final side in [s.home, s.away]) {
        expect(side.stats.shots, 0);
        expect(side.stats.onTarget, 0);
        expect(side.stats.xg, 0);
      }
      expect({for (final e in s.ratings.entries) e.key: e.value.value}, before);
    });

    test('shootoutWinner is null before a shootout', () {
      final s = startMatch(uniformWorld());
      expect(s.homeShootout, isNull);
      expect(s.awayShootout, isNull);
      expect(s.shootoutWinner, isNull);
    });

    test('same seed, same shootout', () {
      final w = uniformWorld();
      List<(ClubId, PlayerId, bool)> run() {
        final s = startMatch(w);
        playShootout(s, w, SeededRng(42));
        return [for (final k in kicks(s)) (k.clubId, k.playerId, k.scored)];
      }

      final a = run();
      expect(a.length, greaterThanOrEqualTo(6));
      expect(run(), a);
    });
  });
}
