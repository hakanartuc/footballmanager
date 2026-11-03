import '../../core/ids.dart';
import '../../core/rng.dart';
import '../../model/enums.dart';
import '../../model/match_log.dart';
import '../../model/match_result.dart';
import '../../model/tactic.dart';
import 'match_state.dart';

/// Seconds between two events, drawn uniformly.
const double _gapMin = 1.0;
const double _gapMax = 2.5;

/// A [Save] follows its [Shot] by this many seconds; nothing is drawn.
const double _saveDelay = 0.5;

/// Share of the no-chance steps that end in a [Tackle] (else a
/// [Clearance]).
const double _tackleShare = 0.6;

/// Spec 5.3 step 11: the coordinated events of [step] for the detailed
/// mode, in the attackers' frame (they play upward; y 100 is the goal they
/// shoot at), every point clamped to 0..100. Pure: reads [step],
/// [attacking] and [defending], draws only from [visualRng] and changes
/// nothing (the caller stores the list in `step.micro`).
///
/// Times start at 0.0; every later event follows the previous one by a gap
/// in `_gapMin..._gapMax`, a [Save] by `_saveDelay`.
///
/// The ball starts in the lane's x band (left 15–35, centre 40–60, right
/// 65–85; "drift" is the band ± 10) at y 30–50, y 45–55 on a counter, with
/// the first carrier: an attacker in a slot of the step's lane, defenders
/// and midfielders first, any attacker when the lane is empty. Choreography
/// (a "move" to a team-mate is a [Pass], to the carrier himself a
/// [Dribble]; the deliverer is the assister, else the first carrier):
///  - through ball: extra pass, move to the deliverer (drift, y 58–72), move
///    to the shooter (band, y 85–95).
///  - cross: extra pass, move to the deliverer on the wing (x 5–20 or 80–95,
///    y 80–92; the centre lane draws its wing), [Cross] to the shooter
///    (x 40–60, y 88–96).
///  - long shot: extra pass, move to the deliverer (drift, y 55–65), move to
///    the shooter (drift, y 70–78).
///  - dribble: move to the shooter, then his [Dribble] 10–20 across toward
///    the centre (the centre lane draws the side) and 10–15 up, ending at
///    y 80–90.
///  - corner: the taker (the assister, else the first carrier) at the flag
///    of the lane (x 0 left, 100 right, drawn for the centre; y 100),
///    [Cross] to the shooter (x 40–60, y 90–97).
///  - free kick: the spot (band, y 70–80); a direct shot, or with an
///    assister his [Pass] to the shooter (drift, y 78–88).
///  - penalty: the shot from (50, 89), nothing before it.
/// The extra pass is an optional first pass (drift, y 50–58) to an outfield
/// team-mate other than the carrier, assister and shooter, only with an
/// assister and not on a counter; a counter's first move is its one long
/// pass. A chance ends with the [Shot] by the shooter from the ball (target
/// x 44–56 on the goal line, the step's outcome, the defending keeper as
/// `keeperId`) and, when saved and the keeper's slot is filled, the [Save]
/// at the target.
///
/// A step without a chance: one or two passes (one long pass on a counter)
/// to outfield team-mates, y rising (50–62 then 62–75; 55–75 alone; 65–80
/// on a counter), ending with a defender of the facing lane (the
/// attackers' left meets the defenders' right; any outfield defender when
/// it is empty) who [Tackle]s the carrier at the ball or [Clearance]s it
/// 15–30 lower (x ± 10).
///
/// A foul ([PossessionStep.fouler]) adds a [Foul] on `fouled` at the ball
/// after the last attacking event (after the [Save] on a chance step, at
/// the shot's origin) and before the tackle or clearance.
///
/// Draw order on [visualRng]: the first carrier (`pick`, not for a penalty
/// or free kick, nor a corner with an assister); the corner flag (centre
/// lane only); the start point or spot (x, then y); the extra pass
/// (`nextBool(0.5)`, then the receiver's `pick`) or, without a chance and
/// not on a counter, the pass count (`nextInt(2)`); then each event in
/// order: its receiver (`pick`), its point draws (a wing or direction
/// first, then x before y), its gap (none for the first event, none for a
/// [Save]). A step without a chance draws its defender (`pick`) and Tackle
/// vs Clearance (`nextDouble`) before the last event's points and gap.
List<MicroEvent> buildMicroEvents(
  PossessionStep step,
  SideState attacking,
  SideState defending,
  Rng visualRng,
) => _Choreography(step, attacking, defending, visualRng).build();

