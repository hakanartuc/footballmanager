/// Spec 5.3 step 11: the coordinates of each possession step in detailed
/// mode, drawn from the visual stream only.
library;

import 'dart:convert';

import 'package:engine/engine.dart';
import 'package:test/test.dart';

import 'match_helpers.dart';

World _world() => createNewGame(
  NewGameSpec(
    seed: 1,
    size: WorldSize.small,
    managerFirstName: 'T',
    managerLastName: 'M',
    managerCountryCode: 'TR',
    startClubId: null,
  ),
);

List<Fixture> _fixtures(World w, int n) {
  final ids = w.fixtures.keys.toList()..sort();
  return [for (final id in ids.take(n)) w.fixtures[id]!];
}

MatchContext _ctx(World w, Fixture f, MatchDetail detail) => MatchContext(
  world: w,
  fixture: f,
  home: autoLineup(w, f.homeId),
  away: autoLineup(w, f.awayId),
  rng: SeededRng(w.seed).fork('match:${f.id}:${w.seasonYear}'),
  detail: detail,
);

/// A step with who was on the pitch for each side just before it.
class _Seen {
  _Seen(this.step, this.att, this.def, this.keeper);

  final PossessionStep step;
  final Set<PlayerId> att;
  final Set<PlayerId> def;

  /// The defending keeper before the step.
  final PlayerId? keeper;
}

PlayerId? _keeperOf(SideState side) {
  final i = side.tactic.slots.indexOf(Position.gk);
  return i == -1 ? null : side.onPitch[i];
}

/// Plays [f] in full detail one step at a time.
List<_Seen> _play(World w, Fixture f) {
  final session = MatchSession(_ctx(w, f, MatchDetail.full));
  final out = <_Seen>[];
  while (!session.finished) {
    final s = session.state;
    final playing = {
      s.home.clubId: s.home.playing.toSet(),
      s.away.clubId: s.away.playing.toSet(),
    };
    final keepers = {
      s.home.clubId: _keeperOf(s.home),
      s.away.clubId: _keeperOf(s.away),
    };
    for (final step in session.step()) {
      final defId = step.attackingId == s.home.clubId
          ? s.away.clubId
          : s.home.clubId;
      out.add(
        _Seen(
          step,
          playing[step.attackingId]!,
          playing[defId]!,
          keepers[defId],
        ),
      );
    }
  }
  return out;
}

bool _isAttacking(MicroEvent e) =>
    e is Pass || e is Dribble || e is Cross || e is Shot;

List<Pt> _points(MicroEvent e) => switch (e) {
  Pass(:final a, :final b) => [a, b],
  Dribble(:final a, :final b) => [a, b],
  Cross(:final a, :final b) => [a, b],
  Shot(:final a, :final target) => [a, target],
  Tackle(:final at) => [at],
  Foul(:final at) => [at],
  Save(:final at) => [at],
  Clearance(:final a, :final b) => [a, b],
};

List<PlayerId> _attackers(MicroEvent e) => switch (e) {
  Pass(:final from, :final to) => [from, to],
  Dribble(:final who) => [who],
  Cross(:final from, :final to) => [from, to],
  Shot(:final who) => [who],
  Tackle(:final victim) => [victim],
  Foul(:final victim) => [victim],
  Save() || Clearance() => [],
};

List<PlayerId> _defenders(MicroEvent e) => switch (e) {
  Tackle(:final who) => [who],
  Foul(:final who) => [who],
  Save(:final keeper) => [keeper],
  Clearance(:final who) => [who],
  Shot(:final keeperId) => [?keeperId],
  Pass() || Dribble() || Cross() => [],
};

String _pt(Pt p) => '(${p.x},${p.y})';

