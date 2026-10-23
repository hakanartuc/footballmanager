import '../../core/ids.dart';
import '../../model/club.dart';
import '../../model/fixture.dart';
import '../../model/match_conditions.dart';
import '../../model/match_log.dart';
import '../../model/match_rules.dart';
import '../../model/tactic.dart';
import '../../model/world.dart';
import 'team_profile.dart';

/// A player's running match rating; Task 7 fills it.
class RatingAcc {
  double value = 6.0;
}

/// One side's mutable state during a match.
class SideState {
  final ClubId clubId;
  Tactic tactic;

  /// `onPitch[i]` plays `tactic.slots[i]`; null is an empty slot (sent off
  /// or injured without a substitute).
  final List<PlayerId?> onPitch;
  final List<PlayerId> bench;
  final Map<PlayerId, double> condition;
  final Map<PlayerId, int> yellows = {};
  final Set<PlayerId> sentOff = {};
  final Set<PlayerId> injuredOff = {};
  int subsUsed = 0;
  final TeamStats stats = TeamStats(
    shots: 0,
    onTarget: 0,
    blocked: 0,
    corners: 0,
    fouls: 0,
    yellows: 0,
    reds: 0,
    offsides: 0,
    possessionPct: 0,
    xg: 0,
  );
  int goals = 0;
  TeamProfile profile;
  bool userManaged = false;

  /// Seconds in possession; the session turns it into `possessionPct`.
  double possessionSeconds = 0;

  SideState({
    required this.clubId,
    required this.tactic,
    required this.onPitch,
    required this.bench,
    required this.condition,
    required this.profile,
  });

  /// The players on the pitch, in slot order.
  List<PlayerId> get playing => [for (final id in onPitch) ?id];

  /// Empties [id]'s slot.
  void removeFromPitch(PlayerId id) {
    final i = onPitch.indexOf(id);
    if (i != -1) onPitch[i] = null;
  }
}

/// The mutable state of a match in progress. Plain data plus small
/// helpers; the loop functions and the session mutate it.
class MatchState {
  final SideState home;
  final SideState away;
  int minute = 0;

  /// 1 or 2, 3 or 4 in extra time, 5 in the shootout.
  int half = 1;
  int addedTime = 0;
  double clockSeconds = 0;
  final List<MatchEvent> events = [];

  /// Kept only in detailed mode; the session appends each step.
  List<PossessionStep>? log;
  final Map<PlayerId, RatingAcc> ratings = {};
  ClubId? lastPossession;

  /// The side whose corner, free kick, counter or penalty the next
  /// possession is; resolved in the order penalty, corner, free kick,
  /// counter.
  ClubId? pendingCorner;
  ClubId? pendingFreeKick;
  ClubId? pendingCounter;
  ClubId? pendingPenalty;
  final MatchRules rules;
  final MatchConditions conditions;

  MatchState({
    required this.home,
    required this.away,
    required this.rules,
    required this.conditions,
  });

  /// Starts the match: conditions come from each player's state, and both
  /// profiles are built with the opponent's tactic (for marking).
  factory MatchState.start({
    required World w,
    required Fixture f,
    required Lineup homeLineup,
    required Lineup awayLineup,
    required Tactic homeTactic,
    required Tactic awayTactic,
    required MatchRules rules,
    required MatchConditions conditions,
  }) {
    SideState side(ClubId club, Lineup l, Tactic t, Tactic opp, bool home) {
      final condition = {
        for (final id in [...l.starters, ...l.bench])
          id: w.players[id]!.state.condition,
      };
      return SideState(
        clubId: club,
        tactic: t,
        onPitch: List<PlayerId?>.of(l.starters),
        bench: List.of(l.bench),
        condition: condition,
        profile: buildProfile(
          w: w,
          tactic: t,
          onPitch: l.starters,
          condition: condition,
          home: home,
          cond: conditions,
          opponentTactic: opp,
        ),
      );
    }

    final s = MatchState(
      home: side(f.homeId, homeLineup, homeTactic, awayTactic, true),
      away: side(f.awayId, awayLineup, awayTactic, homeTactic, false),
      rules: rules,
      conditions: conditions,
    );
    for (final id in [...homeLineup.starters, ...awayLineup.starters]) {
      s.ratings[id] = RatingAcc();
    }
    return s;
  }

  SideState side(ClubId c) => c == home.clubId ? home : away;

  SideState opponent(ClubId c) => c == home.clubId ? away : home;

  /// [side]'s mid under the opponent's pressing:
  /// `side.profile.mid × opponent.profile.pressMul`.
  double effectiveMid(SideState side) =>
      side.profile.mid * opponent(side.clubId).profile.pressMul;

  /// Recompiles [clubId]'s profile from its current pitch, condition and
  /// tactic; call after a substitution, sending-off, injury or tactic change.
  void rebuildProfile(World w, ClubId clubId) {
    final s = side(clubId);
    s.profile = buildProfile(
      w: w,
      tactic: s.tactic,
      onPitch: s.onPitch,
      condition: s.condition,
      home: s == home,
      cond: conditions,
      opponentTactic: opponent(clubId).tactic,
    );
  }
}
