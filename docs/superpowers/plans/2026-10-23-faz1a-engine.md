# Faz 1a — Match Engine Implementation Plan (engine side)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Project rule:** one agent at a time; the controller reviews small diffs directly; separate Fable reviews only for Tasks 5, 6, 9, 11, 12 and the final whole-branch review.

**Goal:** Replace the Poisson placeholder with the possession-based match engine of spec Bölüm 5: team profiles from lineups and the full tactic set, ~120 possession steps per match with chance creation, xG, shots, fouls, cards, injuries, condition decay, AI in-match management, substitutions, extra time and penalties, player ratings, a step-wise interactive session for the user's match, a detailed micro-event log for commentary and 2D, competition rules (subs, card thresholds), weather/pitch/attendance, and a calibration harness that proves the spec's distributions.

**Architecture:** All new code lives in `packages/engine/lib/src/sim/match/` behind the existing `MatchSimulator` interface. `MatchSession` is the single stateful object (step-wise, command-driven); `PossessionMatchSimulator.simulate()` just runs a session to the end with AI only, so fast mode and detailed mode share one code path and one RNG stream (visual coordinates use a separate fork). Every numeric constant lives in `tuning.dart`. Tactics are a new `Tactic` model on `Club` (3 slots); `MatchRules` lives on `League`. The day loop applies post-match discipline, injuries and stats. A `cm calibrate` CLI and slow tests gate the distributions.

