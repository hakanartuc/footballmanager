import '../../model/enums.dart';
import '../../model/match_result.dart';
import '../../model/tactic.dart';

/// Every calibration number of the match engine (spec 5.2, 5.3, 16.1,
/// 16.8). Task 12 (calibration) edits only this file.
abstract final class EngineTuning {
  // --- Possession and chances (spec 5.3 steps 1–3) ---

  /// Possession logistic slope on `mid_a − mid_b` (5.3 step 1).
  static const double possessionK1 = 0.25;

  /// Chance logistic slope on `att_lane − def_lane` (5.3 step 3).
  static const double chanceK2 = 0.20;

  /// Chance logistic intercept: `ln(0.2 / 0.8)`, so equal lanes give a
  /// chance on 20 % of possessions (5.3 step 3).
  static const double chanceBase = -1.3862943611198906;

  /// Chance a lost possession is followed by a counter (5.3 step 1).
  static const double counterProb = 0.15;

  /// [counterProb] with the counter-attack setting on (16.1).
  static const double counterProbTactic = 0.28;

  /// Defending lane multiplier on a counter (5.3 step 1).
  static const double counterDefMul = 0.80;

  /// Attacking lane multiplier on a counter with the setting on (16.1).
  static const double counterAttMul = 1.15;

  // --- Chance quality and outcome (spec 5.3 steps 6–7) ---

  /// Base xG per chance type (5.3 step 6).
  static const Map<ChanceType, double> xgBase = {
    ChanceType.penalty: 0.76,
    ChanceType.throughBall: 0.30,
    ChanceType.cross: 0.12,
    ChanceType.longShot: 0.05,
    ChanceType.dribble: 0.20,
    ChanceType.corner: 0.08,
    ChanceType.freeKick: 0.07,
  };

  /// xG × `(1 + finishingCoef × (finishing + composure − 20))` (5.3 step 6).
  static const double finishingCoef = 0.02;

  /// xG × `(1 − keeperCoef × (gk − 10))` (5.3 step 6).
  static const double keeperCoef = 0.015;

  /// Width of the "saved" band above xG (5.3 step 7).
  static const double saveBand = 0.25;

  /// Width of the "blocked / post" band above the save band (5.3 step 7).
  static const double blockBand = 0.20;

  /// Share of saves that give a corner (5.3 step 7).
  static const double cornerAfterSave = 0.30;

  /// Share of the blocked band (its top) that is the post instead.
  static const double postShare = 0.15;

  /// xG ceiling after the finishing and keeper factors.
  static const double xgMax = 0.95;

  /// Attribute that weights shooter selection per chance type (5.3 step 5).
  static const Map<ChanceType, Attr> shooterAttr = {
    ChanceType.throughBall: Attr.finishing,
    ChanceType.cross: Attr.heading,
    ChanceType.longShot: Attr.longShots,
    ChanceType.dribble: Attr.dribbling,
    ChanceType.corner: Attr.heading,
    ChanceType.freeKick: Attr.longShots,
    ChanceType.penalty: Attr.finishing,
  };

  /// Shooter weight multiplier for forwards (st, aml, amc, amr) per chance
  /// type; absent means 1.0.
  static const Map<ChanceType, double> shooterForwardMul = {
    ChanceType.throughBall: 3.0,
    ChanceType.cross: 2.0,
    ChanceType.dribble: 2.0,
  };

  /// Attribute that weights assister selection per chance type; a type
  /// absent here has no assister (5.3 step 5).
  static const Map<ChanceType, Attr> assistAttr = {
    ChanceType.throughBall: Attr.passing,
    ChanceType.longShot: Attr.passing,
    ChanceType.cross: Attr.crossing,
    ChanceType.corner: Attr.crossing,
  };

  // --- Side effects (spec 5.3 step 8) ---

  /// Foul probability per possession step.
  static const double foulPerStep = 0.10;

  /// Yellow card probability per foul.
  static const double yellowPerFoul = 0.12;

  /// Straight red probability per foul.
  static const double redPerFoul = 0.008;

  /// Share of fouls inside the box; the attacking side's next possession is
  /// a penalty. With ~12 fouls per match this gives the spec's ~0.25
  /// penalties per match (5.3 step 4).
  static const double boxFoulShare = 0.02;

  /// Share of the other fouls that give the attacking side a free-kick
  /// chance as its next possession.
  static const double freeKickShare = 0.25;

  /// Straight red reasons: this share is violent conduct, the next
  /// [redLastManShare] a last-man foul, the rest a normal foul.
  static const double redViolentShare = 0.10;
  static const double redLastManShare = 0.20;

  /// Injury probability per step (spec 6.1: 0.0025 per step per
  /// player-exposure → ~0.3 per match). One exposure per step, independent
  /// of how many players are on the pitch: the probability is this × the
  /// mean of the per-player multipliers below, and the victim is drawn
  /// weighted by them.
  static const double injuryPerStep = 0.0025;

  /// Injury proneness 1 → ×[injuryPronenessMin], 20 → ×[injuryPronenessMax].
  static const double injuryPronenessMin = 0.5;
  static const double injuryPronenessMax = 2.0;

