import 'dart:math' as math;

import '../../core/ids.dart';
import '../../model/attributes.dart';
import '../../model/enums.dart';
import '../../model/match_conditions.dart';
import '../../model/match_result.dart';
import '../../model/player.dart';
import '../../model/tactic.dart';
import '../../model/world.dart';
import 'tuning.dart';

/// The factor every attribute of [p] is scaled by when playing [slot] at
/// [condition] (spec 5.2): familiarity, condition, sharpness, morale, form.
double _playerFactor(Player p, Position slot, double condition) {
  final fam = p.familiarity[slot] ?? 1;
  final s = p.state;
  return (EngineTuning.familiarityMin +
          (1 - EngineTuning.familiarityMin) * (fam - 1) / 19) *
      EngineTuning.conditionFactor(condition) *
      (EngineTuning.sharpnessBase +
          EngineTuning.sharpnessSpan * s.sharpness / 100) *
      (EngineTuning.moraleBase + EngineTuning.moraleSpan * s.morale / 100) *
      (EngineTuning.formBase +
          EngineTuning.formSpan * ((s.form - 1) / 9).clamp(0.0, 1.0));
}

/// [p]'s attribute [a] scaled for playing [slot] (spec 5.2). [condition]
/// defaults to the player's state.
double playerEffectiveness(
  Player p,
  Attr a,
  Position slot, {
  double? condition,
}) => p.attrs[a] * _playerFactor(p, slot, condition ?? p.state.condition);

/// A side's compiled strengths and tactic knobs (spec 5.2, 16.1). The match
/// loop reads only this; it is rebuilt by the session after a substitution,
/// card or tactic change.
class TeamProfile {
  final double mid;
  final double attL;
  final double attC;
  final double attR;
  final double defL;
  final double defC;
  final double defR;
  final double gk;
  final double setPieceAtt;
  final double setPieceDef;

  /// Tempo factor: condition drain and `1 / tempoMul` on step seconds.
  final double tempoMul;

  /// Multiply the opponent's mid by this (high pressing).
  final double pressMul;

  /// Condition drain: tempo × pressing × weather.
  final double conditionDrain;
  final double foulMul;
  final double cardMul;

  /// Injury multiplier on the opponent's players (tackling).
  final double injuryToOpponentMul;

  /// Injury multiplier on own players (weather and pitch).
  final double injuryMul;

  /// Keeper error multiplier (weather and pitch); Task 5 shrinks the save
  /// band by it.
  final double keeperErrorMul;

  /// Multiply the opponent's through-ball xG by this (offside trap).
  final double throughBallXgMul;

  /// Chance this side counters after the opponent loses the ball.
  final double counterProb;

  /// Attack multiplier on this side's counters.
  final double counterAttMul;

  /// Share of possessions that skip the midfield contest.
  final double midBypass;
  final Map<Lane, double> laneWeights;

  /// Multiplies `EngineTuning.laneChanceWeights`; 1.0 for every type unless
  /// the passing style shifts it.
  final Map<ChanceType, double> chanceWeights;

  /// Shooter / passer selection weight per player; absent means 1.0.
  final Map<PlayerId, double> selectionBoost;

  /// Opponents this side man-marks.
  final Set<PlayerId> markedOpponents;
  final List<PlayerId> onPitch;

  /// First occupant per position; [slotOf] is the full inverse.
  final Map<Position, PlayerId> bySlot;
  final Map<PlayerId, Position> slotOf;

  TeamProfile({
    required this.mid,
    required this.attL,
    required this.attC,
    required this.attR,
    required this.defL,
    required this.defC,
    required this.defR,
    required this.gk,
    required this.setPieceAtt,
    required this.setPieceDef,
    required this.tempoMul,
    required this.pressMul,
    required this.conditionDrain,
    required this.foulMul,
    required this.cardMul,
    required this.injuryToOpponentMul,
    required this.injuryMul,
    required this.keeperErrorMul,
    required this.throughBallXgMul,
    required this.counterProb,
    required this.counterAttMul,
    required this.midBypass,
    required this.laneWeights,
    required this.chanceWeights,
    required this.selectionBoost,
    required this.markedOpponents,
    required this.onPitch,
    required this.bySlot,
    required this.slotOf,
  });

