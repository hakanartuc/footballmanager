import 'package:engine/engine.dart';
import 'package:test/test.dart';

import 'match_helpers.dart';

/// [uniformWorld] plus a home bench 12..18 (gk, dc, mc, st, dl, mr, amc)
/// and an away bench 112..113 (gk, dc).
World benchWorld() {
  final w = uniformWorld();
  const home = {
    12: Position.gk,
    13: Position.dc,
    14: Position.mc,
    15: Position.st,
    16: Position.dl,
    17: Position.mr,
    18: Position.amc,
  };
  const away = {112: Position.gk, 113: Position.dc};
  for (final MapEntry(key: id, value: pos) in home.entries) {
    w.players[id] = uniformPlayer(id, pos);
  }
  for (final MapEntry(key: id, value: pos) in away.entries) {
    w.players[id] = uniformPlayer(id, pos);
  }
  return w;
}

const homeBench = [12, 13, 14, 15, 16, 17, 18];
const awayBench = [112, 113];

MatchState benchMatch(World w, {List<PlayerId> bench = homeBench}) =>
    startMatch(w, homeBench: bench, awayBench: awayBench);

Matcher commandError(CommandErrorKind kind) =>
    throwsA(isA<CommandError>().having((e) => e.kind, 'kind', kind));

/// Takes [id] off the home pitch as injured.
void injureOff(MatchState s, PlayerId id) {
  s.home.injuredOff.add(id);
  s.home.removeFromPitch(id);
}

/// Takes [id] off the home pitch as sent off.
void sendOff(MatchState s, PlayerId id) {
  s.home.sentOff.add(id);
  s.home.removeFromPitch(id);
}