class _Choreography {
  _Choreography(this.step, this.att, this.def, this.rng);

  final PossessionStep step;
  final SideState att;
  final SideState def;
  final Rng rng;
  final List<MicroEvent> out = [];
  late PlayerId carrier;
  late Pt ball;

  List<MicroEvent> build() {
    if (step.chance case final type?) {
      _chance(type, step.shooter!, step.assister);
    } else {
      _noChance();
    }
    return out;
  }

  void _chance(ChanceType type, PlayerId shooter, PlayerId? assister) {
    switch (type) {
      case ChanceType.throughBall:
        final deliverer = _openPlay(assister, shooter);
        _move(deliverer, _pt(_driftX(), _u(58, 72)));
        _move(shooter, _pt(_laneX(), _u(85, 95)));
      case ChanceType.cross:
        final deliverer = _openPlay(assister, shooter);
        final left = _leftSide();
        _move(deliverer, _pt(left ? _u(5, 20) : _u(80, 95), _u(80, 92)));
        _move(shooter, _pt(_u(40, 60), _u(88, 96)), cross: true);
      case ChanceType.longShot:
        final deliverer = _openPlay(assister, shooter);
        _move(deliverer, _pt(_driftX(), _u(55, 65)));
        _move(shooter, _pt(_driftX(), _u(70, 78)));
      case ChanceType.dribble:
        _openPlay(assister, shooter);
        final toCentre = switch (step.lane) {
          Lane.left => 1.0,
          Lane.right => -1.0,
          Lane.centre => rng.nextBool(0.5) ? 1.0 : -1.0,
        };
        final endY = _u(80, 90);
        final from = _pt(_laneX(), endY - _u(10, 15));
        _move(shooter, from);
        _move(shooter, _pt(from.x + toCentre * _u(10, 20), endY));
      case ChanceType.corner:
        carrier = assister ?? _firstCarrier();
        ball = Pt(_leftSide() ? 0 : 100, 100);
        _move(shooter, _pt(_u(40, 60), _u(90, 97)), cross: true);
      case ChanceType.freeKick:
        carrier = assister ?? shooter;
        ball = _pt(_laneX(), _u(70, 80));
        if (assister != null) _move(shooter, _pt(_driftX(), _u(78, 88)));
      case ChanceType.penalty:
        carrier = shooter;
        ball = const Pt(50, 89);
    }

    final keeper = _keeper();
    final target = _pt(_u(44, 56), 100);
    final t = _next();
    out.add(Shot(t, shooter, ball, target, step.outcome!, keeper));
    if (step.outcome == ShotOutcome.saved && keeper != null) {
      out.add(Save(t + _saveDelay, keeper, target));
    }
    _foul();
  }

  /// The open-play start and the optional extra pass; returns the
  /// deliverer (the assister, else the first carrier).
  PlayerId _openPlay(PlayerId? assister, PlayerId shooter) {
    _start();
    final deliverer = assister ?? carrier;
    if (assister != null && !step.counter && rng.nextBool(0.5)) {
      final mate = _mate({carrier, assister, shooter});
      if (mate != null) _move(mate, _pt(_driftX(), _u(50, 58)));
    }
    return deliverer;
  }

  void _noChance() {
    _start();
    final passes = step.counter ? 1 : 1 + rng.nextInt(2);
    for (var i = 0; i < passes; i++) {
      final (lo, hi) = step.counter
          ? (65.0, 80.0)
          : passes == 1
          ? (55.0, 75.0)
          : i == 0
          ? (50.0, 62.0)
          : (62.0, 75.0);
      _move(_mate({carrier}) ?? carrier, _pt(_driftX(), _u(lo, hi)));
    }
    _foul();
    final who = _defender();
    if (rng.nextDouble() < _tackleShare) {
      out.add(Tackle(_next(), who, carrier, ball));
    } else {
      final b = _pt(ball.x + _u(-10, 10), ball.y - _u(15, 30));
      out.add(Clearance(_next(), who, ball, b));
    }
  }

