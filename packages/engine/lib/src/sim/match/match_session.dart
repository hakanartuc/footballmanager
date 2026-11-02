import '../../core/ids.dart';
import '../../core/rng.dart';
import '../../model/club.dart';
import '../../model/match_conditions.dart';
import '../../model/match_log.dart';
import '../../model/match_result.dart';
import '../../model/match_rules.dart';
import '../../model/tactic.dart';
import '../../model/world.dart';
import '../match_simulator.dart';
import 'ai_manager.dart';
import 'extra_time.dart';
import 'match_state.dart';
import 'micro_events.dart';
import 'possession.dart';
import 'ratings.dart';
import 'side_effects.dart';
import 'tuning.dart';

/// One match played possession step by possession step (spec 5.3, 5.4):
/// the same loop serves `PossessionMatchSimulator` (run to the end at
/// once) and the live match screen (stepped, paused on events, with the
/// user's commands in between). Playing the same `MatchContext` either
/// way gives the same `MatchResult`.
///
/// Resolved once in the constructor from the context: `rules ??
/// MatchRules.league`, `conditions ?? MatchConditions.neutral`, and per
/// side `homeTactic`/`awayTactic` ?? the club's active tactic when its
/// formation is the lineup's, else `Tactic.preset(lineup.formation)` (a
/// club absent from the world counts as having no tactic). A tactic whose
/// slot count differs from the lineup's starters throws [ArgumentError]:
/// the session never guesses slot alignment.
///
/// Draw order on `ctx.rng`: [matchSeed] (`nextUint32`) first; then per
/// step `resolvePossession`'s draws, `applySideEffects`' draws, and — on
/// the first step that reaches `halfEnd(half)` — one
/// `nextInt(addedTimeDieSides)` for the half's added time; at the end of
/// a level half 4 (or half 2 without extra time) `playShootout`'s draws.
/// `aiDecide` draws nothing. The constructor forks `ctx.rng.fork('visual')`
/// for the coordinates (a fork depends on the seed only, so it consumes
/// nothing); `buildMicroEvents` draws only from that fork, so the detail
/// level never changes the result.
///
/// One [step]: `resolvePossession` → `applySideEffects` → in
/// `MatchDetail.full`, `buildMicroEvents` into `step.micro` → rebuild the
/// profile of every side that lost a player (injury, red, second yellow)
/// → `checkAbandon` (abandoned ends the match) → AI check, home then away
/// → half boundary → the step goes to [log] in `MatchDetail.full`.
///
/// AI check: a side that is not user-managed decides (`aiDecide`, every
/// command applied in order) when the match clock is at least
/// `EngineTuning.aiCheckInterval` minutes past its previous check, or
/// right after a step that injured one of its players. A user-managed
/// side is never asked: `runUntil` stops on the injury and the user
/// decides; without a substitute the side plays short.
///
/// Half boundary (spec 5.3 step 10): when the clock reaches
/// `halfEnd(half)` the half's added time is drawn once,
/// `addedTimeBase + (goals + substitutions + bookings + injuries of this
/// half + 1) ~/ 2 + die`, clamped to `addedTimeMin..addedTimeMax`. The
/// half ends at the first step whose end minute reaches `halfEnd(half) +
/// addedTime`. A break ([HalfTime] after halves 1 and 3, [ExtraTimeStart]
/// after a level half 2 under extra-time rules) resets the clock to the
/// next half's start and clears the pending set pieces, counter and last
/// possession; nothing recovers. The match ends with [FullTime] after
/// half 2 or 4, preceded by the shootout when the rules have penalties
/// and the sides are level.
class MatchSession {
  /// Resolves the defaults, draws [matchSeed] and starts the match.
  MatchSession(MatchContext ctx)
    : _ctx = ctx,
      rules = ctx.rules ?? MatchRules.league,
      matchSeed = ctx.rng.nextUint32(),
      _visualRng = ctx.rng.fork('visual') {
    final w = ctx.world;
    final f = ctx.fixture;
    state = MatchState.start(
      w: w,
      f: f,
      homeLineup: ctx.home,
      awayLineup: ctx.away,
      homeTactic: _tactic(w, f.homeId, ctx.home, ctx.homeTactic),
      awayTactic: _tactic(w, f.awayId, ctx.away, ctx.awayTactic),
      rules: rules,
      conditions: ctx.conditions ?? MatchConditions.neutral,
    );
    log = ctx.detail == MatchDetail.full ? MatchLog() : null;
    state.log = log?.steps;
    _lastAiMinute = {f.homeId: 0, f.awayId: 0};
  }

