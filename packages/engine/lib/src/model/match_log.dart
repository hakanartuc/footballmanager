/// The detailed, per-possession log of a match, produced only in detailed
/// mode for live viewing. It is NOT persisted: these types have no JSON
/// codec, and a saved [MatchResult] keeps only its [MatchEvent]s.
library;

import '../core/ids.dart';
import 'match_result.dart';
import 'tactic.dart';

/// A pitch point, 0..100 on both axes; the attacking side plays upward.
class Pt {
  final double x;
  final double y;

  const Pt(this.x, this.y);
}

/// A step of ball movement inside a possession; [t] is the time offset
/// within the possession.
sealed class MicroEvent {
  final double t;

  const MicroEvent(this.t);
}

final class Pass extends MicroEvent {
  final PlayerId from;
  final PlayerId to;
  final Pt a;
  final Pt b;

  const Pass(super.t, this.from, this.to, this.a, this.b);
}

final class Dribble extends MicroEvent {
  final PlayerId who;
  final Pt a;
  final Pt b;

  const Dribble(super.t, this.who, this.a, this.b);
}

final class Cross extends MicroEvent {
  final PlayerId from;
  final PlayerId to;
  final Pt a;
  final Pt b;

  const Cross(super.t, this.from, this.to, this.a, this.b);
}

final class Shot extends MicroEvent {
  final PlayerId who;
  final Pt a;
  final Pt target;
  final ShotOutcome outcome;
  final PlayerId? keeperId;

  const Shot(
    super.t,
    this.who,
    this.a,
    this.target,
    this.outcome,
    this.keeperId,
  );
}

final class Tackle extends MicroEvent {
  final PlayerId who;
  final PlayerId victim;
  final Pt at;

  const Tackle(super.t, this.who, this.victim, this.at);
}

final class Foul extends MicroEvent {
  final PlayerId who;
  final PlayerId victim;
  final Pt at;

  const Foul(super.t, this.who, this.victim, this.at);
}

final class Save extends MicroEvent {
  final PlayerId keeper;
  final Pt at;

  const Save(super.t, this.keeper, this.at);
}

final class Clearance extends MicroEvent {
  final PlayerId who;
  final Pt a;
  final Pt b;

  const Clearance(super.t, this.who, this.a, this.b);
}

/// One possession by [attackingId]; [seconds] is how long it lasted.
class PossessionStep {
  int minute;
  int half;
  ClubId attackingId;
  Lane lane;
  bool counter;
  double seconds;
  ChanceType? chance;
  double? xg;
  ShotOutcome? outcome;
  PlayerId? shooter;
  PlayerId? assister;
  List<MicroEvent> micro;
  List<MatchEvent> events;

  PossessionStep({
    required this.minute,
    required this.half,
    required this.attackingId,
    required this.lane,
    required this.counter,
    this.seconds = 0,
    this.chance,
    this.xg,
    this.outcome,
    this.shooter,
    this.assister,
    List<MicroEvent>? micro,
    List<MatchEvent>? events,
  }) : micro = micro ?? [],
       events = events ?? [];
}

class MatchLog {
  List<PossessionStep> steps;

  MatchLog({List<PossessionStep>? steps}) : steps = steps ?? [];
}