void main() {
  group('applyCommand Substitute', () {
    test('fills the same slot, leaves the bench, counts and rebuilds', () {
      final w = benchWorld();
      w.players[15]!.state.condition = 80;
      final s = benchMatch(w);
      s.minute = 70;
      s.half = 2;
      applyCommand(
        s,
        w,
        MatchRules.league,
        const Substitute(1, outId: 10, inId: 15),
      );
      expect(s.home.onPitch[9], 15);
      expect(s.home.onPitch.where((id) => id == 10), isEmpty);
      expect(s.home.bench, [12, 13, 14, 16, 17, 18]);
      expect(s.home.subsUsed, 1);
      expect(s.home.condition[15], 80);
      final e = s.events.single as Substitution;
      expect(e.outId, 10);
      expect(e.inId, 15);
      expect(e.reason, SubReason.tactical);
      expect(e.clubId, 1);
      expect(e.minute, 70);
      expect(e.half, 2);
      expect(s.home.profile.onPitch, contains(15));
      expect(s.home.profile.onPitch, isNot(contains(10)));
      expect(s.home.profile.slotOf[15], Position.st);
      expect(s.ratings.containsKey(15), isTrue);
    });

    test('works for the away side', () {
      final w = benchWorld();
      final s = benchMatch(w);
      applyCommand(
        s,
        w,
        MatchRules.league,
        const Substitute(2, outId: 103, inId: 113),
      );
      expect(s.away.onPitch[2], 113);
      expect(s.away.subsUsed, 1);
      expect(s.home.subsUsed, 0);
    });

    test('rejects the same player out and in', () {
      final w = benchWorld();
      final s = benchMatch(w);
      expect(
        () => applyCommand(
          s,
          w,
          MatchRules.league,
          const Substitute(1, outId: 15, inId: 15),
        ),
        commandError(CommandErrorKind.sameSide),
      );
    });

    test('rejects an outgoing player who is not on the pitch', () {
      final w = benchWorld();
      final s = benchMatch(w);
      expect(
        () => applyCommand(
          s,
          w,
          MatchRules.league,
          const Substitute(1, outId: 13, inId: 15),
        ),
        commandError(CommandErrorKind.notOnPitch),
      );
      expect(
        () => applyCommand(
          s,
          w,
          MatchRules.league,
          const Substitute(1, outId: 103, inId: 15),
        ),
        commandError(CommandErrorKind.notOnPitch),
      );
    });

    test('rejects an incoming player who is not on the bench', () {
      final w = benchWorld();
      final s = benchMatch(w);
      expect(
        () => applyCommand(
          s,
          w,
          MatchRules.league,
          const Substitute(1, outId: 10, inId: 11),
        ),
        commandError(CommandErrorKind.notOnBench),
      );
      expect(
        () => applyCommand(
          s,
          w,
          MatchRules.league,
          const Substitute(1, outId: 10, inId: 113),
        ),
        commandError(CommandErrorKind.notOnBench),
      );
    });

    test('rejects when the substitutions are used up', () {
      final w = benchWorld();
      final s = benchMatch(w);
      s.home.subsUsed = MatchRules.league.substitutions;
      expect(
        () => applyCommand(
          s,
          w,
          MatchRules.league,
          const Substitute(1, outId: 10, inId: 15),
        ),
        commandError(CommandErrorKind.noSubsLeft),
      );
    });

    test('rejects an injured bench player', () {
      final w = benchWorld();
      w.players[15]!.state.injury = InjuryStub(daysLeft: 3, type: 'bruise');
      final s = benchMatch(w);
      expect(
        () => applyCommand(
          s,
          w,
          MatchRules.league,
          const Substitute(1, outId: 10, inId: 15),
        ),
        commandError(CommandErrorKind.ineligible),
      );
    });

    test('a rejected command changes nothing', () {
      final w = benchWorld();
      final s = benchMatch(w);
      s.home.subsUsed = MatchRules.league.substitutions;
      expect(
        () => applyCommand(
          s,
          w,
          MatchRules.league,
          const Substitute(1, outId: 10, inId: 15),
        ),
        commandError(CommandErrorKind.noSubsLeft),
      );
      expect(s.home.onPitch, homeIds);
      expect(s.home.bench, homeBench);
      expect(s.events, isEmpty);
    });

    test('a sent-off player\'s slot cannot be refilled', () {
      final w = benchWorld();
      final s = benchMatch(w);
      sendOff(s, 10);
      expect(
        () => applyCommand(
          s,
          w,
          MatchRules.league,
          const Substitute(1, outId: 10, inId: 15),
        ),
        commandError(CommandErrorKind.notOnPitch),
      );
      expect(s.home.onPitch[9], isNull);
    });

    test('fills the emptied slot of a player injured off, reason injury', () {
      final w = benchWorld();
      final s = benchMatch(w);
      injureOff(s, 10);
      expect(s.home.onPitch[9], isNull);
      applyCommand(
        s,
        w,
        MatchRules.league,
        const Substitute(1, outId: 10, inId: 15),
      );
      expect(s.home.onPitch[9], 15);
      expect(s.home.playing.length, 11);
      expect((s.events.single as Substitution).reason, SubReason.injury);
      expect(s.home.profile.onPitch, contains(15));

      // The old id cannot be used again once its slot is filled.
      expect(
        () => applyCommand(
          s,
          w,
          MatchRules.league,
          const Substitute(1, outId: 10, inId: 13),
        ),
        commandError(CommandErrorKind.notOnPitch),
      );
    });

    test(
      'same slot injured again after a refill: only the latest id works',
      () {
        final w = benchWorld();
        final s = benchMatch(w);
        injureOff(s, 10);
        applyCommand(
          s,
          w,
          MatchRules.league,
          const Substitute(1, outId: 10, inId: 15),
        );
        injureOff(s, 15);
        expect(s.home.onPitch[9], isNull);

        expect(
          () => applyCommand(
            s,
            w,
            MatchRules.league,
            const Substitute(1, outId: 10, inId: 13),
          ),
          commandError(CommandErrorKind.notOnPitch),
        );
        expect(s.home.onPitch[9], isNull);

        applyCommand(
          s,
          w,
          MatchRules.league,
          const Substitute(1, outId: 15, inId: 13),
        );
        expect(s.home.onPitch[9], 13);
        expect((s.events.last as Substitution).outId, 15);
        expect((s.events.last as Substitution).reason, SubReason.injury);
      },
    );

    test('a slot whose substitute was then sent off stays empty', () {
      final w = benchWorld();
      final s = benchMatch(w);
      injureOff(s, 10);
      applyCommand(
        s,
        w,
        MatchRules.league,
        const Substitute(1, outId: 10, inId: 15),
      );
      sendOff(s, 15);
      expect(
        () => applyCommand(
          s,
          w,
          MatchRules.league,
          const Substitute(1, outId: 10, inId: 13),
        ),
        commandError(CommandErrorKind.notOnPitch),
      );
    });
  });

  group('applyCommand tactics', () {
    test('SetMentality copies the tactic, logs and rebuilds', () {
      final w = benchWorld();
      final original = Tactic.preset(Formation.f442);
      final s = startMatch(w, homeTactic: original);
      s.minute = 61;
      s.half = 2;
      final attBefore = s.home.profile.attC;
      applyCommand(
        s,
        w,
        MatchRules.league,
        const SetMentality(1, Mentality.attacking),
      );
      expect(s.home.tactic.mentality, Mentality.attacking);
      expect(s.home.tactic.slots, original.slots);
      expect(original.mentality, Mentality.balanced);
      final e = s.events.single as TacticChange;
      expect(e.mentality, Mentality.attacking);
      expect(e.clubId, 1);
      expect(e.minute, 61);
      expect(e.half, 2);
      expect(s.home.profile.attC / attBefore, closeTo(1.08, 1e-9));
    });

    test('SetTactic swaps the whole tactic, slots included', () {
      final w = benchWorld();
      final s = benchMatch(w);
      final t = Tactic.preset(Formation.f433)..mentality = Mentality.defensive;
      applyCommand(s, w, MatchRules.league, SetTactic(1, t));
      expect(s.home.tactic, same(t));
      expect(s.home.onPitch, homeIds);
      expect((s.events.single as TacticChange).mentality, Mentality.defensive);
      // Slot 5 is ml in 4-4-2 and mc in 4-3-3; player 6 keeps slot 5.
      expect(s.home.profile.slotOf[6], Position.mc);
    });

    test('SetTactic rejects a tactic without eleven slots or a keeper', () {
      final w = benchWorld();
      final s = benchMatch(w);
      final ten = Tactic(
        name: 'ten',
        formation: Formation.custom,
        slots: formationSlots(Formation.f442).sublist(0, 10),
      );
      expect(
        () => applyCommand(s, w, MatchRules.league, SetTactic(1, ten)),
        commandError(CommandErrorKind.invalidTactic),
      );
      final noKeeper = Tactic(
        name: 'nogk',
        formation: Formation.custom,
        slots: [...formationSlots(Formation.f442).sublist(1), Position.st],
      );
      expect(
        () => applyCommand(s, w, MatchRules.league, SetTactic(1, noKeeper)),
        commandError(CommandErrorKind.invalidTactic),
      );
      expect(s.home.tactic.formation, Formation.f442);
      expect(s.events, isEmpty);
    });
  });

  group('aiDecide mentality', () {
    test('behind from minute 60: one step up, once', () {
      final w = benchWorld();
      final s = benchMatch(w);
      s.away.goals = 1;
      s.minute = 59;
      expect(aiDecide(s, s.home, w, MatchRules.league), isEmpty);
      s.minute = 60;
      final cmds = aiDecide(s, s.home, w, MatchRules.league);
      final c = cmds.single as SetMentality;
      expect(c.clubId, 1);
      expect(c.mentality, Mentality.attacking);
      applyCommand(s, w, MatchRules.league, c);
      s.minute = 65;
      expect(aiDecide(s, s.home, w, MatchRules.league), isEmpty);
      // The side that is ahead does nothing before 75.
      expect(aiDecide(s, s.away, w, MatchRules.league), isEmpty);
    });

    test('behind at very attacking: nothing to raise', () {
      final w = benchWorld();
      final s = startMatch(
        w,
        homeTactic: Tactic.preset(Formation.f442)
          ..mentality = Mentality.veryAttacking,
      );
      s.away.goals = 1;
      s.minute = 60;
      expect(aiDecide(s, s.home, w, MatchRules.league), isEmpty);
    });

    test('ahead from minute 75: one step down, once', () {
      final w = benchWorld();
      final s = benchMatch(w);
      s.away.goals = 2;
      s.home.goals = 1;
      s.minute = 74;
      expect(aiDecide(s, s.away, w, MatchRules.league), isEmpty);
      s.minute = 75;
      final c =
          aiDecide(s, s.away, w, MatchRules.league).single as SetMentality;
      expect(c.clubId, 2);
      expect(c.mentality, Mentality.defensive);
      applyCommand(s, w, MatchRules.league, c);
      s.minute = 80;
      expect(aiDecide(s, s.away, w, MatchRules.league), isEmpty);
    });

    test('level: no shift', () {
      final w = benchWorld();
      final s = benchMatch(w);
      s.minute = 80;
      expect(aiDecide(s, s.home, w, MatchRules.league), isEmpty);
      expect(aiDecide(s, s.away, w, MatchRules.league), isEmpty);
    });

    test('a user-managed side gets no mentality shift', () {
      final w = benchWorld();
      final s = benchMatch(w);
      s.home.userManaged = true;
      s.away.goals = 1;
      s.minute = 60;
      expect(aiDecide(s, s.home, w, MatchRules.league), isEmpty);
      s.away.goals = 0;
      s.home.goals = 1;
      s.minute = 75;
      expect(aiDecide(s, s.home, w, MatchRules.league), isEmpty);
    });
  });

  group('aiDecide fatigue', () {
    test('condition below 65: the bench player of the same position', () {
      final w = benchWorld();
      w.players[14]!.ca = 150;
      final s = benchMatch(w);
      s.home.condition[10] = 64.9;
      final c = aiDecide(s, s.home, w, MatchRules.league).single as Substitute;
      expect(c.clubId, 1);
      expect(c.outId, 10);
      expect(c.inId, 15);
      expect(c.reason, SubReason.fatigue);
      s.home.condition[10] = 65;
      expect(aiDecide(s, s.home, w, MatchRules.league), isEmpty);
    });

    test('no same position: familiarity 12 beats a higher CA', () {
      final w = benchWorld();
      w.players[14]!.familiarity[Position.mr] = 12;
      w.players[13]!.ca = 150;
      final s = benchMatch(w, bench: [12, 13, 14, 15, 16, 18]);
      s.home.condition[9] = 50;
      final c = aiDecide(s, s.home, w, MatchRules.league).single as Substitute;
      expect(c.outId, 9);
      expect(c.inId, 14);
    });

    test('no position or familiarity match: the highest CA', () {
      final w = benchWorld();
      w.players[13]!.ca = 150;
      final s = benchMatch(w, bench: [12, 13, 14, 15, 16, 18]);
      s.home.condition[9] = 50;
      final c = aiDecide(s, s.home, w, MatchRules.league).single as Substitute;
      expect(c.inId, 13);
    });

    test('the most tired first, distinct substitutes, within the budget', () {
      final w = benchWorld();
      final s = benchMatch(w);
      s.home.condition[10] = 60;
      s.home.condition[11] = 50;
      s.home.condition[7] = 55;
      final cmds = aiDecide(s, s.home, w, MatchRules.league).cast<Substitute>();
      expect(cmds.map((c) => c.outId), [11, 7, 10]);
      expect(cmds.map((c) => c.inId).toSet().length, 3);
      expect(cmds[0].inId, 15);
      expect(cmds[1].inId, 14);
      for (final c in cmds) {
        applyCommand(s, w, MatchRules.league, c);
      }
      expect(s.home.subsUsed, 3);
      expect(s.home.playing.length, 11);

      final t = benchMatch(w);
      t.home.subsUsed = MatchRules.league.substitutions - 1;
      t.home.condition[10] = 60;
      t.home.condition[11] = 50;
      final one =
          aiDecide(t, t.home, w, MatchRules.league).single as Substitute;
      expect(one.outId, 11);
    });

    test('a tired keeper is not substituted', () {
      final w = benchWorld();
      final s = benchMatch(w);
      s.home.condition[1] = 30;
      expect(aiDecide(s, s.home, w, MatchRules.league), isEmpty);
    });

    test('an empty bench or an injured bench player gives nothing', () {
      final w = benchWorld();
      final s = benchMatch(w, bench: []);
      s.home.condition[10] = 50;
      expect(aiDecide(s, s.home, w, MatchRules.league), isEmpty);
      w.players[15]!.state.injury = InjuryStub(daysLeft: 3, type: 'bruise');
      final t = benchMatch(w, bench: [15]);
      t.home.condition[10] = 50;
      expect(aiDecide(t, t.home, w, MatchRules.league), isEmpty);
    });

    test('a user-managed side still gets fatigue subs', () {
      final w = benchWorld();
      final s = benchMatch(w);
      s.home.userManaged = true;
      s.home.condition[10] = 50;
      final c = aiDecide(s, s.home, w, MatchRules.league).single as Substitute;
      expect(c.outId, 10);
    });
  });

  group('aiDecide forced', () {
    test('an injured slot is refilled first, reason injury', () {
      final w = benchWorld();
      final s = benchMatch(w);
      s.minute = 60;
      s.away.goals = 1;
      injureOff(s, 10);
      final cmds = aiDecide(s, s.home, w, MatchRules.league);
      expect(cmds.length, 2);
      final sub = cmds[0] as Substitute;
      expect(sub.outId, 10);
      expect(sub.inId, 15);
      expect(sub.reason, SubReason.injury);
      expect(cmds[1], isA<SetMentality>());
      applyCommand(s, w, MatchRules.league, sub);
      expect(s.home.onPitch[9], 15);
      expect(s.home.playing.length, 11);
      expect((s.events.single as Substitution).reason, SubReason.injury);
      expect(aiDecide(s, s.home, w, MatchRules.league), isEmpty);
    });

    test('a user-managed side still gets the forced sub', () {
      final w = benchWorld();
      final s = benchMatch(w);
      s.home.userManaged = true;
      injureOff(s, 10);
      final c = aiDecide(s, s.home, w, MatchRules.league).single as Substitute;
      expect(c.outId, 10);
      expect(c.reason, SubReason.injury);
    });

    test('no substitutions left: plays short, slot stays empty', () {
      final w = benchWorld();
      final s = benchMatch(w);
      s.home.subsUsed = MatchRules.league.substitutions;
      injureOff(s, 10);
      expect(aiDecide(s, s.home, w, MatchRules.league), isEmpty);
      expect(s.home.onPitch[9], isNull);
      expect(s.home.playing.length, 10);
    });

    test('a sent-off slot is never refilled', () {
      final w = benchWorld();
      final s = benchMatch(w);
      sendOff(s, 10);
      expect(aiDecide(s, s.home, w, MatchRules.league), isEmpty);
    });

    test('an injured keeper: the bench keeper, else the best outfielder', () {
      final w = benchWorld();
      final s = benchMatch(w);
      injureOff(s, 1);
      final c = aiDecide(s, s.home, w, MatchRules.league).single as Substitute;
      expect(c.outId, 1);
      expect(c.inId, 12);

      w.players[13]!.ca = 150;
      final t = benchMatch(w, bench: [13, 14, 15]);
      injureOff(t, 1);
      final d = aiDecide(t, t.home, w, MatchRules.league).single as Substitute;
      expect(d.inId, 13);
    });

    test('forced subs and fatigue subs share the budget', () {
      final w = benchWorld();
      final s = benchMatch(w);
      s.home.subsUsed = MatchRules.league.substitutions - 1;
      s.home.condition[11] = 50;
      injureOff(s, 10);
      final c = aiDecide(s, s.home, w, MatchRules.league).single as Substitute;
      expect(c.outId, 10);
      expect(c.reason, SubReason.injury);
    });
  });

  group('checkAbandon', () {
    test('both sides with seven or more: the match goes on', () {
      final w = benchWorld();
      final s = benchMatch(w);
      for (var i = 7; i < 11; i++) {
        s.home.onPitch[i] = null;
      }
      expect(s.home.playing.length, 7);
      expect(checkAbandon(s), isFalse);
      expect(s.abandoned, isFalse);
      expect(s.events, isEmpty);
    });

    test('below seven: abandoned, 0-3 against the short side, full time', () {
      final w = benchWorld();
      final s = benchMatch(w);
      s.minute = 55;
      s.half = 2;
      s.home.goals = 2;
      for (var i = 6; i < 11; i++) {
        s.home.onPitch[i] = null;
      }
      expect(checkAbandon(s), isTrue);
      expect(s.abandoned, isTrue);
      expect(s.home.goals, 0);
      expect(s.away.goals, 3);
      final e = s.events.single as FullTime;
      expect(e.minute, 55);
      expect(e.half, 2);
      // A second call reports the abandonment without a second full time.
      expect(checkAbandon(s), isTrue);
      expect(s.events.length, 1);

      final t = benchMatch(w);
      for (var i = 6; i < 11; i++) {
        t.away.onPitch[i] = null;
      }
      expect(checkAbandon(t), isTrue);
      expect(t.home.goals, 3);
      expect(t.away.goals, 0);
    });

    test('both sides short: abandoned 0-0', () {
      final w = benchWorld();
      final s = benchMatch(w);
      s.home.goals = 1;
      s.away.goals = 2;
      for (var i = 6; i < 11; i++) {
        s.home.onPitch[i] = null;
        s.away.onPitch[i] = null;
      }
      expect(checkAbandon(s), isTrue);
      expect(s.home.goals, 0);
      expect(s.away.goals, 0);
      expect(s.events.single, isA<FullTime>());
    });
  });
}