  final MatchContext _ctx;
  final MatchRules rules;

  /// The first draw of the match stream, stored on the result.
  final int matchSeed;
  late final MatchState state;

  /// The detailed mode's coordinate stream; never drawn otherwise.
  final Rng _visualRng;

  /// The possession steps so far; non-null only in `MatchDetail.full`.
  late final MatchLog? log;
  late final Map<ClubId, int> _lastAiMinute;
  int _lastRefreshMinute = 0;
  bool _finished = false;
  MatchResult? _result;

  /// True once a [FullTime] has been appended (also by abandonment).
  bool get finished => _finished;

  int get minute => state.minute;

  /// Advances up to [count] steps, fewer when the match ends; returns the
  /// steps taken (`micro` is filled only in `MatchDetail.full`). Nothing
  /// happens on a finished match.
  List<PossessionStep> step({int count = 1}) {
    final out = <PossessionStep>[];
    for (var i = 0; i < count && !_finished; i++) {
      out.add(_step());
    }
    return out;
  }

  /// Steps until the match ends, until the clock reaches [minute] when
  /// given, or — when [stopOnEvent] — right after a step that produced a
  /// [Goal], [Booking], [Injury], [PenaltyMissed], [HalfTime], [FullTime],
  /// [ExtraTimeStart] or [ShootoutStart]. Returns the steps taken.
  List<PossessionStep> runUntil({int? minute, bool stopOnEvent = true}) {
    final out = <PossessionStep>[];
    while (!_finished && (minute == null || state.minute < minute)) {
      final before = state.events.length;
      out.add(_step());
      if (stopOnEvent && state.events.skip(before).any(_stops)) break;
    }
    return out;
  }

  /// Applies the user's [c] between steps (`applyCommand`: it validates,
  /// throws [CommandError] and leaves the state unchanged on error).
  /// Throws [StateError] once the match is finished.
  void apply(MatchCommand c) {
    if (_finished) throw StateError('the match is finished');
    applyCommand(state, _ctx.world, rules, c);
  }

  /// Marks [side] as managed by the user: the AI makes no decisions for
  /// it. Takes effect from the next step.
  void setUserManaged(ClubId side, bool managed) {
    state.side(side).userManaged = managed;
  }

  /// Runs the rest of the match without stopping, finalises the ratings
  /// and returns the result; later calls return the same object.
  MatchResult finish() {
    if (_result case final r?) return r;
    runUntil(stopOnEvent: false);
    final s = state;
    finaliseRatings(s);

    final total = s.home.possessionSeconds + s.away.possessionSeconds;
    final homePct = total == 0
        ? 50
        : (s.home.possessionSeconds / total * 100).round();
    s.home.stats.possessionPct = homePct;
    s.away.stats.possessionPct = 100 - homePct;

    return _result = MatchResult(
      homeGoals: s.home.goals,
      awayGoals: s.away.goals,
      // An abandoned match is awarded 0–3 (or 0–0); the real goals stay in
      // [events] but are not credited.
      goals: [
        if (!s.abandoned)
          for (final e in s.events)
            if (e is Goal)
              GoalEvent(
                minute: e.minute,
                scorerId: e.scorerId,
                clubId: e.clubId,
              ),
      ],
      matchSeed: matchSeed,
      homeStats: s.home.stats,
      awayStats: s.away.stats,
      events: List.of(s.events),
      ratings: {
        for (final id in s.ratings.keys.toList()..sort())
          id: s.ratings[id]!.value,
      },
      manOfTheMatch: manOfTheMatch(s),
      conditions: s.conditions,
      homeShootout: s.homeShootout,
      awayShootout: s.awayShootout,
      abandoned: s.abandoned,
    );
  }

  PossessionStep _step() {
    final s = state;
    final w = _ctx.world;
    final rng = _ctx.rng;
    final step = resolvePossession(
      s,
      w,
      rng,
      detail: _ctx.detail == MatchDetail.full,
    );
    applySideEffects(s, step, w, rng);
    if (_ctx.detail == MatchDetail.full) {
      step.micro = buildMicroEvents(
        step,
        s.side(step.attackingId),
        s.opponent(step.attackingId),
        _visualRng,
      );
    }

    final lostPlayer = <ClubId>{};
    final injured = <ClubId>{};
    for (final e in step.events) {
      switch (e) {
        case Injury():
          lostPlayer.add(e.clubId);
          injured.add(e.clubId);
        case Booking(kind: CardKind.red || CardKind.secondYellow):
          lostPlayer.add(e.clubId);
        default:
          break;
      }
    }
    for (final side in [s.home, s.away]) {
      if (lostPlayer.contains(side.clubId)) s.rebuildProfile(w, side.clubId);
    }

    if (checkAbandon(s)) {
      _finished = true;
    } else {
      for (final side in [s.home, s.away]) {
        _aiCheck(side, injured: injured.contains(side.clubId));
      }
      _refreshProfiles();
      _boundary();
    }
    log?.steps.add(step);
    return step;
  }