  /// Condition below [injuryLowCondition] ×[injuryLowConditionMul]; below
  /// [injuryVeryLowCondition] ×[injuryVeryLowConditionMul] instead.
  static const double injuryLowCondition = 70;
  static const double injuryLowConditionMul = 1.5;
  static const double injuryVeryLowCondition = 50;
  static const double injuryVeryLowConditionMul = 2.5;

  /// Age above [injuryOldAge] ×[injuryOldAgeMul].
  static const int injuryOldAge = 31;
  static const double injuryOldAgeMul = 1.3;

  /// Own side on fast tempo ×[injuryFastTempoMul].
  static const double injuryFastTempoMul = 1.2;

  /// The player fouled this step ×[injuryFoulVictimMul].
  static const double injuryFoulVictimMul = 4.0;

  /// Injury severity bands (spec 6.2): inclusive day ranges and their
  /// weights, normally and when caused by a foul (shifted toward serious).
  static const List<(int, int)> injuryBandDays = [
    (1, 7),
    (8, 21),
    (22, 56),
    (57, 150),
    (151, 360),
  ];
  static const List<double> injuryBandWeights = [45, 30, 15, 8, 2];
  static const List<double> injuryBandWeightsFoul = [35, 32, 18, 12, 3];

  /// Condition lost per minute at stamina 20 and at stamina 5 (5.3 step 8);
  /// linear between and beyond.
  static const double drainAtStamina20 = 0.18;
  static const double drainAtStamina5 = 0.35;

  /// Condition lost per minute by a player with [stamina], before the
  /// side's `conditionDrain`.
  static double drainPerMinute(int stamina) =>
      drainAtStamina5 +
      (drainAtStamina20 - drainAtStamina5) * (stamina - 5) / 15;

  /// Mid and def multiplier per missing player below eleven.
  static const double tenMenMul = 0.85;

  /// Extra att multiplier with nine or fewer players (Task 4 resolution).
  static const double nineMenAttMul = 0.9;

  // --- Clock and venue (spec 5.3, 5.2) ---

  /// Shortest possession step in seconds at normal tempo.
  static const int stepSecondsMin = 30;

  /// Longest possession step in seconds at normal tempo.
  static const int stepSecondsMax = 90;

  /// Home advantage when match conditions carry none (5.2).
  static const double homeAdvantageDefault = 1.06;

  // --- Player effectiveness (spec 5.2) ---

  /// Familiarity factor at familiarity 1; linear to 1.0 at 20.
  static const double familiarityMin = 0.6;

  /// Condition factor: `conditionBase + conditionSpan × condition / 100`
  /// (5.2: 100 → 1.0, 50 → 0.75). Only the match engine uses this curve;
  /// `lineup.dart` keeps its own for auto-lineup ordering.
  static const double conditionBase = 0.5;
  static const double conditionSpan = 0.5;

  /// The 5.2 condition curve for [condition] in 0..100.
  static double conditionFactor(double condition) =>
      conditionBase + conditionSpan * condition / 100;

  /// Sharpness factor: `sharpnessBase + sharpnessSpan × sharpness / 100`.
  static const double sharpnessBase = 0.9;
  static const double sharpnessSpan = 0.1;

  /// Morale factor: `moraleBase + moraleSpan × morale / 100`.
  static const double moraleBase = 0.95;
  static const double moraleSpan = 0.10;

  /// Form factor: `formBase + formSpan × clamp((form − 1) / 9, 0, 1)`.
  static const double formBase = 0.95;
  static const double formSpan = 0.10;

  // --- Profile aggregation (spec 5.2, Task 4 resolution) ---

  /// Mid bonus per midfielder above [midCountBase].
  static const double midCountBonus = 0.3;
  static const double midCountBase = 4.0;

  /// Weight of aml/amc/amr in the mid mean and midfielder count.
  static const double attackingMidWeight = 0.5;

  /// Weight of a striker in the left and right attack lanes.
  static const double strikerWingWeight = 0.5;

  /// Weight of a dm in the centre defence lane.
  static const double dmDefWeight = 0.7;

  /// Weight of ml/mr in their defence lane.
  static const double wideMidDefWeight = 0.3;

  /// An empty lane is this × the mean of the occupied lanes.
  static const double emptyLaneMul = 0.8;

  /// Value of a group nobody on the pitch belongs to (gk, mid, all lanes).
  static const double missingGroupValue = 5.0;

  /// Players whose mean counts for set-piece attack.
  static const int setPieceTopN = 5;

  // --- Tactic multipliers (spec 16.1 table) ---

  /// Mentality: att multiplier; def is [mentalityDefMul].
  static const Map<Mentality, double> mentalityAttMul = {
    Mentality.veryDefensive: 0.85,
    Mentality.defensive: 0.92,
    Mentality.balanced: 1.0,
    Mentality.attacking: 1.08,
    Mentality.veryAttacking: 1.15,
  };
  static const Map<Mentality, double> mentalityDefMul = {
    Mentality.veryDefensive: 1.15,
    Mentality.defensive: 1.08,
    Mentality.balanced: 1.0,
    Mentality.attacking: 0.92,
    Mentality.veryAttacking: 0.85,
  };