  double att(Lane l) => switch (l) {
    Lane.left => attL,
    Lane.centre => attC,
    Lane.right => attR,
  };

  double def(Lane l) => switch (l) {
    Lane.left => defL,
    Lane.centre => defC,
    Lane.right => defR,
  };
}

const _midAttrs = [
  Attr.passing,
  Attr.teamwork,
  Attr.workRate,
  Attr.decisions,
  Attr.stamina,
];
const _defAttrs = [
  Attr.tackling,
  Attr.positioning,
  Attr.heading,
  Attr.strength,
  Attr.concentration,
  Attr.pace,
];
const _gkAttrs = [
  Attr.reflexes,
  Attr.oneOnOnes,
  Attr.handling,
  Attr.positioning,
];
const _setPieceAttAttrs = [
  Attr.heading,
  Attr.jumping,
  Attr.longPassing,
  Attr.crossing,
];
const _setPieceDefAttrs = [Attr.heading, Attr.jumping, Attr.positioning];

double _mean(Attributes a, List<Attr> attrs) {
  var sum = 0;
  for (final x in attrs) {
    sum += a[x];
  }
  return sum / attrs.length;
}

/// Attack lane attributes: crossing on the wings, passing in the centre.
double _attMean(Attributes a, Lane lane) =>
    (a[Attr.pace] +
        a[Attr.dribbling] +
        a[lane == Lane.centre ? Attr.passing : Attr.crossing] +
        a[Attr.finishing] +
        a[Attr.anticipation]) /
    5;

/// Weighted-sum accumulator per lane.
class _Lanes {
  final sum = [0.0, 0.0, 0.0];
  final weight = [0.0, 0.0, 0.0];

  void add(Lane l, double value, double w) {
    sum[l.index] += value * w;
    weight[l.index] += w;
  }

  /// Means per lane; an empty lane is `emptyLaneMul` × the mean of the
  /// occupied lanes, or `missingGroupValue` when all are empty.
  List<double> resolve() {
    var occupiedSum = 0.0;
    var occupied = 0;
    final out = List.filled(3, EngineTuning.missingGroupValue);
    for (var i = 0; i < 3; i++) {
      if (weight[i] > 0) {
        out[i] = sum[i] / weight[i];
        occupiedSum += out[i];
        occupied++;
      }
    }
    if (occupied == 0) return out;
    final fallback = occupiedSum / occupied * EngineTuning.emptyLaneMul;
    for (var i = 0; i < 3; i++) {
      if (weight[i] == 0) out[i] = fallback;
    }
    return out;
  }
}

