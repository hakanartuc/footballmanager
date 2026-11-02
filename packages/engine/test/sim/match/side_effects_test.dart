import 'package:engine/engine.dart';
import 'package:test/test.dart';

import 'match_helpers.dart';

/// A 60-second home possession that ended off target, as the step
/// [applySideEffects] follows.
PossessionStep homeStep({ShotOutcome? outcome, PlayerId? shooter}) =>
    PossessionStep(
      minute: 1,
      half: 1,
      attackingId: 1,
      lane: Lane.centre,
      counter: false,
      seconds: 60,
      chance: outcome == null ? null : ChanceType.throughBall,
      outcome: outcome,
      shooter: shooter,
    );

/// No foul (0.99), no injury (0.99).
const quiet = [0.99, 0.99];

/// Foul by the first away player on the first home player, then [card],
/// [box] and [freeKick] (drawn only when [box] misses); no injury.
List<double> foul({
  double card = 0.5,
  double box = 0.5,
  double freeKick = 0.99,
}) => [0.0, 0.0, 0.0, card, box, freeKick, 0.99];

void main() {
  group('applySideEffects', () {
    test('a quiet step drains condition by stamina and leaves no events', () {
      final w = uniformWorld();
      w.players[2]!.attrs.set(Attr.stamina, 20);
      w.players[3]!.attrs.set(Attr.stamina, 5);
      final s = startMatch(w);
      s.minute = 1;
      final step = homeStep();
      applySideEffects(s, step, w, ScriptedRng(quiet));
      expect(s.events, isEmpty);
      expect(step.events, isEmpty);
      // Stamina 10 sits a third of the way from 5 to 20: 0.35 − 0.17 / 3.
      expect(s.home.condition[1], closeTo(100 - (0.35 - 0.17 / 3), 1e-9));
      expect(s.home.condition[2], closeTo(100 - 0.18, 1e-9));
      expect(s.home.condition[3], closeTo(100 - 0.35, 1e-9));
      expect(s.away.condition[101], closeTo(100 - (0.35 - 0.17 / 3), 1e-9));
      expect(s.home.stats.fouls, 0);
      expect(s.away.stats.fouls, 0);
    });

    test('drain scales with the step length, the tactic drain and clamps', () {
      final w = uniformWorld();
      final s = startMatch(
        w,
        awayTactic: Tactic.preset(Formation.f442)
          ..tempo = Tempo.fast
          ..pressing = Pressing.high,
      );
      s.home.condition[2] = 0.1;
      applySideEffects(s, homeStep()..seconds = 120, w, ScriptedRng(quiet));
      expect(s.home.condition[1], closeTo(100 - 2 * (0.35 - 0.17 / 3), 1e-9));
      expect(s.home.condition[2], 0);
      expect(
        s.away.condition[101],
        closeTo(100 - 2 * (0.35 - 0.17 / 3) * 1.3 * 1.25, 1e-9),
      );
    });

    test('an empty slot is skipped', () {
      final w = uniformWorld();
      final s = startMatch(w);
      s.home.onPitch[10] = null;
      applySideEffects(s, homeStep(), w, ScriptedRng(quiet));
      expect(s.home.condition[11], 100);
      expect(s.home.condition[10], lessThan(100));
    });

    test('a foul counts for the defending side; no card below the band', () {
      final w = uniformWorld();
      final s = startMatch(w);
      final rng = ScriptedRng(foul());
      applySideEffects(s, homeStep(), w, rng);
      expect(s.away.stats.fouls, 1);
      expect(s.home.stats.fouls, 0);
      expect(s.events, isEmpty);
      expect(s.pendingPenalty, isNull);
      expect(s.pendingFreeKick, isNull);
      expect(rng.used, 7);
    });

    test('the fouler is drawn by aggression from the defending side', () {
      final w = uniformWorld();
      w.players[105]!.attrs.set(Attr.aggression, 20);
      final s = startMatch(w);
      // Aggression weights 10 ×4, 20, 10 ×6 → r = 0.45 × 120 = 54 → id 105.
      final step = homeStep();
      applySideEffects(
        s,
        step,
        w,
        ScriptedRng([0.0, 0.45, 0.0, 0.05, 0.5, 0.99, 0.99]),
      );
      final b = step.events.single as Booking;
      expect(b.playerId, 105);
      expect(b.clubId, 2);
      expect(b.kind, CardKind.yellow);
      expect(b.reason, FoulKind.normal);
      expect(b.minute, 0);
      expect(b.half, 1);
      expect(s.events, [same(b)]);
      expect(s.away.yellows[105], 1);
      expect(s.away.stats.yellows, 1);
      expect(s.away.sentOff, isEmpty);
    });

    test('a foul records the fouler and the fouled on the step', () {
      final w = uniformWorld();
      w.players[105]!.attrs.set(Attr.aggression, 20);
      final s = startMatch(w);
      // Fouler 105 as above; victim 0.5 × 11 → index 5 → id 6; no card.
      final step = homeStep();
      applySideEffects(
        s,
        step,
        w,
        ScriptedRng([0.0, 0.45, 0.5, 0.5, 0.5, 0.99, 0.99]),
      );
      expect(step.fouler, 105);
      expect(step.fouled, 6);

      final quietStep = homeStep();
      applySideEffects(s, quietStep, w, ScriptedRng(quiet));
      expect(quietStep.fouler, isNull);
      expect(quietStep.fouled, isNull);
    });

    test('foul and card rates scale with tackling', () {
      final w = uniformWorld();
      final s = startMatch(
        w,
        awayTactic: Tactic.preset(Formation.f442)..tackling = Tackling.hard,
      );
      // 0.12 < 0.10 × 1.3 is a foul; 0.15 < 0.128 × 1.4 is a yellow.
      final step = homeStep();
      applySideEffects(
        s,
        step,
        w,
        ScriptedRng([0.12, 0.0, 0.0, 0.15, 0.5, 0.99, 0.99]),
      );
      expect(s.away.stats.fouls, 1);
      expect(s.away.stats.yellows, 1);

      final t = startMatch(w);
      applySideEffects(t, homeStep(), w, ScriptedRng([0.12, 0.99]));
      expect(t.away.stats.fouls, 0);
    });

    test('a second yellow sends the player off and empties the slot', () {
      final w = uniformWorld();
      final s = startMatch(w);
      s.away.yellows[101] = 1;
      s.away.stats.yellows = 1;
      final step = homeStep();
      applySideEffects(s, step, w, ScriptedRng(foul(card: 0.05)));
      final b = step.events.single as Booking;
      expect(b.playerId, 101);
      expect(b.kind, CardKind.secondYellow);
      expect(b.reason, FoulKind.normal);
      expect(s.away.yellows[101], 2);
      expect(s.away.sentOff, {101});
      expect(s.away.onPitch[0], isNull);
      expect(s.away.playing, awayIds.sublist(1));
      expect(s.away.stats.yellows, 2);
      expect(s.away.stats.reds, 1);
    });

    test('a straight red: reason by share, sent off', () {
      final reasons = {
        0.05: FoulKind.violent,
        0.2: FoulKind.lastMan,
        0.5: FoulKind.normal,
      };
      for (final MapEntry(key: r, value: reason) in reasons.entries) {
        final w = uniformWorld();
        final s = startMatch(w);
        final step = homeStep();
        // Foul, fouler, victim, card 0.001 (red), reason, box, free kick,
        // injury.
        applySideEffects(
          s,
          step,
          w,
          ScriptedRng([0.0, 0.0, 0.0, 0.001, r, 0.5, 0.99, 0.99]),
        );
        final b = step.events.single as Booking;
        expect(b.kind, CardKind.red);
        expect(b.reason, reason, reason: 'r = $r');
        expect(s.away.sentOff, {101});
        expect(s.away.onPitch[0], isNull);
        expect(s.away.stats.reds, 1);
        expect(s.away.stats.yellows, 0);
        expect(s.away.yellows[101], isNull);
      }
    });

    test('a foul in the box queues a penalty for the attacking side', () {
      final w = uniformWorld();
      final s = startMatch(w);
      s.pendingCounter = 2;
      // Box 0.01 < 0.02: no free-kick draw; the trailing 0.99 is the injury.
      final rng = ScriptedRng(foul(box: 0.01));
      applySideEffects(s, homeStep(), w, rng);
      expect(s.pendingPenalty, 1);
      expect(s.pendingFreeKick, isNull);
      expect(s.pendingCounter, isNull);
      expect(rng.used, 6);

      final t = startMatch(w);
      final awayStep = homeStep()..attackingId = 2;
      applySideEffects(t, awayStep, w, ScriptedRng(foul(box: 0.01)));
      expect(t.pendingPenalty, 2);
      expect(t.home.stats.fouls, 1);
    });

    test('a quarter of the other fouls queue a free kick', () {
      final w = uniformWorld();
      final s = startMatch(w);
      s.pendingCounter = 2;
      applySideEffects(s, homeStep(), w, ScriptedRng(foul(freeKick: 0.24)));
      expect(s.pendingFreeKick, 1);
      expect(s.pendingPenalty, isNull);
      expect(s.pendingCounter, isNull);

      final t = startMatch(w);
      t.pendingCounter = 2;
      applySideEffects(t, homeStep(), w, ScriptedRng(foul(freeKick: 0.26)));
      expect(t.pendingFreeKick, isNull);
      expect(t.pendingCounter, 2);
    });

    test('an injury takes the player off with a severity in days', () {
      final w = uniformWorld();
      final s = startMatch(w);
      s.minute = 30;
      s.half = 1;
      final step = homeStep();
      // No foul; injury 0.0; victim 0.0 (first home player); band minor,
      // 1 day, first type.
      applySideEffects(
        s,
        step,
        w,
        ScriptedRng([0.99, 0.0, 0.0, 0.0, 0.0, 0.0]),
      );
      final inj = step.events.single as Injury;
      expect(inj.playerId, 1);
      expect(inj.clubId, 1);
      expect(inj.severityDays, 1);
      expect(inj.injury.daysLeft, 1);
      expect(inj.injury.type, 'bruise');
      expect(inj.minute, 30);
      expect(s.events, [same(inj)]);
      expect(s.home.injuredOff, {1});
      expect(s.home.onPitch[0], isNull);
      expect(s.home.playing, homeIds.sublist(1));
    });

    test(
      'injury hazard: 0.0025 × mean multiplier; the victim of a foul ×4',
      () {
        // Proneness 10 → ×(0.5 + 1.5 × 9 / 19); everyone else alike.
        const m = 0.5 + 1.5 * 9 / 19;
        final w = uniformWorld();
        final quietS = startMatch(w);
        applySideEffects(
          quietS,
          homeStep(),
          w,
          ScriptedRng([0.99, 0.0025 * m - 1e-6, 0.0, 0.0, 0.0, 0.0]),
        );
        expect(quietS.home.injuredOff, {1});

        final t = startMatch(w);
        applySideEffects(
          t,
          homeStep(),
          w,
          ScriptedRng([0.99, 0.0025 * m + 1e-6]),
        );
        expect(t.home.injuredOff, isEmpty);

        // Foul on home player 1 (victim draw 0.0): the mean rises by 3 m / 22.
        final u = startMatch(w);
        final hazard = 0.0025 * m * 25 / 22;
        applySideEffects(
          u,
          homeStep(),
          w,
          ScriptedRng([
            0.0,
            0.0,
            0.0,
            0.5,
            0.5,
            0.99,
            hazard - 1e-6,
            0.0,
            0.0,
            0.0,
            0.0,
          ]),
        );
        expect(u.home.injuredOff, {1});
        final v = startMatch(w);
        applySideEffects(
          v,
          homeStep(),
          w,
          ScriptedRng([0.0, 0.0, 0.0, 0.5, 0.5, 0.99, hazard + 1e-6]),
        );
        expect(v.home.injuredOff, isEmpty);
      },
    );

    test('injury multipliers: condition, age, tempo, pitch, tackling', () {
      const m = 0.5 + 1.5 * 9 / 19;
      final w = uniformWorld();
      w.players[1]!.state.condition = 60;
      w.players[2]!.state.condition = 40;
      w.players[3]!.birth = GameDate.ymd(1990, 1, 1);
      w.players[101]!.hidden.injuryProneness = 20;
      final s = startMatch(
        w,
        homeTactic: Tactic.preset(Formation.f442)..tempo = Tempo.fast,
        awayTactic: Tactic.preset(Formation.f442)..tackling = Tackling.hard,
        cond: const MatchConditions(
          weather: Weather.rainy,
          pitch: 8,
          attendance: 1,
          homeAdvantage: 1.0,
        ),
      );
      // Home: fast tempo ×1.2, wet ×1.15, hard opponent ×1.4; player 1
      // ×1.5, 2 ×2.5, 3 ×1.3. Away: wet ×1.15, normal opponent; 101 ×2 / m.
      final home = m * 1.2 * 1.15 * 1.4;
      final homeSum = home * (1.5 + 2.5 + 1.3 + 8);
      final awaySum = m * 1.15 * 10 + 2.0 * 1.15;
      final hazard = 0.0025 * (homeSum + awaySum) / 22;
      applySideEffects(
        s,
        homeStep(),
        w,
        ScriptedRng([0.99, hazard - 1e-6, 0.0, 0.0, 0.0, 0.0]),
      );
      expect(s.home.injuredOff, {1});
      final t = startMatch(
        w,
        homeTactic: Tactic.preset(Formation.f442)..tempo = Tempo.fast,
        awayTactic: Tactic.preset(Formation.f442)..tackling = Tackling.hard,
        cond: const MatchConditions(
          weather: Weather.rainy,
          pitch: 8,
          attendance: 1,
          homeAdvantage: 1.0,
        ),
      );
      applySideEffects(t, homeStep(), w, ScriptedRng([0.99, hazard + 1e-6]));
      expect(t.home.injuredOff, isEmpty);
    });
  });

  group('rollInjury', () {
    test('band proportions, day ranges and types (20k rolls)', () {
      final rng = SeededRng(21);
      final counts = List.filled(5, 0);
      for (var i = 0; i < 20000; i++) {
        final inj = rollInjury(rng, fromFoul: false);
        final band = EngineTuning.injuryBandDays.indexWhere(
          (b) => inj.daysLeft >= b.$1 && inj.daysLeft <= b.$2,
        );
        expect(band, isNot(-1), reason: '${inj.daysLeft} days');
        expect(injuryTypes[band], contains(inj.type));
        counts[band]++;
      }
      const expected = [0.45, 0.30, 0.15, 0.08, 0.02];
      for (var b = 0; b < 5; b++) {
        expect(
          counts[b] / 20000,
          closeTo(expected[b], 0.02),
          reason: 'band $b',
        );
      }
    });

    test('a foul shifts the bands toward serious', () {
      final rng = SeededRng(22);
      var minor = 0;
      var serious = 0;
      for (var i = 0; i < 20000; i++) {
        final d = rollInjury(rng, fromFoul: true).daysLeft;
        if (d <= 7) minor++;
        if (d >= 57 && d <= 150) serious++;
      }
      expect(minor / 20000, closeTo(0.35, 0.02));
      expect(serious / 20000, closeTo(0.12, 0.02));
    });

    test('days are uniform inside the band', () {
      final rng = SeededRng(23);
      var low = 0;
      var n = 0;
      for (var i = 0; i < 20000; i++) {
        final d = rollInjury(rng, fromFoul: false).daysLeft;
        if (d > 7) continue;
        n++;
        if (d <= 3) low++;
      }
      expect(low / n, closeTo(3 / 7, 0.03));
    });

    test('every type key is assigned to exactly one band', () {
      final all = injuryTypes.expand((t) => t).toList();
      expect(all.toSet().length, all.length);
      expect(all, containsAll(['bruise', 'acl', 'brokenLeg', 'hamstring']));
      expect(injuryTypes.length, 5);
    });
  });
}