  /// Short passing: mid multiplier.
  static const double shortPassMidMul = 1.1;

  /// Share of possessions that skip the midfield contest, per style.
  static const Map<PassingStyle, double> midBypass = {
    PassingStyle.short: 0.0,
    PassingStyle.mixed: 0.1,
    PassingStyle.direct: 0.2,
    PassingStyle.longBall: 0.3,
  };

  /// Long ball: chance-type weight shifts.
  static const double longBallCrossMul = 1.5;
  static const double longBallThroughMul = 0.7;

  /// Tempo: condition drain and `1 / tempoMul` on step seconds.
  static const Map<Tempo, double> tempoMul = {
    Tempo.slow: 0.85,
    Tempo.normal: 1.0,
    Tempo.fast: 1.3,
  };

  /// Width: lane weights left / centre / right.
  static const Map<Width, Map<Lane, double>> widthLaneWeights = {
    Width.narrow: {Lane.left: 0.25, Lane.centre: 0.5, Lane.right: 0.25},
    Width.normal: {Lane.left: 0.3, Lane.centre: 0.4, Lane.right: 0.3},
    Width.wide: {Lane.left: 0.4, Lane.centre: 0.2, Lane.right: 0.4},
  };

  /// High pressing: opponent mid multiplier (applied by the caller).
  static const double pressHighOpponentMidMul = 0.92;

  /// Pressing: own condition drain multiplier.
  static const Map<Pressing, double> pressDrainMul = {
    Pressing.low: 0.9,
    Pressing.normal: 1.0,
    Pressing.high: 1.25,
  };

  /// Tackling: foul, card, injury-to-opponent and ball-winning (def).
  static const Map<Tackling, double> tacklingFoulMul = {
    Tackling.soft: 0.8,
    Tackling.normal: 1.0,
    Tackling.hard: 1.3,
  };
  static const Map<Tackling, double> tacklingCardMul = {
    Tackling.soft: 0.8,
    Tackling.normal: 1.0,
    Tackling.hard: 1.4,
  };
  static const Map<Tackling, double> tacklingInjuryMul = {
    Tackling.soft: 0.9,
    Tackling.normal: 1.0,
    Tackling.hard: 1.4,
  };
  static const Map<Tackling, double> tacklingDefMul = {
    Tackling.soft: 0.95,
    Tackling.normal: 1.0,
    Tackling.hard: 1.1,
  };

  /// Man marking: own att multiplier per marked opponent (at most two).
  static const double manMarkerAttMul = 0.8;

  /// Man marking: effectiveness of the marked playmaker / target man.
  static const double manMarkedEffMul = 0.85;

  /// Offside trap: opponent through-ball xG multiplier.
  static const double offsideTrapThroughMul = 0.75;

  /// Offside trap: share of trapped through balls that beat the trap, and
  /// their xG multiplier (applied per chance in Task 5).
  static const double offsideTrapFailProb = 0.12;
  static const double offsideTrapFailMul = 1.6;

  /// Arrows: forward att / def multipliers; back swaps them.
  static const double arrowAttMul = 1.25;
  static const double arrowDefMul = 0.85;

  /// Playmaker / target man selection weight.
  static const double playmakerBoost = 2.0;

  /// Selection weight per matching instruction (long shots, through balls,
  /// forward runs), multiplicative.
  static const double instructionBoost = 1.5;

  // --- Chance-type weights (spec 5.3 step 4) ---

  /// Open-play chance-type weights per attacking lane; the profile's
  /// `chanceWeights` multiplies these.
  static const Map<Lane, Map<ChanceType, double>> laneChanceWeights = {
    Lane.left: {
      ChanceType.cross: 1.5,
      ChanceType.dribble: 1.2,
      ChanceType.throughBall: 0.7,
      ChanceType.longShot: 0.6,
    },
    Lane.centre: {
      ChanceType.cross: 0.5,
      ChanceType.dribble: 0.9,
      ChanceType.throughBall: 1.4,
      ChanceType.longShot: 1.3,
    },
    Lane.right: {
      ChanceType.cross: 1.5,
      ChanceType.dribble: 1.2,
      ChanceType.throughBall: 0.7,
      ChanceType.longShot: 0.6,
    },
  };

  // --- Weather and pitch (spec 16.8) ---

  /// Pitch quality at or below this plays like rain.
  static const int wetPitchMax = 4;

  /// Wet: mid multiplier with short / mixed passing.
  static const double wetShortPassMul = 0.92;

  /// Wet: mid multiplier with direct / long-ball passing.
  static const double wetLongBallMul = 1.05;

  /// Wet: keeper error multiplier (Task 5 shrinks the save band).
  static const double wetKeeperErrorMul = 1.3;

  /// Wet: injury multiplier.
  static const double wetInjuryMul = 1.15;

  /// Hot: condition drain multiplier.
  static const double hotDrainMul = 1.15;
}