String _dump(MicroEvent e) => switch (e) {
  Pass(:final t, :final from, :final to, :final a, :final b) =>
    'pass $t $from $to ${_pt(a)} ${_pt(b)}',
  Dribble(:final t, :final who, :final a, :final b) =>
    'dribble $t $who ${_pt(a)} ${_pt(b)}',
  Cross(:final t, :final from, :final to, :final a, :final b) =>
    'cross $t $from $to ${_pt(a)} ${_pt(b)}',
  Shot(:final t, :final who, :final a, :final target, :final outcome) =>
    'shot $t $who ${_pt(a)} ${_pt(target)} $outcome ${e.keeperId}',
  Tackle(:final t, :final who, :final victim, :final at) =>
    'tackle $t $who $victim ${_pt(at)}',
  Foul(:final t, :final who, :final victim, :final at) =>
    'foul $t $who $victim ${_pt(at)}',
  Save(:final t, :final keeper, :final at) => 'save $t $keeper ${_pt(at)}',
  Clearance(:final t, :final who, :final a, :final b) =>
    'clearance $t $who ${_pt(a)} ${_pt(b)}',
};

String _dumpAll(List<PossessionStep> steps) =>
    [for (final s in steps) s.micro.map(_dump).join('; ')].join('\n');

/// A home chance on the uniform 4-4-2 (home 1 gk, 2 dl, 3–4 dc, 5 dr,
/// 6 ml, 7–8 mc, 9 mr, 10–11 st; away 101..111 the same).
PossessionStep _step({
  ChanceType? chance,
  Lane lane = Lane.left,
  PlayerId? shooter,
  PlayerId? assister,
  ShotOutcome? outcome,
  bool counter = false,
  PlayerId? fouler,
  PlayerId? fouled,
}) =>
    PossessionStep(
        minute: 10,
        half: 1,
        attackingId: 1,
        lane: lane,
        counter: counter,
        seconds: 30,
        chance: chance,
        shooter: shooter,
        assister: assister,
        outcome: outcome,
      )
      ..fouler = fouler
      ..fouled = fouled;

/// Builds [step]'s events on a fresh uniform match with every visual draw
/// equal to [v].
List<MicroEvent> _build(PossessionStep step, double v) {
  final s = startMatch(uniformWorld());
  return buildMicroEvents(
    step,
    s.side(step.attackingId),
    s.opponent(step.attackingId),
    ScriptedRng(List.filled(64, v)),
  );
}

const _draws = [0.0, 0.5, 0.999];

Matcher _within(double lo, double hi) => inInclusiveRange(lo, hi);