/// Compiles [tactic] and the players [onPitch] into a [TeamProfile].
///
/// `onPitch[i]` occupies `tactic.slots[i]`; a null entry and slots past the
/// end of [onPitch] are empty. A player missing from [condition] uses its
/// state condition. Ids in the tactic that are not on the pitch are ignored.
/// [opponentTactic] supplies the opponent's marking and marked players.
TeamProfile buildProfile({
  required World w,
  required Tactic tactic,
  required List<PlayerId?> onPitch,
  required Map<PlayerId, double> condition,
  required bool home,
  required MatchConditions cond,
  Tactic? opponentTactic,
}) {
  final slotCount = math.min(onPitch.length, tactic.slots.length);
  final playing = <PlayerId>[
    for (var i = 0; i < slotCount; i++)
      if (onPitch[i] != null) onPitch[i]!,
  ];
  final n = playing.length;
  final opponentMarksMan = opponentTactic?.marking == Marking.man;

  var midSum = 0.0;
  var midWeight = 0.0;
  final att = _Lanes();
  final def = _Lanes();
  double? gk;
  final setPieceAtt = <double>[];
  var setPieceDefSum = 0.0;
  final bySlot = <Position, PlayerId>{};
  final slotOf = <PlayerId, Position>{};

  for (var i = 0; i < slotCount; i++) {
    final id = onPitch[i];
    if (id == null) continue;
    final slot = tactic.slots[i];
    final p = w.players[id]!;
    bySlot.putIfAbsent(slot, () => id);
    slotOf[id] = slot;

    var f = _playerFactor(p, slot, condition[id] ?? p.state.condition);
    if (opponentMarksMan &&
        (id == tactic.playmaker || id == tactic.targetMan)) {
      f *= EngineTuning.manMarkedEffMul;
    }
    final (arrowAtt, arrowDef) = switch (tactic.arrows[id] ?? Arrow.none) {
      Arrow.forward => (EngineTuning.arrowAttMul, EngineTuning.arrowDefMul),
      Arrow.back => (EngineTuning.arrowDefMul, EngineTuning.arrowAttMul),
      Arrow.none => (1.0, 1.0),
    };
    final a = p.attrs;

    final midW = switch (slot) {
      Position.dm || Position.ml || Position.mc || Position.mr => 1.0,
      Position.aml ||
      Position.amc ||
      Position.amr => EngineTuning.attackingMidWeight,
      _ => 0.0,
    };
    if (midW > 0) {
      midSum += _mean(a, _midAttrs) * f * midW;
      midWeight += midW;
    }

    final fa = f * arrowAtt;
    switch (slot) {
      case Position.st:
        att.add(Lane.centre, _attMean(a, Lane.centre) * fa, 1.0);
        att.add(
          Lane.left,
          _attMean(a, Lane.left) * fa,
          EngineTuning.strikerWingWeight,
        );
        att.add(
          Lane.right,
          _attMean(a, Lane.right) * fa,
          EngineTuning.strikerWingWeight,
        );
      case Position.aml || Position.ml:
        att.add(Lane.left, _attMean(a, Lane.left) * fa, 1.0);
      case Position.amr || Position.mr:
        att.add(Lane.right, _attMean(a, Lane.right) * fa, 1.0);
      case Position.amc || Position.mc:
        att.add(Lane.centre, _attMean(a, Lane.centre) * fa, 1.0);
      default:
        break;
    }

    final defW = switch (slot) {
      Position.dc || Position.dl || Position.dr => 1.0,
      Position.dm => EngineTuning.dmDefWeight,
      Position.ml || Position.mr => EngineTuning.wideMidDefWeight,
      _ => 0.0,
    };
    if (defW > 0) {
      def.add(laneOf(slot), _mean(a, _defAttrs) * f * arrowDef, defW);
    }

    if (slot == Position.gk) gk ??= _mean(a, _gkAttrs) * f;
    setPieceAtt.add(_mean(a, _setPieceAttAttrs) * f);
    setPieceDefSum += _mean(a, _setPieceDefAttrs) * f;
  }

  final attLanes = att.resolve();
  final defLanes = def.resolve();
  final midRaw = midWeight > 0
      ? midSum / midWeight
      : EngineTuning.missingGroupValue;
  setPieceAtt.sort((x, y) => y.compareTo(x));
  final topN = math.min(EngineTuning.setPieceTopN, setPieceAtt.length);
  var spAtt = EngineTuning.missingGroupValue;
  if (topN > 0) {
    var s = 0.0;
    for (var i = 0; i < topN; i++) {
      s += setPieceAtt[i];
    }
    spAtt = s / topN;
  }
  final spDef = n > 0 ? setPieceDefSum / n : EngineTuning.missingGroupValue;

  // Man marking: opponents this side marks.
  final marked = <PlayerId>{};
  if (tactic.marking == Marking.man && opponentTactic != null) {
    for (final id in [opponentTactic.playmaker, opponentTactic.targetMan]) {
      if (id != null && w.players.containsKey(id)) marked.add(id);
    }
  }

  final wet =
      cond.weather == Weather.rainy ||
      cond.weather == Weather.heavyRain ||
      cond.pitch <= EngineTuning.wetPitchMax;
  final longBall =
      tactic.passing == PassingStyle.direct ||
      tactic.passing == PassingStyle.longBall;
  final shortHanded = math.pow(EngineTuning.tenMenMul, 11 - n).toDouble();
  final homeMul = home ? cond.homeAdvantage : 1.0;

  final attMul =
      EngineTuning.mentalityAttMul[tactic.mentality]! *
      homeMul *
      math.pow(EngineTuning.manMarkerAttMul, marked.length) *
      (n <= 9 ? EngineTuning.nineMenAttMul : 1.0);
  final defMul =
      EngineTuning.mentalityDefMul[tactic.mentality]! *
      EngineTuning.tacklingDefMul[tactic.tackling]! *
      shortHanded;
  final midMul =
      (tactic.passing == PassingStyle.short
          ? EngineTuning.shortPassMidMul
          : 1.0) *
      (wet
          ? (longBall
                ? EngineTuning.wetLongBallMul
                : EngineTuning.wetShortPassMul)
          : 1.0) *
      homeMul *
      shortHanded;

  final chanceWeights = {for (final t in ChanceType.values) t: 1.0};
  if (tactic.passing == PassingStyle.longBall) {
    chanceWeights[ChanceType.cross] = EngineTuning.longBallCrossMul;
    chanceWeights[ChanceType.throughBall] = EngineTuning.longBallThroughMul;
  }

  final boost = <PlayerId, double>{};
  for (final id in playing) {
    var b = 1.0;
    if (id == tactic.playmaker) b *= EngineTuning.playmakerBoost;
    if (id == tactic.targetMan) b *= EngineTuning.playmakerBoost;
    final ins = tactic.instructions[id];
    if (ins != null) {
      if (ins.longShots) b *= EngineTuning.instructionBoost;
      if (ins.throughBalls) b *= EngineTuning.instructionBoost;
      if (ins.forwardRuns) b *= EngineTuning.instructionBoost;
    }
    if (b != 1.0) boost[id] = b;
  }

  final tempoMul = EngineTuning.tempoMul[tactic.tempo]!;
  return TeamProfile(
    mid:
        (midRaw +
            EngineTuning.midCountBonus *
                (midWeight - EngineTuning.midCountBase)) *
        midMul,
    attL: attLanes[0] * attMul,
    attC: attLanes[1] * attMul,
    attR: attLanes[2] * attMul,
    defL: defLanes[0] * defMul,
    defC: defLanes[1] * defMul,
    defR: defLanes[2] * defMul,
    gk: gk ?? EngineTuning.missingGroupValue,
    setPieceAtt: spAtt,
    setPieceDef: spDef,
    tempoMul: tempoMul,
    pressMul: tactic.pressing == Pressing.high
        ? EngineTuning.pressHighOpponentMidMul
        : 1.0,
    conditionDrain:
        tempoMul *
        EngineTuning.pressDrainMul[tactic.pressing]! *
        (cond.weather == Weather.hot ? EngineTuning.hotDrainMul : 1.0),
    foulMul: EngineTuning.tacklingFoulMul[tactic.tackling]!,
    cardMul: EngineTuning.tacklingCardMul[tactic.tackling]!,
    injuryToOpponentMul: EngineTuning.tacklingInjuryMul[tactic.tackling]!,
    injuryMul: wet ? EngineTuning.wetInjuryMul : 1.0,
    keeperErrorMul: wet ? EngineTuning.wetKeeperErrorMul : 1.0,
    throughBallXgMul: tactic.offsideTrap
        ? EngineTuning.offsideTrapThroughMul
        : 1.0,
    counterProb: tactic.counterAttack
        ? EngineTuning.counterProbTactic
        : EngineTuning.counterProb,
    counterAttMul: tactic.counterAttack ? EngineTuning.counterAttMul : 1.0,
    midBypass: EngineTuning.midBypass[tactic.passing]!,
    laneWeights: EngineTuning.widthLaneWeights[tactic.width]!,
    chanceWeights: chanceWeights,
    selectionBoost: boost,
    markedOpponents: marked,
    onPitch: playing,
    bySlot: bySlot,
    slotOf: slotOf,
  );
}