  void _start() {
    carrier = _firstCarrier();
    ball = step.counter ? _pt(_laneX(), _u(45, 55)) : _pt(_laneX(), _u(30, 50));
  }

  /// Moves the ball to [b] and [to]: a [Pass] (or [Cross]) from the
  /// carrier, a [Dribble] when [to] is the carrier.
  void _move(PlayerId to, Pt b, {bool cross = false}) {
    final t = _next();
    out.add(
      to == carrier
          ? Dribble(t, carrier, ball, b)
          : cross
          ? Cross(t, carrier, to, ball, b)
          : Pass(t, carrier, to, ball, b),
    );
    carrier = to;
    ball = b;
  }

  void _foul() {
    final fouler = step.fouler;
    if (fouler == null) return;
    out.add(Foul(_next(), fouler, step.fouled ?? carrier, ball));
  }

  double _next() => out.isEmpty ? 0.0 : out.last.t + _u(_gapMin, _gapMax);

  double _u(double lo, double hi) => lo + rng.nextDouble() * (hi - lo);

  (double, double) get _band => switch (step.lane) {
    Lane.left => (15, 35),
    Lane.centre => (40, 60),
    Lane.right => (65, 85),
  };

  double _laneX() => _u(_band.$1, _band.$2);

  double _driftX() => _u(_band.$1 - 10, _band.$2 + 10);

  /// Left for the left lane, right for the right; drawn for the centre.
  bool _leftSide() => switch (step.lane) {
    Lane.left => true,
    Lane.right => false,
    Lane.centre => rng.nextBool(0.5),
  };

  /// An attacker in a slot of the step's lane, defenders and midfielders
  /// first; any attacker when the lane is empty.
  PlayerId _firstCarrier() {
    final inLane = <PlayerId>[];
    final preferred = <PlayerId>[];
    for (var i = 0; i < att.onPitch.length; i++) {
      final id = att.onPitch[i];
      final pos = att.tactic.slots[i];
      if (id == null || laneOf(pos) != step.lane) continue;
      inLane.add(id);
      if (pos.group == PositionGroup.def || pos.group == PositionGroup.mid) {
        preferred.add(id);
      }
    }
    return rng.pick(
      preferred.isNotEmpty
          ? preferred
          : inLane.isNotEmpty
          ? inLane
          : att.playing,
    );
  }

  /// An outfield attacker not in [except]; null when there is none.
  PlayerId? _mate(Set<PlayerId> except) {
    final pool = [
      for (var i = 0; i < att.onPitch.length; i++)
        if (att.onPitch[i] case final id?)
          if (att.tactic.slots[i] != Position.gk && !except.contains(id)) id,
    ];
    return pool.isEmpty ? null : rng.pick(pool);
  }

  /// An outfield defender of the lane facing the step's lane; any outfield
  /// defender when it is empty, anyone on the pitch as a last resort.
  PlayerId _defender() {
    final facing = switch (step.lane) {
      Lane.left => Lane.right,
      Lane.centre => Lane.centre,
      Lane.right => Lane.left,
    };
    final outfield = <PlayerId>[];
    final inLane = <PlayerId>[];
    for (var i = 0; i < def.onPitch.length; i++) {
      final id = def.onPitch[i];
      final pos = def.tactic.slots[i];
      if (id == null || pos == Position.gk) continue;
      outfield.add(id);
      if (laneOf(pos) == facing) inLane.add(id);
    }
    return rng.pick(
      inLane.isNotEmpty
          ? inLane
          : outfield.isNotEmpty
          ? outfield
          : def.playing,
    );
  }

  PlayerId? _keeper() {
    final i = def.tactic.slots.indexOf(Position.gk);
    return i == -1 ? null : def.onPitch[i];
  }

  static Pt _pt(double x, double y) =>
      Pt(x.clamp(0.0, 100.0), y.clamp(0.0, 100.0));
}