void main() {
  group('50 generated fixtures in full detail', () {
    final w = _world();
    final fixtures = _fixtures(w, 50);
    final seen = [for (final f in fixtures) ..._play(w, f)];
    final chances = [
      for (final s in seen)
        if (s.step.chance != null) s,
    ];
    final quiet = [
      for (final s in seen)
        if (s.step.chance == null) s,
    ];

    test('every step has events within the pitch and a steady clock', () {
      for (final s in seen) {
        final m = s.step.micro;
        final isSetShot =
            s.step.chance == ChanceType.penalty ||
            s.step.chance == ChanceType.freeKick;
        expect(m.length, _within(isSetShot ? 1 : 2, 6));
        expect(m.first.t, 0.0);
        for (var i = 1; i < m.length; i++) {
          final gap = m[i].t - m[i - 1].t;
          if (m[i] is Save) {
            expect(gap, closeTo(0.5, 1e-9));
          } else {
            expect(gap, _within(1.0, 2.5));
          }
        }
        for (final e in m) {
          for (final p in _points(e)) {
            expect(p.x, _within(0, 100));
            expect(p.y, _within(0, 100));
          }
        }
      }
    });

    test('a chance ends its attack with the step\'s shot', () {
      var saves = 0;
      for (final s in chances) {
        final step = s.step;
        final shot = step.micro.lastWhere(_isAttacking) as Shot;
        expect(shot.who, step.shooter);
        expect(shot.outcome, step.outcome);
        expect(shot.target.y, 100);
        expect(shot.target.x, _within(44, 56));
        expect(shot.keeperId, anyOf(isNull, s.keeper));
        final save = step.micro.whereType<Save>().toList();
        if (step.outcome == ShotOutcome.saved && shot.keeperId != null) {
          saves++;
          expect(save.single.keeper, shot.keeperId);
          expect(save.single.at, same(shot.target));
          expect(save.single.t, closeTo(shot.t + 0.5, 1e-9));
        } else {
          expect(save, isEmpty);
        }
        expect(step.micro.whereType<Tackle>(), isEmpty);
        expect(step.micro.whereType<Clearance>(), isEmpty);
        if (step.chance == ChanceType.penalty) {
          expect(step.micro.where(_isAttacking).single, same(shot));
          expect(shot.a.x, 50);
          expect(shot.a.y, 89);
        }
      }
      expect(saves, greaterThan(0));
    });

    test('the assister passes or crosses to the shooter last', () {
      var n = 0;
      for (final s in chances) {
        final step = s.step;
        if (step.assister == null) continue;
        n++;
        final delivery = step.micro.where((e) => e is Pass || e is Cross).last;
        final (from, to) = switch (delivery) {
          Pass(:final from, :final to) => (from, to),
          Cross(:final from, :final to) => (from, to),
          _ => throw StateError('unreachable'),
        };
        expect(from, step.assister);
        expect(to, step.shooter);
      }
      expect(n, greaterThan(0));
    });

    test('a step without a chance ends in a tackle or a clearance', () {
      for (final s in quiet) {
        final last = s.step.micro.last;
        expect(last, anyOf(isA<Tackle>(), isA<Clearance>()));
        expect(_defenders(last).single, isIn(s.def));
        expect(s.step.micro.length, _within(2, 4));
      }
    });

    test('a foul appears exactly when the step has a fouler', () {
      var fouls = 0;
      for (final s in seen) {
        final f = s.step.micro.whereType<Foul>().toList();
        if (s.step.fouler == null) {
          expect(f, isEmpty);
        } else {
          fouls++;
          expect(f.single.who, s.step.fouler);
          expect(f.single.victim, s.step.fouled);
        }
      }
      expect(fouls, greaterThan(0));
    });

    test('participants come from the right side', () {
      for (final s in seen) {
        for (final e in s.step.micro) {
          for (final id in _attackers(e)) {
            expect(id, isIn(s.att), reason: _dump(e));
          }
          for (final id in _defenders(e)) {
            expect(id, isIn(s.def), reason: _dump(e));
          }
        }
      }
    });

    test('result JSON is the same with and without the coordinates', () {
      String json(Fixture f, MatchDetail d) =>
          jsonEncode(matchResultToJson(MatchSession(_ctx(w, f, d)).finish()));
      for (final f in fixtures) {
        expect(
          json(f, MatchDetail.full),
          json(f, MatchDetail.result),
          reason: 'fixture ${f.id}',
        );
      }
    });
  });

  test('the same seed gives the same coordinates', () {
    final w = _world();
    final f = _fixtures(w, 1).single;
    List<PossessionStep> run() {
      final s = MatchSession(_ctx(w, f, MatchDetail.full))..finish();
      return s.log!.steps;
    }

    final a = _dumpAll(run());
    expect(a, isNotEmpty);
    expect(_dumpAll(run()), a);
  });

  test('outside full detail the steps carry no coordinates', () {
    final w = _world();
    final f = _fixtures(w, 1).single;
    final s = MatchSession(_ctx(w, f, MatchDetail.events));
    while (!s.finished) {
      for (final step in s.step()) {
        expect(step.micro, isEmpty);
      }
    }
  });

  test('buildMicroEvents changes neither the step nor the sides', () {
    final w = uniformWorld();
    final s = startMatch(w);
    s.away.yellows[103] = 1;
    final step = _step(
      chance: ChanceType.cross,
      shooter: 10,
      assister: 6,
      outcome: ShotOutcome.saved,
      fouler: 103,
      fouled: 10,
    );
    String dumpStep() =>
        '${step.minute} ${step.half} ${step.attackingId} ${step.lane} '
        '${step.counter} ${step.seconds} ${step.chance} ${step.xg} '
        '${step.outcome} ${step.shooter} ${step.assister} ${step.fouler} '
        '${step.fouled} ${step.micro.length} ${step.events.length}';
    String dumpSide(SideState x) =>
        '${x.onPitch} ${x.bench} ${x.condition} ${x.yellows} ${x.sentOff} '
        '${x.injuredOff} ${x.formerSlot} ${x.subsUsed} ${x.goals} '
        '${x.possessionSeconds} ${x.tactic.slots} '
        '${jsonEncode(teamStatsToJson(x.stats))}';
    final before = [dumpStep(), dumpSide(s.home), dumpSide(s.away)];
    final micro = buildMicroEvents(
      step,
      s.home,
      s.away,
      ScriptedRng(List.filled(64, 0.5)),
    );
    expect(micro, isNotEmpty);
    expect([dumpStep(), dumpSide(s.home), dumpSide(s.away)], before);
  });

  group('choreography per chance type', () {
    test('cross: from the wing of the lane to the shooter in the box', () {
      for (final lane in [Lane.left, Lane.right]) {
        for (final v in _draws) {
          final m = _build(
            _step(
              chance: ChanceType.cross,
              lane: lane,
              shooter: 10,
              assister: lane == Lane.left ? 6 : 9,
              outcome: ShotOutcome.saved,
            ),
            v,
          );
          final cross = m.whereType<Cross>().single;
          expect(cross.from, lane == Lane.left ? 6 : 9);
          expect(cross.to, 10);
          expect(
            cross.a.x,
            lane == Lane.left
                ? lessThanOrEqualTo(20)
                : greaterThanOrEqualTo(80),
          );
          expect(cross.a.y, _within(80, 92));
          expect(cross.b.x, _within(40, 60));
          expect(cross.b.y, _within(88, 96));
          final shot = m[m.length - 2] as Shot;
          expect(shot.a, same(cross.b));
          expect(shot.keeperId, 101);
          final save = m.last as Save;
          expect(save.keeper, 101);
          expect(save.at, same(shot.target));
          // Own-half start in the lane band.
          final first = m.first;
          final start = _points(first).first;
          expect(start.y, _within(30, 50));
          expect(
            start.x,
            lane == Lane.left ? _within(15, 35) : _within(65, 85),
          );
        }
      }
    });

    test('through ball: ends in the box within the lane band', () {
      for (final v in _draws) {
        final m = _build(
          _step(
            chance: ChanceType.throughBall,
            lane: Lane.right,
            shooter: 11,
            assister: 9,
            outcome: ShotOutcome.goal,
          ),
          v,
        );
        final pass = m[m.length - 2] as Pass;
        expect(pass.from, 9);
        expect(pass.to, 11);
        expect(pass.b.y, _within(85, 95));
        expect(pass.b.x, _within(65, 85));
        expect((m.last as Shot).outcome, ShotOutcome.goal);
      }
    });

    test('long shot: taken from y 70–78', () {
      for (final v in _draws) {
        final m = _build(
          _step(
            chance: ChanceType.longShot,
            lane: Lane.centre,
            shooter: 8,
            assister: 7,
            outcome: ShotOutcome.off,
          ),
          v,
        );
        final shot = m.last as Shot;
        expect(shot.a.y, _within(70, 78));
        final pass = m[m.length - 2] as Pass;
        expect(pass.from, 7);
        expect(pass.to, 8);
        expect(pass.b, same(shot.a));
      }
    });

    test('dribble: a diagonal toward the centre ending at y 80–90', () {
      for (final lane in [Lane.left, Lane.right]) {
        for (final v in _draws) {
          final m = _build(
            _step(
              chance: ChanceType.dribble,
              lane: lane,
              shooter: 10,
              outcome: ShotOutcome.blocked,
            ),
            v,
          );
          final d = m[m.length - 2] as Dribble;
          expect(d.who, 10);
          final dx = d.b.x - d.a.x;
          expect(lane == Lane.left ? dx : -dx, _within(10, 20));
          expect(d.b.y - d.a.y, _within(10, 15));
          expect(d.b.y, _within(80, 90));
          // The ball reaches the shooter from the first carrier.
          final pass = m[m.length - 3] as Pass;
          expect(pass.to, 10);
          expect(pass.from, isIn([2, 6, 5, 9]));
        }
      }
    });

    test('corner: from the flag of the lane, crossed into the box', () {
      for (final lane in [Lane.left, Lane.right]) {
        for (final v in _draws) {
          final m = _build(
            _step(
              chance: ChanceType.corner,
              lane: lane,
              shooter: 4,
              assister: 6,
              outcome: ShotOutcome.off,
            ),
            v,
          );
          expect(m, hasLength(2));
          final cross = m.first as Cross;
          expect(cross.from, 6);
          expect(cross.to, 4);
          expect(cross.a.x, lane == Lane.left ? 0 : 100);
          expect(cross.a.y, 100);
          expect(cross.b.x, _within(40, 60));
          expect(cross.b.y, _within(90, 97));
          expect((m.last as Shot).a, same(cross.b));
        }
      }
    });

    test('free kick without an assister: a direct shot from y 70–80', () {
      for (final v in _draws) {
        final m = _build(
          _step(
            chance: ChanceType.freeKick,
            lane: Lane.left,
            shooter: 10,
            outcome: ShotOutcome.post,
          ),
          v,
        );
        final shot = m.single as Shot;
        expect(shot.who, 10);
        expect(shot.a.y, _within(70, 80));
        expect(shot.a.x, _within(15, 35));
      }
    });

    test('penalty: one shot from the spot, then the save', () {
      final m = _build(
        _step(
          chance: ChanceType.penalty,
          lane: Lane.centre,
          shooter: 10,
          outcome: ShotOutcome.saved,
        ),
        0.5,
      );
      expect(m, hasLength(2));
      final shot = m.first as Shot;
      expect(shot.t, 0.0);
      expect(shot.a.x, 50);
      expect(shot.a.y, 89);
      expect((m.last as Save).keeper, 101);
    });

    test('an empty keeper slot: no save, no keeper on the shot', () {
      final s = startMatch(uniformWorld());
      s.away.onPitch[0] = null;
      final m = buildMicroEvents(
        _step(
          chance: ChanceType.penalty,
          shooter: 10,
          outcome: ShotOutcome.saved,
        ),
        s.home,
        s.away,
        ScriptedRng(List.filled(64, 0.5)),
      );
      expect((m.single as Shot).keeperId, isNull);
    });

    test('counter: starts at y 45–55 with one long pass', () {
      for (final v in _draws) {
        final m = _build(_step(lane: Lane.left, counter: true), v);
        expect(m, hasLength(2));
        final pass = m.first as Pass;
        expect(pass.a.y, _within(45, 55));
        expect(pass.from, isIn([2, 6]));
      }
    });

    test('no chance: a tackle (60%) or a clearance by a defender', () {
      final tackle = _build(_step(lane: Lane.left), 0.0);
      final t = tackle.last as Tackle;
      // The attackers' left meets the defenders' right lane (dr 105, mr 109).
      expect(t.who, isIn([105, 109]));
      final carrier = switch (tackle[tackle.length - 2]) {
        Pass(:final to) => to,
        Dribble(:final who) => who,
        _ => throw StateError('unexpected'),
      };
      expect(t.victim, carrier);
      expect(t.at, same(_points(tackle[tackle.length - 2]).last));

      final clear = _build(_step(lane: Lane.left), 0.999);
      final c = clear.last as Clearance;
      expect(c.who, isIn([105, 109]));
      expect(c.b.y, lessThanOrEqualTo(c.a.y - 15));
      expect(c.b.y, greaterThanOrEqualTo(0));
    });

    test('a foul comes before the tackle, at the ball', () {
      final m = _build(_step(lane: Lane.right, fouler: 103, fouled: 7), 0.0);
      final foul = m[m.length - 2] as Foul;
      expect(foul.who, 103);
      expect(foul.victim, 7);
      expect(foul.at, same(_points(m[m.length - 3]).last));
      expect(m.last, isA<Tackle>());
    });

    test('a foul on a chance step follows the shot and the save', () {
      final m = _build(
        _step(
          chance: ChanceType.penalty,
          shooter: 10,
          outcome: ShotOutcome.saved,
          fouler: 104,
          fouled: 10,
        ),
        0.0,
      );
      expect(m.map((e) => e.runtimeType), [Shot, Save, Foul]);
      expect((m.last as Foul).at, same((m.first as Shot).a));
    });
  });
}
