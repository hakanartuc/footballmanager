import 'dart:convert';

import 'package:engine/engine.dart';
import 'package:test/test.dart';

import 'match_helpers.dart';

/// A small generated world; its fixtures give realistic lineups and tactics.
World _generated() => createNewGame(
  NewGameSpec(
    seed: 1,
    size: WorldSize.small,
    managerFirstName: 'T',
    managerLastName: 'M',
    managerCountryCode: 'TR',
    startClubId: null,
  ),
);

Fixture _firstFixture(World w) {
  final ids = w.fixtures.keys.toList()..sort();
  return w.fixtures[ids.first]!;
}

MatchContext _ctx(
  World w,
  Fixture f, {
  int seed = 1,
  MatchRules? rules,
  MatchDetail detail = MatchDetail.result,
  Lineup? home,
  Lineup? away,
}) => MatchContext(
  world: w,
  fixture: f,
  home: home ?? autoLineup(w, f.homeId),
  away: away ?? autoLineup(w, f.awayId),
  rng: SeededRng(seed).fork('match:${f.id}:${w.seasonYear}'),
  rules: rules,
  detail: detail,
);

/// [uniformWorld] plus a home bench 12..18 (gk, dc, mc, st, dl, mr, amc)
/// and an away bench 112..118 (the same positions).
World _benchWorld() {
  final w = uniformWorld();
  const positions = [
    Position.gk,
    Position.dc,
    Position.mc,
    Position.st,
    Position.dl,
    Position.mr,
    Position.amc,
  ];
  for (var i = 0; i < positions.length; i++) {
    w.players[12 + i] = uniformPlayer(12 + i, positions[i]);
    w.players[112 + i] = uniformPlayer(112 + i, positions[i]);
  }
  return w;
}

const _homeBench = [12, 13, 14, 15, 16, 17, 18];
const _awayBench = [112, 113, 114, 115, 116, 117, 118];

/// Club 1 (home) against club 2 on a uniform world with explicit 4-4-2
/// presets: the uniform world has no clubs to read a tactic from.
MatchContext _uniformCtx(
  World w, {
  int seed = 7,
  MatchRules? rules,
  MatchDetail detail = MatchDetail.result,
  List<PlayerId> homeBench = const [],
  List<PlayerId> awayBench = const [],
  List<PlayerId> homeStarters = homeIds,
  Tactic? homeTactic,
}) => MatchContext(
  world: w,
  fixture: fixture(),
  home: Lineup(
    formation: Formation.f442,
    starters: homeStarters,
    bench: homeBench,
  ),
  away: Lineup(formation: Formation.f442, starters: awayIds, bench: awayBench),
  rng: SeededRng(seed),
  rules: rules,
  conditions: conditions(),
  homeTactic: homeTactic ?? Tactic.preset(Formation.f442),
  awayTactic: Tactic.preset(Formation.f442),
  detail: detail,
);

const _cupRules = MatchRules(
  substitutions: 5,
  benchSize: 7,
  extraTime: true,
  penalties: true,
  yellowThresholds: [5, 10, 15],
  redBanSecondYellow: 1,
  redBanFoul: 3,
  redBanViolent: 4,
);

String _json(MatchResult r) => jsonEncode(matchResultToJson(r));

/// Every player's condition except the keepers', so fatigue substitutions
/// happen within ninety minutes.
void _tireOutfield(World w, double condition) {
  for (final id in [...homeIds, ...awayIds]) {
    if (id != 1 && id != 101) w.players[id]!.state.condition = condition;
  }
}

