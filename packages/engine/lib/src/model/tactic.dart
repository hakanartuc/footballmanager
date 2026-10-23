import '../core/ids.dart';
import 'enums.dart';

enum Mentality { veryDefensive, defensive, balanced, attacking, veryAttacking }

enum PassingStyle { short, mixed, direct, longBall }

enum Tempo { slow, normal, fast }

enum Width { narrow, normal, wide }

enum Pressing { low, normal, high }

enum Tackling { soft, normal, hard }

enum Marking { zonal, man }

enum Arrow { none, forward, back }

enum CrossTarget { near, far, mixed }

enum Lane { left, centre, right }

/// The lane of [p]: `dl`, `ml`, `aml` left; `dr`, `mr`, `amr` right; the
/// rest centre.
Lane laneOf(Position p) => switch (p) {
  Position.dl || Position.ml || Position.aml => Lane.left,
  Position.dr || Position.mr || Position.amr => Lane.right,
  _ => Lane.centre,
};

class PlayerInstructions {
  bool forwardRuns;
  bool runWithBall;
  bool longShots;
  bool throughBalls;
  bool holdUpBall;
  bool freeRole;
  CrossTarget crossFrom;

  PlayerInstructions({
    this.forwardRuns = false,
    this.runWithBall = false,
    this.longShots = false,
    this.throughBalls = false,
    this.holdUpBall = false,
    this.freeRole = false,
    this.crossFrom = CrossTarget.mixed,
  });
}

/// Null means the engine picks a taker.
class SetPieceTakers {
  PlayerId? cornerLeft;
  PlayerId? cornerRight;
  PlayerId? freeKickLeft;
  PlayerId? freeKickRight;
  PlayerId? penalty;
  PlayerId? longThrow;

  SetPieceTakers({
    this.cornerLeft,
    this.cornerRight,
    this.freeKickLeft,
    this.freeKickRight,
    this.penalty,
    this.longThrow,
  });
}

/// One of a club's three tactic slots.
class Tactic {
  String name;
  Formation formation;

  /// 11 positions, index 0 the goalkeeper. Presets copy
  /// [formationSlots]; [Formation.custom] carries its own list.
  List<Position> slots;
  Mentality mentality;
  PassingStyle passing;
  Tempo tempo;
  Width width;
  Pressing pressing;
  Tackling tackling;
  Marking marking;
  bool offsideTrap;
  bool counterAttack;
  PlayerId? playmaker;
  PlayerId? targetMan;
  PlayerId? captain;
  PlayerId? viceCaptain;
  SetPieceTakers setPieces;
  Map<PlayerId, PlayerInstructions> instructions;
  Map<PlayerId, Arrow> arrows;

  Tactic({
    required this.name,
    required this.formation,
    required this.slots,
    this.mentality = Mentality.balanced,
    this.passing = PassingStyle.mixed,
    this.tempo = Tempo.normal,
    this.width = Width.normal,
    this.pressing = Pressing.normal,
    this.tackling = Tackling.normal,
    this.marking = Marking.zonal,
    this.offsideTrap = false,
    this.counterAttack = false,
    this.playmaker,
    this.targetMan,
    this.captain,
    this.viceCaptain,
    SetPieceTakers? setPieces,
    Map<PlayerId, PlayerInstructions>? instructions,
    Map<PlayerId, Arrow>? arrows,
  }) : setPieces = setPieces ?? SetPieceTakers(),
       instructions = instructions ?? {},
       arrows = arrows ?? {};

  /// A balanced tactic on [f]'s slots, named [name] (default `f.name`).
  /// Throws [ArgumentError] for [Formation.custom].
  static Tactic preset(Formation f, {String? name}) => Tactic(
    name: name ?? f.name,
    formation: f,
    slots: List.of(formationSlots(f)),
  );

  /// A [Formation.custom] tactic on [slots]: 11 positions, the first `gk`.
  Tactic.custom(
    List<Position> slots, {
    String name = 'custom',
    Mentality mentality = Mentality.balanced,
    PassingStyle passing = PassingStyle.mixed,
    Tempo tempo = Tempo.normal,
    Width width = Width.normal,
    Pressing pressing = Pressing.normal,
    Tackling tackling = Tackling.normal,
    Marking marking = Marking.zonal,
    bool offsideTrap = false,
    bool counterAttack = false,
    PlayerId? playmaker,
    PlayerId? targetMan,
    PlayerId? captain,
    PlayerId? viceCaptain,
    SetPieceTakers? setPieces,
    Map<PlayerId, PlayerInstructions>? instructions,
    Map<PlayerId, Arrow>? arrows,
  }) : this(
         name: name,
         formation: Formation.custom,
         slots: _validSlots(slots),
         mentality: mentality,
         passing: passing,
         tempo: tempo,
         width: width,
         pressing: pressing,
         tackling: tackling,
         marking: marking,
         offsideTrap: offsideTrap,
         counterAttack: counterAttack,
         playmaker: playmaker,
         targetMan: targetMan,
         captain: captain,
         viceCaptain: viceCaptain,
         setPieces: setPieces,
         instructions: instructions,
         arrows: arrows,
       );

  static List<Position> _validSlots(List<Position> slots) {
    if (slots.length != 11 || slots[0] != Position.gk) {
      throw ArgumentError.value(
        slots,
        'slots',
        'must be 11 positions with the goalkeeper first',
      );
    }
    return List.of(slots);
  }
}

/// A club's three default tactic slots: [first], 4-3-3 and 5-3-2, named
/// `'1'`, `'2'`, `'3'`.
List<Tactic> defaultTactics(Formation first) => [
  Tactic.preset(first, name: '1'),
  Tactic.preset(Formation.f433, name: '2'),
  Tactic.preset(Formation.f532, name: '3'),
];