**Tech Stack:** Dart 3.12, `package:test`; no new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-20-cm-simulation-design.md` — Bölüm 5 (5.1–5.6), 6.1 (maç içi sakatlık), 9 (kalibrasyon hedefleri), 11 (Faz 1a satırı), 14-3 (hızlı modda AI yönetir), 16.1 (taktik tam set), 16.8 (izleme modları, hava/zemin, seyirci, ceza kuralları, yedek kadro), 17 (test katmanları). Faz 0A engine README documents the current layout. The app side (narration TR/EN, tactics screen, live match screen) is a separate plan written after this one ships.

## Global Constraints

- Engine stays pure Dart, headless, deterministic: same seed + same commands ⇒ byte-identical `MatchResult` and world JSON; all randomness from `SeededRng`; sorted iteration; no `DateTime.now()` (Spec §2, §12).
- **One code path:** fast mode (`simulate`) and detailed mode (session with `MatchDetail.full`) must produce identical results with no commands; the detailed log consumes only the `visual` RNG fork (Spec §5.4).
- **Symmetry:** the engine never knows which side is the user; the host issues commands for a side (Spec §3, §14-3: AI decisions are applied by default for both sides).
- Calibration targets are binding and tested (Spec §9, §5.6): equal strength → goals/match 2.5–2.9, home 43–47 %, draw 24–28 %, away 27–31 %, shots 10–14 per team, on target 3.5–5, yellows 3–4 per match, reds 0.15–0.25, injuries 0.25–0.4, 0-0 7–9 %, 1-1 11–13 %, 1-0 9–11 %, 5+ goals 8–12 %; gap curve (stronger wins) +10 → 55 ±5, +20 → 65 ±5, +40 → 78 ±5; league season (20 teams, 100 seasons): champion 78–95 pts, last 18–32, median ≈ 50, strongest-3 in top-4 ≥ 80 %, strongest champion ≤ 70 %, top scorer 20–32.
- Performance budget unchanged: large-world match day p95 < 300 ms (≈500 matches/day ⇒ ≤ 0.6 ms per fast-mode match on an M-series Mac; measured, not assumed) (Spec §3).
- Save schema → **3** (club tactics, league rules, result extensions); migration 2→3 registered and tested (Spec §16.12).
- All tunables in `lib/src/sim/match/tuning.dart`; calibration changes touch only that file and are recorded in the engine README with measured numbers.
- Commit per task; Fable trailer for Fable commits.

## Review Focus

1. **A side with fewer than 11 available players mid-match** (red cards + injuries with no subs left): the step loop must keep running with 7–10 players, scale the profile, and abandon the match (3–0 loss) below 7, never crash. Pinned in Task 6.
2. **A user command naming a player who is not on the bench / already on / injured**: the session must reject with a typed error and leave state untouched. Pinned in Task 9.
3. **Stored tactic referencing a player who left the club** (captain, set-piece taker, instructions): profile building must ignore dangling ids and fall back to the auto choice, never throw. Pinned in Task 4.
4. **Old saves (schema 2) without tactics/rules/result extensions** must load, get default tactics and rules, and old results must render with empty stats. Pinned in Task 1.
5. **Extreme tactics stacked** (very attacking + hard tackling + high press + offside trap + counter): no multiplier chain may push a probability outside [0, 1] or a condition below 0; a 10k-match stress test with random tactic combinations must stay within sane bands. Pinned in Task 12.

---

## File Structure

```
packages/engine/lib/src/
  model/tactic.dart                 Tactic + enums (Mentality, PassingStyle, Tempo, Width, Pressing, Tackling, Marking, Arrow, CrossTarget), PlayerInstructions, SetPieceTakers, Lane + laneOf(Position), presets
  model/match_rules.dart            MatchRules (subs, benchSize, extraTime, penalties, yellowThresholds, redBan), defaults
  model/match_result.dart           TeamStats, MatchEvent (sealed), MatchConditions (Weather, pitch), result extensions (moved out of fixture.dart)
  model/match_log.dart              MatchLog, PossessionStep, MicroEvent (sealed), ChanceType, ShotOutcome, Pt
  model/club.dart                   + tactics: List<Tactic> (3), activeTactic: int; `formation` getter kept
  model/country.dart                League + rules: MatchRules
  model/events.dart                 + PlayerInjured, PlayerSentOff, PlayerSuspended (inbox)
  model/json.dart                   codecs for all of the above; schemaVersion 3
  persistence/migrations.dart       2→3
  sim/match/tuning.dart             EngineTuning: every constant, documented with the spec value and the calibrated value
  sim/match/team_profile.dart       playerEffectiveness(), TeamProfile, buildProfile()
  sim/match/match_state.dart        MatchState (mutable in-match state per side: on-pitch, condition, cards, subs, stats, tactic, events)
  sim/match/possession.dart         resolvePossession(): steps 1–7 of spec 5.3 → PossessionOutcome
  sim/match/side_effects.dart       fouls, cards, injuries, condition decay per step (spec 5.3 step 8)
  sim/match/ai_manager.dart         in-match AI (spec 5.3 step 9)
  sim/match/ratings.dart            player ratings + MOTM (spec 5.3 end)
  sim/match/extra_time.dart         extra time + penalty shootout (spec 16.3 rules, 14-4)
  sim/match/micro_events.dart       coordinates for detail mode (spec 5.3 step 11)
  sim/match/match_session.dart      MatchSession (step-wise), MatchCommand (sealed), MatchDetail, decision points
  sim/match/possession_match_simulator.dart   PossessionMatchSimulator implements MatchSimulator
  sim/match/conditions.dart         weather/pitch sampling + attendance
  sim/match/injury_table.dart       in-match injury severity → InjuryStub (Faz 1a simple table; Faz 2 refines)
  sim/discipline.dart               post-match card accumulation → suspensions; daily decrement of suspensions/injuries
  sim/day_loop.dart                 wires the new simulator, post-match discipline/injuries/stats, inbox events
  sim/lineup.dart                   autoLineup uses the active tactic's slots
  session/engine_session.dart       interactive user match API
  cli/commands.dart                 `cm calibrate`
  test/sim/match/**, test/slow/calibration_test.dart, test/slow/season_calibration_test.dart
```

---

### Task 1: Tactic model, lanes, presets, club tactics, schema v3 `[Model: Fable]`

**Files:**
- Create: `lib/src/model/tactic.dart`; Modify: `lib/src/model/club.dart`, `lib/src/model/json.dart`, `lib/src/model/world.dart` (`currentSchemaVersion = 3`), `lib/src/persistence/migrations.dart`, `lib/src/gen/world_generator.dart` (default tactics), `lib/src/sim/lineup.dart` (`autoLineup` slots from the active tactic), README; tests `test/model/tactic_test.dart`, `test/persistence/migrations_test.dart`, `test/sim/lineup_test.dart`.

**Interfaces:**
- Produces:
  ```dart
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
  Lane laneOf(Position p);                    // dl, ml, aml → left; dr, mr, amr → right; rest centre
  class PlayerInstructions { bool forwardRuns, runWithBall, longShots, throughBalls, holdUpBall, freeRole; CrossTarget crossFrom; }
  class SetPieceTakers { PlayerId? cornerLeft, cornerRight, freeKickLeft, freeKickRight, penalty, longThrow; }
  class Tactic {
    String name; Formation formation; List<Position> slots;        // slots.length == 11, index 0 gk; presets via formationSlots(f); Formation.custom allowed
    Mentality mentality; PassingStyle passing; Tempo tempo; Width width; Pressing pressing; Tackling tackling; Marking marking;
    bool offsideTrap, counterAttack; PlayerId? playmaker, targetMan, captain, viceCaptain;
    SetPieceTakers setPieces; Map<PlayerId, PlayerInstructions> instructions; Map<PlayerId, Arrow> arrows;
    static Tactic preset(Formation f, {String? name});             // balanced defaults
  }
  // Club: List<Tactic> tactics (exactly 3), int activeTactic (0..2); Tactic get tactic; Formation get formation => tactic.formation (compat)
  ```
- `Formation` gains `custom`. `formationSlots(custom)` throws; callers use `tactic.slots`.
- Migration 2→3: every club gets `tactics = [preset(club.formation, '1'), preset(f433, '2'), preset(f532, '3')]`, `activeTactic = 0`; the legacy `formation` key is dropped from club JSON (getter remains). Leagues get default `rules` (Task 2 adds the type; this migration only adds tactics — keep migrations composable: Task 2 extends the same 2→3 step since v3 is not shipped yet; document "v3 = tactics + rules + result extensions").
- JSON: `tactic` keys in declaration order; ids as ints; `instructions`/`arrows` keyed by decimal-string player id ascending.

- [ ] **Step 1:** Tests: `laneOf` for all 12 positions; `preset(f442)` slots == `formationSlots(f442)`, mentality balanced; JSON round trip of a tactic with instructions/arrows/set pieces; migration 2→3 on a v2 envelope gives 3 tactics with `activeTactic 0` and the first tactic's formation == old `formation`; `autoLineup` uses a custom `slots` list (e.g. 3-4-3 with `aml/amr`) — assert slot positions; world generator: every club has 3 tactics; `tool/check.sh --slow` still green (determinism gates unchanged since defaults are deterministic).
- [ ] **Step 2–4.** **Step 5:** Commit `feat(engine): tactic model, club tactic slots, schema v3`.

---

### Task 2: Match rules, conditions, attendance `[Model: Opus]`

**Files:**
- Create: `lib/src/model/match_rules.dart`, `lib/src/sim/match/conditions.dart`; Modify: `lib/src/model/country.dart` (`League.rules`), `lib/src/data/assets/countries.json` (+ `climate` per country: `temperate | mediterranean | continental | tropical | arid`), `lib/src/data/country_data.dart`, `json.dart`, migration 2→3 (rules default), generator; tests `test/model/match_rules_test.dart`, `test/sim/match/conditions_test.dart`.

**Interfaces:**
- Produces:
  ```dart
  class MatchRules { int substitutions /*5*/; int benchSize /*7*/; bool extraTime /*false*/; bool penalties /*false*/; List<int> yellowThresholds /*[5,10,15] → bans 1,2,3*/; int redBanSecondYellow /*1*/, redBanFoul /*3*/, redBanViolent /*4*/; static const league = MatchRules(...); }
  enum Weather { sunny, cloudy, rainy, heavyRain, snow, windy, hot }
  class MatchConditions { Weather weather; int pitch /*1..10*/; int attendance; double homeAdvantage /*1.03..1.08*/; }
  MatchConditions sampleConditions({required World w, required Fixture f, required SeededRng rng});   // rng = fork 'conditions:<fixtureId>:<season>'
  ```
- Weather table per climate × month (12×7 weights; e.g. temperate November: cloudy 35, rainy 30, heavyRain 10, windy 10, sunny 10, snow 3, hot 0). Pitch = clamp(round(stadium quality proxy `clubRep/10`) − seasonal wear (Dec–Feb −2, Nov/Mar −1) − (heavyRain ? 2 : rainy ? 1 : 0), 1, 10). Attendance = round(capacity × fill), fill = clamp(0.35 + 0.45 × homeRep/100 + 0.10 × awayRep/100 + 0.10 × homeFormFactor − weatherPenalty(heavyRain/snow 0.10, rainy 0.05), 0.2, 1.0) where `homeFormFactor` = wins in last 5 / 5 (0.5 when unknown). `homeAdvantage = 1.03 + 0.05 × fill`.
- [ ] **Step 1:** Tests: default rules values; JSON round trip; migration adds `rules` to every league; weather sampling over 2000 draws for `temperate` July has `sunny + hot ≥ 50 %` and `snow == 0`; December `continental` has `snow ≥ 10 %`; pitch bounds 1..10 across all months/weathers; attendance ≤ capacity and `homeAdvantage ∈ [1.03, 1.08]`; determinism by seed.
- [ ] **Step 2–4.** **Step 5:** Commit `feat(engine): match rules, weather/pitch, attendance`.

---

### Task 3: Result extensions and match log model `[Model: Opus]`

**Files:**
- Create: `lib/src/model/match_result.dart` (move `MatchResult`/`GoalEvent` here from `fixture.dart`, re-export from `fixture.dart` for compatibility), `lib/src/model/match_log.dart`; Modify: `json.dart`, `events.dart` (+3 inbox events), invariants `inbox.refs`/`fixture.goals` (goals ↔ `MatchEvent.goal` consistency), `test/model/json_test.dart`, `test/model/match_log_test.dart`.

**Interfaces:**
- Produces:
  ```dart
  class TeamStats { int shots, onTarget, blocked, corners, fouls, yellows, reds, offsides, possessionPct; double xg; }
  sealed class MatchEvent { int minute; int half /*1,2,3,4 = ET halves, 5 = shootout*/; ClubId clubId; }
    Goal(scorerId, assistId?, type: ChanceType, isPenalty, isOwnGoal=false) · Card(playerId, CardKind{yellow, secondYellow, red}, reason: FoulKind{normal, lastMan, violent}) · Injury(playerId, severityDays) · Substitution(outId, inId, reason: SubReason{injury, tactical, fatigue}) · PenaltyMissed(playerId, outcome: ShotOutcome) · TacticChange(mentality) · HalfTime · FullTime · ExtraTimeStart · ShootoutStart · ShootoutKick(playerId, scored)
  class MatchResult { int homeGoals, awayGoals; List<GoalEvent> goals; int matchSeed;      // existing
    TeamStats? homeStats, awayStats; List<MatchEvent> events; Map<PlayerId, double> ratings; PlayerId? manOfTheMatch; MatchConditions? conditions;
    int? homeShootout, awayShootout; bool abandoned; }                                      // new, all defaulted so v2 results decode
  enum ChanceType { throughBall, cross, longShot, dribble, corner, freeKick, penalty }
  enum ShotOutcome { goal, saved, blocked, post, off }
  class Pt { double x, y; }   // 0..100, attacking side plays upward
  sealed class MicroEvent { double t; }  Pass(from, to, a: Pt, b: Pt) · Dribble(who, a, b) · Cross(from, to, a, b) · Shot(who, a, target: Pt, outcome, keeperId?) · Tackle(who, victim, at) · Foul(who, victim, at) · Save(keeper, at) · Clearance(who, a, b)
  class PossessionStep { int minute; int half; ClubId attackingId; Lane lane; bool counter; ChanceType? chance; double? xg; ShotOutcome? outcome; PlayerId? shooter, assister; List<MicroEvent> micro; List<MatchEvent> events; }
  class MatchLog { List<PossessionStep> steps; }    // NOT persisted; produced only in detailed mode
  // GameEvent additions: PlayerInjured(playerId, clubId, days), PlayerSentOff(playerId, clubId, fixtureId), PlayerSuspended(playerId, clubId, matches)
  ```
- JSON: all new `MatchResult` fields serialised; absent keys decode to defaults (empty lists/maps, nulls, `abandoned false`). `MatchLog`/`MicroEvent` have **no** JSON (document).
- [ ] **Step 1:** Tests: v2-shaped result JSON (only the four old keys) decodes with empty extensions and re-encodes with the new keys present; full round trip incl. every `MatchEvent` subtype; `fixture.goals` invariant still passes with events present; new inbox events round-trip and are relevance-filtered (`isUserRelevant`: clubId == user club).
- [ ] **Step 2–4.** **Step 5:** Commit `feat(engine): match result extensions, match log model, injury/card inbox events`.

---

### Task 4: Tuning constants and team profiles `[Model: Fable]`

**Files:**
- Create: `lib/src/sim/match/tuning.dart`, `lib/src/sim/match/team_profile.dart`; tests `test/sim/match/team_profile_test.dart`.

**Interfaces:**
- Produces:
  ```dart
  abstract final class EngineTuning {   // every constant below is a `static const`; initial values = spec values
    possession: k1 = 0.25; chance: k2 = 0.20, chanceBase (logit solved so equal teams give 0.20 per possession); counterProb = 0.15, counterDefMul = 0.80;
    xgBase = {penalty 0.76, throughBall 0.30, cross 0.12, longShot 0.05, dribble 0.20, corner 0.08, freeKick 0.07}; finishingCoef = 0.02; keeperCoef = 0.015; saveBand = 0.25, blockBand = 0.20; cornerAfterSave = 0.30;
    foulPerStep = 0.10; yellowPerFoul = 0.12; redPerFoul = 0.008; injuryPerStepPerPlayer = 0.0025; conditionPerMinute = 0.25; tenMenMul = 0.85;
    homeAdvantageDefault = 1.06; stepSecondsMin = 30, stepSecondsMax = 90; penaltyPerMatch = 0.25;
    lane weights, tactic multipliers (spec 16.1 table), chance-type weights per lane/passing style, scorer weights (Task 5), rating constants (Task 7)
  }
  double playerEffectiveness(Player p, Attr a, Position slot) => attr × familiarity(0.6..1.0 mapped from 1..20) × conditionFactor(0.75..1.0) × sharpnessFactor(0.9..1.0) × moraleFactor(0.95..1.05) × formFactor(0.95..1.05);
  class TeamProfile { double mid, attL, attC, attR, defL, defC, defR, gk, setPieceAtt, setPieceDef; double tempoMul, pressMul, conditionDrain; Map<Lane,double> laneWeights; Map<ChanceType,double> chanceWeights; double foulMul, cardMul, injuryToOpponentMul; double throughBallXgMul /*offside trap*/; double counterProb; List<PlayerId> onPitch; Map<Position, PlayerId> bySlot; }
  TeamProfile buildProfile({required World w, required Tactic tactic, required List<PlayerId> onPitch /*≤11*/, required Map<PlayerId,double> condition, required bool home, required MatchConditions cond, required int playersOnPitch});
  ```
- Rules (spec 5.2 + 16.1 table, exact multipliers): mentality ±(0.85…1.15) on att/def; passing: longBall → `midBypass 0.30`, chance weights shift to cross/header, short → mid ×1.1; tempo → step seconds and drain ×(0.85…1.3); width → lane weights (narrow 25/50/25, normal 30/40/30, wide 40/20/40); pressing → opponent mid ×0.92 at high, own drain ×1.25; tackling → foul ×(0.8…1.3), card ×(0.8…1.4), injury-to-opponent ×(0.9…1.4), ball-winning (def) ×(0.95…1.1); man marking → opponent playmaker/target man effectiveness ×0.85 and own marker's attack ×0.8; offside trap → opponent through-ball xG ×0.75 with 12 % "trap fails" ×1.6 (applied per chance in Task 5); counter → counterProb 0.28 and counter attack ×1.15; arrows → forward: att ×1.25/def ×0.85 for that player; playmaker/target man → selection weight ×2 (Task 5); weather/pitch (16.8): rain/bad pitch short pass ×0.92, long ball ×1.05, keeper error ×1.3 (saveBand −0.05), injury ×1.15; hot → drain ×1.15; `home` → att & mid × `cond.homeAdvantage`. Fewer than 11 on pitch: mid & def × `tenMenMul^(11−n)`; ≤ 9: att ×0.9 additionally.
- Dangling ids (captain/takers/playmaker not on pitch) are ignored (Review Focus 3).
- [ ] **Step 1:** Tests (table-driven; a hand-built world with controlled attributes): effectiveness factors at the boundaries (familiarity 1 → ×0.6, 20 → ×1.0; condition 50 → ×0.75); profile with all attrs 10 and balanced tactic gives mid == gk == att* == def* == 10 ± 0.01 at condition 100; each tactic setting changes exactly the fields the table says (one test per setting, asserting the multiplier); home advantage; weather effects; 10 men; dangling playmaker id → no throw and weights unchanged.
- [ ] **Step 2–4.** **Step 5:** Commit `feat(engine): tuning constants and team profiles`.

---

### Task 5: Match state and possession resolution `[Model: Fable]` — separate Fable review

**Files:**
- Create: `lib/src/sim/match/match_state.dart`, `lib/src/sim/match/possession.dart`, `lib/src/sim/match/side_effects.dart`, `lib/src/sim/match/injury_table.dart`; tests `test/sim/match/possession_test.dart`, `test/sim/match/side_effects_test.dart`, `test/slow/possession_stats_test.dart`.

**Interfaces:**
- Produces:
  ```dart
  class SideState { ClubId clubId; Tactic tactic; List<PlayerId> onPitch; List<PlayerId> bench; Map<PlayerId,double> condition; Map<PlayerId,int> yellows; Set<PlayerId> sentOff; Set<PlayerId> injuredOff; int subsUsed; TeamStats stats; int goals; TeamProfile profile; bool userManaged; }
  class MatchState { SideState home, away; int minute; int half; int addedTime; double clockSeconds; List<MatchEvent> events; List<PossessionStep>? log; Map<PlayerId, RatingAcc> ratings; ClubId? lastPossession; bool pendingCorner; bool pendingCounterFor; }
  PossessionStep resolvePossession(MatchState s, World w, MatchRules rules, SeededRng rng, {required bool detail});   // steps 1–7; mutates stats/goals; returns the step (micro empty unless detail — Task 10 fills coordinates)
  void applySideEffects(MatchState s, PossessionStep step, World w, SeededRng rng);   // step 8: foul/card/injury/condition; appends MatchEvents to s.events and step.events
  InjuryStub rollInjury(SeededRng rng, {required bool fromFoul});   // table: minor 1–7 d 45 %, light 8–21 d 30 %, moderate 22–56 d 15 %, serious 57–150 d 8 %, severe 151–360 d 2 %; fromFoul shifts +10 % toward serious; types list per spec 6.2
  ```
- Possession step (spec 5.3): possession owner via `logistic(k1 × (mid_a − mid_b))` unless `pendingCorner` (same side) or counter flag; lane by `laneWeights`; chance via `logistic(k2 × (att_lane − def_lane) + chanceBase)` (counter: def ×0.8); chance type by weights (lane: wings favour cross/dribble, centre favours throughBall/longShot; passing style shifts; `penalty` only from a foul-in-box roll `penaltyPerMatch/steps`; corner/freeKick from pending flags); shooter weighted by chance type (throughBall → st/am ×3, cross → heading, longShot → longShots attr, dribble → dribbling) × instructions (longShots/throughBalls/forwardRuns ×1.5) × playmaker/targetMan ×2; assister from passing/crossing; xG per spec formula with finishing/composure/keeper; offside trap rule; outcome bands; save → 30 % corner; stats updated (shots/onTarget/blocked/corners/xg/possession seconds). Minute advances by `stepSeconds ∈ [30,90] / tempoMul`.
- Side effects: foul `foulPerStep × foulMul`, fouler = defending side weighted by aggression; card rolls; second yellow → red; red → `sentOff`, profile rebuilt by the session (Task 9) ; injury roll per on-pitch player per step (`injuryPerStepPerPlayer × injuryProneness(0.5..2.0) × condition<70 ×1.5 × condition<50 ×2.5 × age>31 ×1.3 × tempo ×1.2`), victim of a foul ×4; condition decay per minute `conditionPerMinute × (0.18 at stamina 20 … 0.35 at stamina 5) × drain`; events appended.
- [ ] **Step 1:** Unit tests with a scripted rng (`SeededRng` + `restore` or a stub implementing the same interface — add `abstract interface class Rng` extracted from `SeededRng` if needed, Fable's call): possession favours higher mid; chance probability at equal lanes ≈ 0.20 (10k steps, ±0.02); xG formula values for pinned inputs; outcome bands; corner follow-up; second yellow produces `Card(secondYellow)` and `sentOff`; injury table proportions (20k rolls); condition decay per stamina. Slow: 20k steps of equal teams → shots per 120 steps ≈ 12 per side, on-target share 0.30–0.40, fouls ≈ 12 per match, yellows ≈ 1.5 per side, injuries ≈ 0.15 per side.
- [ ] **Step 2–4.** **Step 5:** Commit `feat(engine): match state, possession resolution, side effects, injury table`.

---

### Task 6: In-match AI, substitutions, short-handed play `[Model: Fable]` — separate Fable review

**Files:**
- Create: `lib/src/sim/match/ai_manager.dart`; Modify: `match_state.dart` (`applySubstitution`, `rebuildProfile`); tests `test/sim/match/ai_manager_test.dart`.

**Interfaces:**
- Produces:
  ```dart
  sealed class MatchCommand { ClubId clubId; }  Substitute(outId, inId) · SetMentality(Mentality) · SetTactic(Tactic) /* full swap incl. slots */
  class CommandError implements Exception { CommandErrorKind kind; }  enum CommandErrorKind { notOnPitch, notOnBench, noSubsLeft, ineligible, sameSide, invalidTactic }
  void applyCommand(MatchState s, World w, MatchRules rules, MatchCommand c);   // validates (Review Focus 2) then mutates; records Substitution/TacticChange events; rebuilds the side profile
  List<MatchCommand> aiDecide(MatchState s, SideState side, World w, MatchRules rules);   // called every 5 match minutes and after injuries; spec 5.3 step 9
  ```
- AI rules: minute ≥ 60 and behind → mentality +1 (max veryAttacking) once; minute ≥ 75 and ahead → −1 once; condition < 65 → sub with the best bench player for that slot (same position first, familiarity ≥ 12 next) while subs remain; injured on-pitch player → forced sub (or play short if no subs); never subs a GK unless injured/sent off; `userManaged` sides: AI still does forced subs and fatigue subs but skips mentality shifts.
- Short-handed: ≤ 10 → profile `tenMenMul`; < 7 on pitch → match abandoned: `abandoned = true`, score set to 0–3 against the short side (or 3–0), `FullTime` event immediately (Review Focus 1).
- [ ] **Step 1:** Tests: each AI rule fires at the right minute/score once; forced sub after injury; no subs left → plays with 10; command validation errors (all six kinds); `Substitute` updates onPitch/bench/subsUsed and rebuilds the profile; abandonment below 7.
- [ ] **Step 2–4.** **Step 5:** Commit `feat(engine): in-match AI, commands, short-handed rules`.

---

### Task 7: Ratings and man of the match `[Model: Opus]`

**Files:**
- Create: `lib/src/sim/match/ratings.dart`; tests `test/sim/match/ratings_test.dart`.

**Interfaces:**
- Produces: `class RatingAcc { double value = 6.0; }`, `void creditRating(MatchState s, RatingEvent e)` with `enum RatingEvent { goal(+1.0), assist(+0.5), save(+0.1), possessionLost(−0.05), criticalError(−0.5), yellow(−0.3), red(−1.0) }`, `void finaliseRatings(MatchState s)` (team win +0.3 to the winners' on-pitch and subbed players; clean sheet +0.5 to defenders and GK; clamp 1..10; players who played < 10 min get no rating), `PlayerId manOfTheMatch(MatchState s)` (highest rating, tie → more goals, then lower id).
- [ ] **Step 1:** Tests: pinned sequences give pinned ratings; clamp; clean-sheet logic; MOTM tie-break.
- [ ] **Step 2–4.** **Step 5:** Commit `feat(engine): player ratings and man of the match`.

---

### Task 8: Extra time and penalty shootout `[Model: Opus]`

**Files:**
- Create: `lib/src/sim/match/extra_time.dart`; tests `test/sim/match/extra_time_test.dart`.

**Interfaces:**
- Produces: `bool needsExtraTime(MatchState s, MatchRules r)` (rules.extraTime && level after 90+added); `void playExtraTime(MatchState s, …)` — two 15-minute halves (`half 3, 4`), condition drain ×1.2, an extra substitution allowed; `void playShootout(MatchState s, …)` — 5 kicks each then sudden death, kicker order: penalty taker first, then by `composure + finishing` desc among on-pitch; kick scored with p = `0.76 × (1 + 0.02 × (finishing + composure − 20)) × (1 − 0.015 × (gk − 10))` clamped 0.4..0.95; `ShootoutKick` events; `homeShootout/awayShootout` set; winner via `s.shootoutWinner`.
- [ ] **Step 1:** Tests: no ET when rules say so; ET played only when level; shootout ends at the first unreachable margin; sudden death terminates; determinism.
- [ ] **Step 2–4.** **Step 5:** Commit `feat(engine): extra time and penalty shootout`.

---

### Task 9: MatchSession, simulator, equivalence `[Model: Fable]` — separate Fable review

**Files:**
- Create: `lib/src/sim/match/match_session.dart`, `lib/src/sim/match/possession_match_simulator.dart`; Modify: `lib/src/sim/match_simulator.dart` (`MatchContext` + `rules`, `conditions`, `homeTactic`, `awayTactic`, `detail`), `lib/engine.dart`; tests `test/sim/match/match_session_test.dart`, `test/sim/match/equivalence_test.dart`.

**Interfaces:**
- Produces:
  ```dart
  enum MatchDetail { result, events, full }      // result: no log; events: MatchEvents only; full: PossessionSteps with micro-events
  class MatchContext { … existing …; MatchRules rules; MatchConditions conditions; Tactic homeTactic, awayTactic; MatchDetail detail; }
  class MatchSession {
    MatchSession(MatchContext ctx);
    MatchState get state; bool get finished; int get minute;
    List<PossessionStep> step({int count = 1});                // advances `count` possession steps (AI checks fire inside); returns the steps (micro-events only in `full`)
    List<PossessionStep> runUntil({int? minute, bool stopOnEvent = true});   // stops after the step that produces a Goal/Card/Injury/HalfTime/FullTime when stopOnEvent, or at `minute`
    void apply(MatchCommand c);                                 // only between steps; throws CommandError
    void setUserManaged(ClubId side, bool managed);
    MatchResult finish();                                       // runs to the end if not finished; ET/shootout per rules; ratings; returns the result (idempotent)
    MatchLog? get log;                                          // non-null in `full`
  }
  class PossessionMatchSimulator implements MatchSimulator { MatchResult simulate(MatchContext ctx) => MatchSession(ctx).finish(); }
  ```
- RNG discipline: `ctx.rng` drives outcomes; `ctx.rng.fork('visual')` drives Task 10 coordinates only; `matchSeed = rng.nextUint32()` first (as before). Half-time at 45 + added; added time 1–6 per half from cards/injuries/goals/subs counts (deterministic formula + 1 die).
- [ ] **Step 1:** Tests: `simulate()` on a generated small world fixture gives 90+ minutes, two `HalfTime`/`FullTime` events, stats consistent (`goals == Goal events`, `shots ≥ onTarget ≥ goals`); equivalence: `simulate` vs `MatchSession.step` loop vs `runUntil` loop vs `detail: full` → identical `MatchResult` JSON for 200 seeded fixtures; `apply(Substitute)` changes the result (deterministically); `CommandError` kinds; `userManaged` suppresses AI mentality shifts; abandoned match path; `finish()` idempotent.
- [ ] **Step 2–4.** **Step 5:** Commit `feat(engine): MatchSession and possession match simulator`.

---

### Task 10: Micro-event coordinates (detail mode) `[Model: Opus]`

**Files:**
- Create: `lib/src/sim/match/micro_events.dart`; tests `test/sim/match/micro_events_test.dart`.

**Interfaces:**
- Produces: `List<MicroEvent> buildMicroEvents(PossessionStep step, SideState attacking, SideState defending, SeededRng visualRng)` — 2–6 events per spec 5.3 step 11: start in own half (y 30–50) at the lane's x band (left 15–35, centre 40–60, right 65–85), a pass or two toward the final third, lane-specific build-up (cross from x ≤ 20 or ≥ 80 at y 80–92; through ball to y 85–95; long shot from y 70–78; dribble diagonal), a `Shot` with `target` on the goal line (x 44–56, y 100) and the step's outcome; no-chance steps end with a `Tackle`/`Clearance` by a defender; fouls add `Foul` at the ball position; times `t` ascending with 1.0–2.5 s gaps.
- [ ] **Step 1:** Tests: coordinates within 0..100; ascending `t`; the last event of a chance step is a `Shot` whose `outcome` equals `step.outcome`; participants ⊂ on-pitch of the right side; determinism with the visual fork; no outcome RNG consumption (run `simulate` with and without `full` → identical result — covered in Task 9, re-asserted here on 50 fixtures).
- [ ] **Step 2–4.** **Step 5:** Commit `feat(engine): micro-event coordinates for detailed mode`.

---

### Task 11: Day-loop integration, discipline, session API `[Model: Fable]` — separate Fable review

**Files:**
- Create: `lib/src/sim/discipline.dart`; Modify: `lib/src/sim/day_loop.dart`, `lib/src/session/engine_session.dart`, `lib/src/invariants/invariants.dart`, `lib/src/cli/commands.dart` (`simulate` report adds cards/injuries), README; tests `test/sim/day_loop_test.dart`, `test/sim/discipline_test.dart`, `test/session/engine_session_test.dart`, `test/invariants/invariants_test.dart`.

**Interfaces:**
- Produces:
  ```dart
  // discipline.dart
  List<GameEvent> applyPostMatch(World w, Fixture f, MatchResult r, MatchRules rules);   // stats (apps/goals/assists/yellows/reds/ratingSum/minutes?), yellow accumulation → PlayerSuspended at thresholds, red → suspension by reason, injuries → state.injury + PlayerInjured, condition written back from the session's final condition
  void dailyRecovery(World w);        // suspensions decrement when the player's club plays (per matchday: in playMatches, decrement suspensionMatches of absent players of both clubs); injuries: daysLeft −1 per day, cleared at 0 with sharpness set to 40 (spec 6.3)
  // DayRunner: default sim = PossessionMatchSimulator; startOfDay: condition +12/day stays; playMatches builds MatchContext with rules (league), conditions (sampleConditions), tactics (club.tactic), detail: result; after each match applyPostMatch; user-side: none (symmetry)
  // EngineSession interactive API:
  MatchSession startUserMatch({MatchDetail detail = MatchDetail.events});   // today must be a user match day (nextUserMatchDate() == date) else StateError; marks the fixture as "in progress" in memory only
  void finishUserMatch();     // takes the session's result, stores it on the fixture, then runs the REST of the day (other fixtures + endOfDay) exactly as advanceDay would; returns DaySummary
  ```
- Determinism rule: `startUserMatch` + `finishUserMatch` with no commands must equal `advanceDay()` for the same day (same fixture fork, same order: the user's fixture is simulated with the same rng fork regardless of order; other fixtures unaffected since each has its own fork).
- Invariants: `player.suspended` (suspended players not in a stored lineup), `injury.consistent` (injured players not on pitch — covered by lineup.valid), `stats.consistent` (season apps ≥ goals? no: `goals ≤ apps × 10` sanity), `result.extended` (every result of the current season has stats and events).
- [ ] **Step 1:** Tests: a small-world season via `advanceDay`: every result has stats/events; yellow accumulation at 5 → `PlayerSuspended(1)` and the player misses exactly the next match (not in lineup) then plays; red (foul) → 3 matches; injuries land in `state.injury` and heal with sharpness 40; condition carries over between matches; `startUserMatch`/`finishUserMatch` equivalence with `advanceDay` (JSON equal) on 5 seeds; with a `Substitute` command the result differs but the day still completes; CLI `simulate` prints cards/injuries per season; `tool/check.sh --slow` green (long-sim invariants incl. the new rules; the Poisson-era gates on goals/home % now measure the new engine — expected to pass after Task 12's calibration; if Task 11 lands before calibration, run the long sim and record the numbers but gate thresholds are asserted in Task 12).
- [ ] **Step 2–4.** **Step 5:** Commit `feat(engine): possession engine wired into the day loop; discipline, injuries, interactive user match`.

---

### Task 12: Calibration harness and tuning `[Model: Fable]` — separate Fable review

**Files:**
- Create: `test/slow/calibration_test.dart`, `test/slow/season_calibration_test.dart`, `test/slow/tactic_stress_test.dart`; Modify: `lib/src/cli/commands.dart` (`cm calibrate`), `tuning.dart` (tuned values), README (calibration table).

- `cm calibrate --seed N --matches 20000 [--report path]`: builds two synthetic clubs at CA 120 (all attrs 12, condition 100, balanced tactics) and prints the full distribution (goals, H/D/A, shots, on target, corners, fouls, yellows, reds, injuries, score histogram, possession split, xG); `--gap 10|20|40` variants (home stronger and away stronger averaged); `--season` runs 100 seasons of a 20-team synthetic league with CA spread sd 13 and prints champion/last/median points, top-4 hit rate, champion hit rate, top scorer.
- Slow tests assert every Global-Constraint band. Tuning loop: adjust only `tuning.dart`; record each iteration's numbers in the report; stop when all bands pass with ≥ 1 pp margin where possible.
- Tactic stress (Review Focus 5): 10k matches with uniformly random tactic settings on both sides → goals/match within 1.5–4.5, no NaN, no probability assertion failures (add `assert` guards in possession for [0,1] ranges), condition ≥ 0, every match finishes.
- Performance: 1000 fast-mode matches on the large world's clubs < 600 ms total (≤ 0.6 ms each) — if missed, profile and optimise `buildProfile` caching (profiles rebuilt only on sub/card/tactic change) before touching gameplay.
- [ ] **Step 1:** Write the harness and tests; run; tune; re-run `tool/check.sh --slow` (the Faz 0 long-sim and perf gates must still pass with the new engine — update their goals/home bands to the spec's if the Poisson-era widening is no longer needed).
- [ ] **Step 2:** Commit `feat(engine): calibration harness; tuned possession engine`.

---

### Task 13: Acceptance `[Model: Fable]`

- [ ] `tool/check.sh --slow` from a clean checkout green; `cm simulate --size medium --seasons 3 --invariants` 0 violations; `cm calibrate` report pasted into this plan's Results section with the final tuning table; README updated (engine v0.2.0, schema 3, tuning table, interactive session API).
- [ ] Final whole-branch review (Fable), one fix wave, finishing (merge to `main` only after Hakan's approval, then push). Hand off to the Faz 1a app plan (narration TR/EN, tactics screen, live match screen) which consumes `MatchSession`, `MatchDetail`, `MatchCommand`, `PossessionStep`/`MicroEvent`, `MatchEvent`, `TeamStats`, `Tactic` exactly as named here.

---

## Self-review notes

- Spec coverage (Faz 1a row): Bölüm 5.2 (T4), 5.3 steps 1–7 (T5), 8 (T5), 9 (T6), 10 (T9 added time), 11 (T10), ratings (T7), 5.4 modes (T9 `MatchDetail`), 5.6 curve (T12), 6.1 in-match injuries (T5/T11), 16.1 tactic set (T1/T4/T5), 16.3 rules (T2/T11), 16.8 weather/attendance/cards/subs (T2/T11), 14-3/14-4 ET+pens (T8), 14-3 AI default (T6/T9), 9 calibration (T12), 17 tests throughout. Spec 5.5/5.7 (screens, 2D) and narration are the app plan.
- Names consistent: `Tactic`, `MatchRules`, `MatchConditions`, `TeamProfile`, `MatchState`/`SideState`, `PossessionStep`, `MicroEvent`, `MatchEvent`, `MatchCommand`/`CommandError`, `MatchSession`, `MatchDetail`, `PossessionMatchSimulator`, `applyPostMatch`, `startUserMatch`/`finishUserMatch`.
- Review Focus pins: 1 → T6; 2 → T9 (and T6 validation); 3 → T4; 4 → T1/T3; 5 → T12.