void main() {
  group('a league match on a generated world', () {
    final w = _generated();
    final f = _firstFixture(w);
    final result = const PossessionMatchSimulator().simulate(_ctx(w, f));

    test('runs two halves with one to six minutes added to each', () {
      final halfTimes = result.events.whereType<HalfTime>().toList();
      final fullTimes = result.events.whereType<FullTime>().toList();
      expect(halfTimes, hasLength(1));
      expect(fullTimes, hasLength(1));
      expect(halfTimes.single.half, 1);
      expect(fullTimes.single.half, 2);
      // The boundary step ends at or after 45 + added, at most a step later.
      expect(halfTimes.single.minute, inInclusiveRange(46, 52));
      expect(fullTimes.single.minute, inInclusiveRange(91, 97));
      expect(result.events.whereType<ExtraTimeStart>(), isEmpty);
      expect(result.homeShootout, isNull);
      expect(result.abandoned, isFalse);
    });

    test('scores, goal list and statistics agree', () {
      final goals = result.events.whereType<Goal>().toList();
      expect(result.homeGoals, goals.where((g) => g.clubId == f.homeId).length);
      expect(result.awayGoals, goals.where((g) => g.clubId == f.awayId).length);
      expect(result.goals, hasLength(goals.length));
      for (var i = 0; i < goals.length; i++) {
        expect(result.goals[i].minute, goals[i].minute);
        expect(result.goals[i].scorerId, goals[i].scorerId);
        expect(result.goals[i].clubId, goals[i].clubId);
      }
      final home = result.homeStats!;
      final away = result.awayStats!;
      expect(home.shots, greaterThanOrEqualTo(home.onTarget));
      expect(home.onTarget, greaterThanOrEqualTo(result.homeGoals));
      expect(away.shots, greaterThanOrEqualTo(away.onTarget));
      expect(away.onTarget, greaterThanOrEqualTo(result.awayGoals));
      expect(home.possessionPct + away.possessionPct, 100);
      expect(home.possessionPct, inInclusiveRange(20, 80));
      expect(result.conditions, isNotNull);
    });

    test('rates the players and names a rated man of the match', () {
      expect(result.ratings, isNotEmpty);
      expect(result.ratings.keys, contains(result.manOfTheMatch));
      for (final v in result.ratings.values) {
        expect(v, inInclusiveRange(1, 10));
      }
    });

    test('uses the club tactic when the lineup is in its formation', () {
      final session = MatchSession(_ctx(w, f));
      expect(session.state.home.tactic, same(w.clubs[f.homeId]!.tactic));
      final other = MatchSession(
        _ctx(w, f, home: autoLineup(w, f.homeId, formation: Formation.f433)),
      );
      expect(other.state.home.tactic.formation, Formation.f433);
      expect(other.state.home.tactic, isNot(same(w.clubs[f.homeId]!.tactic)));
    });
  });

  group('extra time and shootout', () {
    final w = _generated();
    final f = _firstFixture(w);
    MatchResult? shootout;
    MatchResult? decidedInExtraTime;
    for (var seed = 1; seed <= 400; seed++) {
      final r = const PossessionMatchSimulator().simulate(
        _ctx(w, f, seed: seed, rules: _cupRules),
      );
      if (r.events.whereType<ExtraTimeStart>().isEmpty) continue;
      if (r.homeShootout != null) {
        shootout ??= r;
      } else {
        decidedInExtraTime ??= r;
      }
      if (shootout != null && decidedInExtraTime != null) break;
    }

    test('a level match plays two extra halves and a shootout', () {
      final r = shootout!;
      final et = r.events.whereType<ExtraTimeStart>().single;
      expect(et.minute, 90);
      expect(et.half, 3);
      final halfTimes = r.events.whereType<HalfTime>().toList();
      expect(halfTimes.map((e) => e.half), [1, 3]);
      expect(halfTimes[1].minute, inInclusiveRange(106, 112));
      expect(r.events.whereType<ShootoutStart>(), hasLength(1));
      expect(r.events.whereType<ShootoutKick>(), isNotEmpty);
      final ft = r.events.whereType<FullTime>().single;
      expect(ft.half, 5);
      expect(ft.minute, greaterThanOrEqualTo(121));
      expect(r.homeGoals, r.awayGoals);
      expect(r.homeShootout, isNot(r.awayShootout));
      // The shootout changes neither the score nor the goal list.
      expect(r.goals, hasLength(r.homeGoals + r.awayGoals));
      expect(r.events.whereType<Goal>(), hasLength(r.goals.length));
    });

    test('a match decided in extra time ends after the fourth half', () {
      final r = decidedInExtraTime!;
      expect(r.events.whereType<FullTime>().single.half, 4);
      expect(r.events.whereType<ShootoutStart>(), isEmpty);
      expect(r.homeShootout, isNull);
      expect(r.awayShootout, isNull);
      expect(r.homeGoals, isNot(r.awayGoals));
    });
  });

  group('abandonment', () {
    test('a side below seven players: finished, abandoned, 0-3', () {
      final w = uniformWorld();
      final session = MatchSession(_uniformCtx(w));
      for (final id in [7, 8, 9, 10, 11]) {
        session.state.home.sentOff.add(id);
        session.state.home.removeFromPitch(id);
      }
      expect(session.finished, isFalse);
      final steps = session.step();
      expect(steps, hasLength(1));
      expect(session.finished, isTrue);
      expect(session.step(), isEmpty);
      final r = session.finish();
      expect(r.abandoned, isTrue);
      expect(r.homeGoals, 0);
      expect(r.awayGoals, 3);
      expect(r.events.whereType<FullTime>(), hasLength(1));
    });
  });

  group('apply', () {
    test(
      'a substitution between steps changes the result deterministically',
      () {
        final w = _benchWorld();
        MatchSession start() {
          final s = MatchSession(_uniformCtx(w, homeBench: _homeBench));
          s.step(count: 10);
          return s;
        }

        const sub = Substitute(1, outId: 10, inId: 15);
        final a = start()..apply(sub);
        final b = start()..apply(sub);
        final c = start();
        final ra = a.finish();
        final rb = b.finish();
        final rc = c.finish();
        expect(_json(ra), _json(rb));
        expect(_json(ra), isNot(_json(rc)));
        // Ours is the first substitution; the AI may add injury ones later.
        final e = ra.events.whereType<Substitution>().first;
        expect(e.outId, 10);
        expect(e.inId, 15);
        expect(e.reason, SubReason.tactical);
        expect(e.minute, a.state.events.whereType<Substitution>().first.minute);
        expect(
          rc.events.whereType<Substitution>().map((e) => e.reason),
          isNot(contains(SubReason.tactical)),
        );
      },
    );

    test('propagates CommandError kinds and leaves the state unchanged', () {
      final w = _benchWorld();
      final s = MatchSession(_uniformCtx(w, homeBench: _homeBench));
      s.step();
      expect(
        () => s.apply(const Substitute(1, outId: 13, inId: 15)),
        throwsA(
          isA<CommandError>().having(
            (e) => e.kind,
            'kind',
            CommandErrorKind.notOnPitch,
          ),
        ),
      );
      expect(
        () => s.apply(const Substitute(1, outId: 10, inId: 11)),
        throwsA(
          isA<CommandError>().having(
            (e) => e.kind,
            'kind',
            CommandErrorKind.notOnBench,
          ),
        ),
      );
      expect(s.state.home.onPitch, homeIds);
      expect(s.state.home.bench, _homeBench);
      expect(s.state.events.whereType<Substitution>(), isEmpty);
    });

    test('throws StateError once the match is finished', () {
      final w = _benchWorld();
      final s = MatchSession(_uniformCtx(w, homeBench: _homeBench));
      s.finish();
      expect(
        () => s.apply(const SetMentality(1, Mentality.attacking)),
        throwsStateError,
      );
    });
  });

  group('user-managed sides', () {
    test('get no AI commands while the other side still does', () {
      final w = _benchWorld();
      _tireOutfield(w, 70);
      final session = MatchSession(
        _uniformCtx(w, homeBench: _homeBench, awayBench: _awayBench),
      );
      session.setUserManaged(1, true);
      // Home is far behind: the AI would raise its mentality from minute 60.
      session.state.away.goals = 5;
      final r = session.finish();
      final ai = r.events.where((e) => e is TacticChange || e is Substitution);
      expect(ai.where((e) => e.clubId == 1), isEmpty);
      expect(
        r.events.whereType<Substitution>().where((e) => e.clubId == 2),
        isNotEmpty,
      );
      expect(
        r.events
            .whereType<TacticChange>()
            .where((e) => e.clubId == 2)
            .map((e) => e.mentality),
        [Mentality.defensive],
      );
      // Without the flag the home side shifts up and substitutes.
      final control = MatchSession(
        _uniformCtx(w, homeBench: _homeBench, awayBench: _awayBench),
      );
      control.state.away.goals = 5;
      final rc = control.finish();
      expect(
        rc.events
            .whereType<TacticChange>()
            .where((e) => e.clubId == 1)
            .map((e) => e.mentality),
        [Mentality.attacking],
      );
      expect(
        rc.events.whereType<Substitution>().where((e) => e.clubId == 1),
        isNotEmpty,
      );
    });
  });

  group('AI cadence', () {
    test(
      'commands appear only at check intervals or right after an injury',
      () {
        final w = _benchWorld();
        _tireOutfield(w, 70);
        final session = MatchSession(
          _uniformCtx(w, homeBench: _homeBench, awayBench: _awayBench),
        );
        session.state.away.goals = 1;
        // Minute of the last step in which each side issued commands; one
        // check can issue several, all at that step's minute.
        final lastCommand = <ClubId, int>{1: 0, 2: 0};
        var commands = 0;
        while (!session.finished) {
          final before = session.state.events.length;
          session.step();
          final fresh = session.state.events.skip(before).toList();
          final injured = {for (final e in fresh.whereType<Injury>()) e.clubId};
          final issued = <ClubId, int>{};
          for (final e in fresh) {
            if (e is! TacticChange && e is! Substitution) continue;
            commands++;
            issued[e.clubId] = e.minute;
          }
          for (final MapEntry(key: club, value: minute) in issued.entries) {
            if (!injured.contains(club)) {
              expect(
                minute,
                greaterThanOrEqualTo(
                  lastCommand[club]! + EngineTuning.aiCheckInterval,
                ),
                reason: 'commands for $club at $minute',
              );
            }
            lastCommand[club] = minute;
          }
        }
        expect(commands, greaterThan(2));
      },
    );
  });

  group('finish and log', () {
    test('finish is idempotent and returns the same object', () {
      final w = uniformWorld();
      final s = MatchSession(_uniformCtx(w));
      final a = s.finish();
      expect(s.finish(), same(a));
      expect(s.step(), isEmpty);
      expect(s.runUntil(), isEmpty);
    });

    test('log is null unless the detail is full', () {
      final w = uniformWorld();
      expect(MatchSession(_uniformCtx(w)).log, isNull);
      expect(
        MatchSession(_uniformCtx(w, detail: MatchDetail.events)).log,
        isNull,
      );
      final full = MatchSession(_uniformCtx(w, detail: MatchDetail.full));
      expect(full.log, isNotNull);
      var steps = 0;
      while (!full.finished) {
        steps += full.step().length;
      }
      expect(full.log!.steps, hasLength(steps));
      expect(full.state.log, same(full.log!.steps));
    });

    test('runUntil stops after a goal, a card, an injury or a break', () {
      final w = uniformWorld();
      final s = MatchSession(_uniformCtx(w));
      while (!s.finished) {
        final steps = s.runUntil();
        final last = s.state.events.length;
        if (!s.finished) {
          // Every stop but the last is explained by an event of its step.
          final stop = s.state.events.sublist(last - 1);
          expect(
            stop.any(
              (e) =>
                  e is Goal ||
                  e is Booking ||
                  e is Injury ||
                  e is PenaltyMissed ||
                  e is HalfTime,
            ),
            isTrue,
            reason: 'stopped after ${steps.length} steps at ${s.minute}',
          );
        }
      }
      expect(s.state.events.last, isA<FullTime>());
    });

    test('runUntil a minute stops there without an event', () {
      final w = uniformWorld();
      final s = MatchSession(_uniformCtx(w));
      s.runUntil(minute: 20, stopOnEvent: false);
      expect(s.minute, greaterThanOrEqualTo(20));
      expect(s.minute, lessThan(23));
      expect(s.finished, isFalse);
    });
  });

  group('construction', () {
    test('rejects a tactic whose slots do not match the starters', () {
      final w = uniformWorld();
      expect(
        () =>
            MatchSession(_uniformCtx(w, homeStarters: homeIds.sublist(0, 10))),
        throwsArgumentError,
      );
    });

    test('draws the match seed first, then plays on the same stream', () {
      final w = uniformWorld();
      final rng = SeededRng(7);
      final seed = rng.nextUint32();
      final r = MatchSession(_uniformCtx(w, seed: 7)).finish();
      expect(r.matchSeed, seed);
    });
  });
}