  /// Rebuilds both profiles every [EngineTuning.aiCheckInterval] minutes so
  /// the condition drain reaches lane strengths (spec 5.3 step 8); draws
  /// nothing. User-managed sides are refreshed too.
  void _refreshProfiles() {
    final s = state;
    if (s.minute < _lastRefreshMinute + EngineTuning.aiCheckInterval) return;
    _lastRefreshMinute = s.minute;
    s.rebuildProfile(_ctx.world, s.home.clubId);
    s.rebuildProfile(_ctx.world, s.away.clubId);
  }

  void _aiCheck(SideState side, {required bool injured}) {
    if (side.userManaged) return;
    final s = state;
    if (!injured &&
        s.minute < _lastAiMinute[side.clubId]! + EngineTuning.aiCheckInterval) {
      return;
    }
    _lastAiMinute[side.clubId] = s.minute;
    final w = _ctx.world;
    for (final c in aiDecide(s, side, w, rules)) {
      applyCommand(s, w, rules, c);
    }
  }

  void _boundary() {
    final s = state;
    final end = halfEnd(s.half);
    if (s.minute < end) return;
    if (s.addedTime == 0) s.addedTime = _drawAddedTime();
    if (s.minute < end + s.addedTime) return;
    switch (s.half) {
      case 1:
        _break(HalfTime(minute: s.minute, half: 1, clubId: s.home.clubId));
        s.half = 2;
        s.minute = 45;
      case 2:
        if (needsExtraTime(s, rules)) {
          startExtraTime(s);
          _clearPending();
        } else {
          _fullTime();
        }
      case 3:
        _break(HalfTime(minute: s.minute, half: 3, clubId: s.home.clubId));
        s.half = 4;
        s.minute = 105;
      case 4:
        _fullTime();
    }
    if (!_finished) s.clockSeconds = s.minute * 60.0;
  }

  /// This half's added time: `addedTimeBase + (events + 1) ~/ 2 + die`,
  /// counting the half's goals, substitutions, bookings and injuries.
  int _drawAddedTime() {
    final s = state;
    var n = 0;
    for (final e in s.events) {
      if (e.half == s.half &&
          (e is Goal || e is Substitution || e is Booking || e is Injury)) {
        n++;
      }
    }
    final added =
        EngineTuning.addedTimeBase +
        (n + 1) ~/ 2 +
        _ctx.rng.nextInt(EngineTuning.addedTimeDieSides);
    return added.clamp(EngineTuning.addedTimeMin, EngineTuning.addedTimeMax);
  }

  void _break(HalfTime e) {
    state.events.add(e);
    state.addedTime = 0;
    _clearPending();
  }

  void _clearPending() {
    state
      ..pendingCorner = null
      ..pendingFreeKick = null
      ..pendingPenalty = null
      ..pendingCounter = null
      ..lastPossession = null;
  }

  void _fullTime() {
    final s = state;
    if (needsShootout(s, rules)) playShootout(s, _ctx.world, _ctx.rng);
    s.events.add(
      FullTime(minute: s.minute, half: s.half, clubId: s.home.clubId),
    );
    _finished = true;
  }

  static bool _stops(MatchEvent e) => switch (e) {
    Goal() ||
    Booking() ||
    Injury() ||
    PenaltyMissed() ||
    HalfTime() ||
    FullTime() ||
    ExtraTimeStart() ||
    ShootoutStart() => true,
    _ => false,
  };

  static Tactic _tactic(World w, ClubId clubId, Lineup lineup, Tactic? given) {
    final club = w.clubs[clubId];
    final t =
        given ??
        (club != null && club.tactic.formation == lineup.formation
            ? club.tactic
            : Tactic.preset(lineup.formation));
    if (t.slots.length != lineup.starters.length) {
      throw ArgumentError(
        'tactic ${t.name} has ${t.slots.length} slots for '
        '${lineup.starters.length} starters of club $clubId',
      );
    }
    return t;
  }
}
