# engine

Pure-Dart football-manager simulation engine (Faz 0A + Faz 1a match
engine). Hosts (the Flutter app, the CLI in `bin/cm.dart`) talk to it only
through `EngineSession`. Engine version 0.2.0 (`pubspec.yaml`; 0.1.x was
the Faz 0 Poisson placeholder), save schema 3.

## Running the tests

```sh
dart test -x slow              # fast suite: unit, scenario and determinism tests (seconds)
dart test -t slow              # slow suite: long simulation, performance and statistics
tool/check.sh                  # format + analyze + fast suite
tool/check.sh --slow           # the same, then the slow suite
```

Slow tests carry `@Tags(['slow'])` and get a 30-minute timeout from
`dart_test.yaml`. They print a one-line summary each; the fast suite prints
nothing. Every slow test file builds its own world, so files can be run on
their own, e.g. `dart test -t slow test/slow/perf_test.dart`.

## Acceptance gates (spec §9, §17.3, §18.6)

All gates are real assertions. Thresholds are Faz 0 bounds; the spec's
30-season and 100-season checks arrive with the later phases.

| Test | World | Gate |
| --- | --- | --- |
| `test/determinism_test.dart` (fast) | small, seed 7, user at the first TR tier-1 club, `SetLineup` on day 3, 120 days | Two sessions give byte-identical `jsonEncode(worldToJson(world))`; the same run inside `Isolate.run` gives the same JSON; a session restored from a save taken on day 60 ends identical to the uninterrupted one. |
| `test/slow/long_sim_test.dart` | small, seed 11, 5 seasons, `advanceDay` loop | `checkInvariants()` after every day: zero violations (this covers senior squads 18..28 daily). Per season: goals/match in 2.5..3.0, home wins 43..47 %, every archived champion equals both the first row of the archived `finalOrder` and the table computed on the morning of `seasonEnd`; youth squad per club ≤ 21 and senior goalkeepers per club ≥ 2 at every season end. At season 5: total player count within ±10 % of season 2; age buckets 16–20 / 21–25 / 26–30 / 31+ within ±8 points of season 3. |
| `test/slow/perf_test.dart` | large, seed 1, 400 days | Generation < 8 s; match-day `summary.elapsed` p95 < 300 ms and non-match-day p95 < 50 ms (nearest-rank percentile; the first 5 match days are JIT warm-up and are left out); `save()` < 15 MB and < 2 s; `EngineSession.fromBytes` < 2 s. Peak RSS is not measured here (Faz 0B measures on device). |
| `test/slow/world_generator_perf_test.dart` | large, seed 1 | Generation < 8 s. |
| `test/slow/invariants_perf_test.dart` | large, seed 1 | One `checkInvariants` pass < 50 ms. |
| `test/slow/possession_stats_test.dart` | 20k possession steps | Per-step sanity bands of the possession engine (chances, shots, fouls, cards, injuries, xG). |
| `test/slow/calibration_test.dart` | synthetic CA-120 pair, seed 1, 10 000 matches + 3 × 4 000 | Spec §9 single-match bands and the §5.6 gap curve (±5 points); see "Calibration". |
| `test/slow/season_calibration_test.dart` | synthetic 20-club league, seed 1, 100 seasons | Spec §9 season bands: champion / last / median points, strongest-three top-four share, strongest-one champion cap, top scorer. |
| `test/slow/tactic_stress_test.dart` | 10 000 synthetic matches, random tactics | Every tactic setting, formation (custom included) and strength 80..160 drawn at random on both sides: every match finishes, no NaN in statistics, ratings or condition, 1.5..4.5 goals per match; the engine's probability `assert`s hold. |
| `test/slow/perf_test.dart` (added) | large world, first 1 000 fixtures | 1 000 fast-mode `simulate` calls (contexts built outside the timing, 100 warm-up matches) < 600 ms. |

Measured on an Apple Silicon Mac (JIT, `dart test`, Task 13 constants):
large world generates in ~160 ms; match day p50 119 ms / p95 133 ms (up
to ~250 matches a day), other day p50 2.2 ms / p95 2.9 ms; save 4.96 MB
in ~1.0 s, load ~0.76 s (results carry events, statistics and ratings).
Small world, 5 seasons with daily invariant checks: ~14 s. One fast-mode
match ≈ 0.41 ms (1 000 large-world matches in 413 ms; 779 ms before Task
12 cached the per-player injury and drain constants that
`applySideEffects` read on every step — `PlayerMatchConsts` on
`SideState`).

### Band notes

- **Goals, home wins and draws in the league** (`long_sim_test`) are
  gated at goals 2.5..3.0, home wins 43..47 % and draws 22..30 %: spec
  §9's 2.5..2.9 / 43..47 / 24..28 are single-match, equal-strength
  targets (`calibration_test` holds them); a league with the generator's
  strength spread and fatigue scores a little more and draws less (see
  "Calibration"). Seed 11, 5 seasons, Task 13 constants: goals/match
  2.67, 2.63, 2.66, 2.63, 2.61; home/draw/away ≈ 44/24/32 % (home
  43.2..44.4, draws 23.1..24.2); yellows ≈ 3.0 and reds ≈ 0.21 per match
  (second yellows included); injuries 6.5..6.9 per club-season;
  suspensions ≈ 1 600 a season.
- **Population gates are post-transient.** The generated world is not at
  steady state (senior squads 22..26 against the cap of 28, youth cohorts
  fill over three seasons), so the player count at the end of season 5 is
  compared with the end of season 2, and the age buckets with the end of
  season 3: the generated 18..34 cohort keeps aging into 31+ until then
  (11 % → 21 %, which is the spec's steady-state value), and that is cohort
  aging, not drift. The youth-squad bound is 21 at every season end: the
  steady state is 18 (three intake cohorts of up to 6) and the 21 at season
  3 is the generated 15..17 cohort meeting the first full intake cohort.
  Outflow comes from retirement at 35 and the release of youth who are
  still unpromoted at 19 (`YouthReleased`, players deleted; Faz 3 turns
  this into free agency). The spec's 30-season ±10 % gate arrives in Faz 4.
- **Goalkeepers ≥ 2 per senior squad** at every season end. Youth
  promotion is position-aware: goalkeeper youth are promoted first while
  the squad has fewer than two, the id-order promotion leaves room for the
  goalkeepers still missing, and the rollover's fillers add goalkeepers up
  to two even when the squad is above the 18 floor (never above the 28
  cap). Without this the position-blind rule starved squads once every
  club sat at the cap: on seed 11 the fewest goalkeepers at any club were
  2, 2, 1, 1, 0 over seasons 1–5.

## Known Faz 0 limitations

### Data growth

Old-season fixtures are kept in `world.fixtures` until Faz 4 archiving.
Measured on the large world under the Poisson placeholder: the gzip save
grew by about 0.53 MB per season (uncompressed JSON about 5 MB per
season) and `save()` took about 100 ms longer per season on desktop. With
the possession engine every result carries its events, statistics and
ratings: after 400 days the save is 7.5 MB (was 1.97 MB), so the
per-season growth is roughly 5 MB until Faz 4 archives old seasons. The daily cost is flat: the day loop
and `computeTable` read the per-season indexes (`fixturesOn`,
`fixturesOfClub`, `fixturesOfLeagueSeason`), never the whole fixture map.

### Quality decay (no development model)

Faz 0 has no player development: youth arrive at CA ≈ `reputation × 0.6
+ 20` (about 60) and never improve, while the generated seniors retire.
On the small world (seed 11) the mean best-XI CA falls from 119 at the
start to 100 at season 10 and 84 at season 12. Player development in Faz
2/4 resolves this. Do not tune the match model against a world that has
decayed past season 5: the strength spread it produces is an artefact
of the missing development, not a calibration target.

### Cross-platform determinism

The JSON produced by `worldToJson` is the determinism oracle, but a
comparison between native and web (dart2js) output must be structural
(decoded values), not byte-wise: dart2js encodes integral doubles such as
`50.0` as `50`. Faz 0B's CI should pin determinism on the browser too,
with `dart test -p chrome test/determinism_test.dart` run alongside the
VM suite.

## Match engine (Faz 1a)

`lib/src/sim/match/`: the possession engine of spec §5. `MatchSession`
plays one `MatchContext` possession step by possession step (team
profiles from the lineups and tactics, chance creation and xG, fouls,
cards, injuries, condition drain, AI substitutions and mentality shifts,
extra time and penalties, player ratings); `PossessionMatchSimulator` runs
a session to the end and is the default `MatchSimulator` of `DayRunner`
and `EngineSession`. The Faz 0 Poisson placeholder is gone.

The day loop (`lib/src/sim/day_loop.dart`) builds every fixture's context
with `DayRunner.contextFor`: the stored lineups (auto-picked on the
club's active tactic, custom formations on the tactic's own slots), the
league's `MatchRules`, conditions from `sampleConditions` on the fork
`conditions:<fixtureId>:<seasonYear>`, both clubs' tactics and the match
stream `match:<fixtureId>:<seasonYear>`. After each match
`DayRunner.settleMatch` serves a match of every ban of a player left out
of the squad, then `applyPostMatch` (`lib/src/sim/discipline.dart`)
credits appearances, goals, assists, cards, `ratingSum`, form (an EMA of
the ratings, weight 0.2) and sharpness (+5 per appearance), accumulates
yellows against the league's thresholds (the i-th threshold bans `i + 1`
matches), bans sent-off players (`redBanSecondYellow`, `redBanFoul`,
`redBanViolent`), stores injuries (days ×1.15 over age 30) and writes
the final condition of every squad member back from
`MatchResult.finalCondition`. `startOfDay` runs `dailyRecovery` after the
condition recovery: injuries count down and heal with sharpness 40,
everyone else gains 1 sharpness per day. The season rollover resets the
yellow-card totals with the season statistics; bans carry over.

### Interactive session API

The user's match is played step by step through the session pair; with
the AI left on (`userManaged: false`) and no commands the pair is
identical to `advanceDay` (world JSON equal).

- `MatchSession EngineSession.startUserMatch({List<Command> commands,
  MatchDetail detail = MatchDetail.events, bool userManaged = true})` —
  runs `startOfDay` with [commands] (recovery, injury countdown, lineups)
  and returns the session of the user club's fixture, built with the same
  `contextFor` as the day loop; with [userManaged] the user's side gets no
  AI decisions. Throws `StateError` unless today is `nextUserMatchDate()`
  and no user match is in progress.
- `DaySummary EngineSession.finishUserMatch()` — `finish()`es the session,
  settles its fixture, plays the day's other fixtures and ends the day as
  `advanceDay` would. Throws `StateError` when no user match is in
  progress.
- `bool EngineSession.userMatchInProgress` — true between the two calls.
  `advanceDay`, `advanceUntil` and `save()` throw `StateError` while it is
  true: the world is saved only between days, so hosts guard their
  autosave with it.
- `MatchDetail { result, events, full }` — how much of the match is kept:
  the `MatchResult` with its events and statistics, or (`full`) also every
  `PossessionStep` with its `MicroEvent`s in `MatchSession.log`. The
  result is identical in all three (the micro events draw only from the
  `visual` fork).
- `List<PossessionStep> MatchSession.step({int count = 1})` — up to
  [count] steps, fewer when the match ends; nothing on a finished match.
- `List<PossessionStep> MatchSession.runUntil({int? minute, bool
  stopOnEvent = true})` — steps until the end, until the clock reaches
  [minute], or right after a step that produced a `Goal`, `Booking`,
  `Injury`, `PenaltyMissed`, `HalfTime`, `FullTime`, `ExtraTimeStart` or
  `ShootoutStart`.
- `void MatchSession.apply(MatchCommand c)` — `Substitute`, `SetMentality`
  or `SetTactic` between steps; validated, throws `CommandError` and
  leaves the state untouched on error; `StateError` once finished.
- `void MatchSession.setUserManaged(ClubId side, bool managed)` — the AI
  makes no decisions for a managed side from the next step on.
- `MatchResult MatchSession.finish()` — runs the rest without stopping,
  finalises the ratings and returns the result (the same object on later
  calls). `finished`, `minute` and `state` are readable throughout.

## CLI

`dart run bin/cm.dart simulate --seed 1 --size small --seasons 1
[--invariants] [--report r.json]` prints one JSON object per season:
`champions`, `matches`, `goals`, `goalsPerMatch`, `homeWinPct`,
`drawPct`, `awayWinPct`, `yellows`, `reds` (second yellows included),
`injuries`, `substitutions`, `violations`, `days`, `msTotal`. `generate`,
`bench` and `inspect` are described by `cm help`.

`cm calibrate --seed 1 --matches 20000 [--gap 10|20|40] [--season]
[--seasons 100] [--report c.json]` runs the calibration harness
(`lib/src/calibration/`): two synthetic clubs of uniform attributes
(CA = attribute × 10, condition 100, balanced 4-4-2 presets, a 7-man
bench) under league rules and neutral conditions, match `i` on
`SeededRng(seed).fork('calib:$i')`, and prints the spec §9 table (goals,
home/draw/away, shots and on-target per side, xG, possession, corners,
fouls, yellows, reds, injuries, substitutions, added time, the twelve
most common scores and the 5+ goals share). `--gap` plays half the
matches with the home side that many CA stronger and half with the away
side stronger and averages the stronger side's win/draw/loss; `--season`
plays `--seasons` double round robins of 20 synthetic clubs whose
strengths are drawn with sd 13 CA around 120 (every match at condition
100: no fatigue, injuries or bans carried) and reports champion / last /
median points, how often the strongest three finish top four and the
strongest one wins, and the top scorer. The same seed gives byte-identical
output.

## Calibration

Task 12 tuned `lib/src/sim/match/tuning.dart` against spec §9 and §5.6
on the harness above (`cm calibrate --seed 1`). The structural finding:
every strength effect in the §5.3 formulas is a logistic in an attribute
difference, so odds grow exponentially with the CA gap, while the §5.6
table is concave (+10 → 55 %, +40 → 78 %). The shape was obtained by
making the midfield contest decide only `1 − midBypass` of the
possessions (a coin flip decides the rest) with a steep `possessionK1`,
and a flatter `chanceK2`; counters as a floor for the weaker side were
tried and rejected (they dilute the small gaps as much as the large
one).

Task 13 (rows 10–15) reshaped step 1 after the Task 12 review: the
contested share of possessions is now the style-independent
`midContestShare` (0.45) less the spec's small style bypass (0.0–0.3),
`possessionK1` dropped from 1.4 to 1.0 so the contest no longer
saturates (a one-point mid edge is +9 pp of open-play possession, four
points +20 pp; before, +8 and +10), and the home advantage is an additive
log-odds term in the contest (`homeLogOdds` 0.7 at the neutral 1.055,
scaled by `(homeAdvantage − 1) / 0.055`) instead of ×1.055 on the mid, so
the home edge is the same size at every strength gap. A booked player
draws a further yellow at `yellowPerFoul × bookedYellowMul` (0.5), which
let `redPerFoul` return to 0.007 (spec 0.008): straight reds are 43 % of
the sendings-off instead of 5 %.

Iterations (equal CA-120 sides; H/D/A in %, gaps = stronger side's
win %; 2 000–4 000 matches per probe, 10 000 for rows 9, 14 and 15):

| # | Change | Goals | H/D/A | Shots h/a | Yel | Red | Inj | 5+ | +10 / +20 / +40 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | spec constants | 4.19 | 48/19/33 | 14.0/11.7 | 1.16 | 0.10 | 0.29 | 41.6 | — |
| 1 | xgBase ×0.68, chanceBase ln(.18/.82), foulPerStep .12, yellowPerFoul .27, redPerFoul .002 | 2.71 | 43/25/32 | 13.1/11.0 | 2.97 | 0.23 | 0.30 | 14.6 | 51 / 67 / 88 |
| 2 | + chanceK2 .26, counterProb .25 | 2.93 | 44/24/32 | 14.1/11.8 | 2.95 | 0.23 | 0.30 | 17.8 | 55 / 70 / 91 |
| 3 | counterProb .35 (k2 .2) | 3.00 | 43/25/32 | 14.6/12.2 | 2.94 | 0.23 | 0.30 | 18.5 | 53 / 68 / 92 |
| 4 | possessionK1 .8, chanceK2 .15, midBypass .4–.7 | 2.58 | 45/24/31 | 12.8/10.3 | 2.96 | 0.22 | 0.31 | 12.2 | 53 / 65 / 83 |
| 5 | + counterProb .3, counterDefMul .7 (floor) | 2.81 | 43/26/31 | 13.6/11.4 | 2.97 | 0.21 | 0.29 | 15.1 | 50 / 61 / 80 |
| 6 | possessionK1 1.2, midBypass .5–.8; row 5's counter floor reverted (counterProb .15, counterDefMul .80) | 2.59 | 46/24/30 | 13.0/10.1 | 2.95 | 0.22 | 0.30 | 12.2 | 53 / 64 / 82 |
| 7 | possessionK1 1.4, chanceK2 .13 | 2.59 | 45/24/30 | 13.1/9.9 | 2.96 | 0.23 | 0.30 | 12.7 | 53 / 65 / 81 |
| 8 | chanceK2 .14, chanceBase ln(.187/.813), xgBase ×0.95, yellowPerFoul .285 | 2.58 | 46/25/29 | 13.7/10.3 | 3.10 | 0.26 | 0.30 | 12.1 | 53 / 65 / 82 |
| 9 | xgBase ×0.99, yellowPerFoul .28, redPerFoul .001, shooterForwardMul 4/3/3 (Task 12 final) | 2.56 | 45.9/25.2/28.9 | 13.7/10.3 | 3.05 | 0.24 | 0.30 | 11.6 | 52.9 / 65.0 / 81.2 |
| 10 | midContestShare .5 with the spec midBypass (0–.3), possessionK1 .5, homeLogOdds .35 (mid no longer ×homeAdvantage), bookedYellowMul .5, redPerFoul .007 | 2.53 | 43.0/25.6/31.4 | 13.0/10.9 | 3.06 | 0.19 | 0.30 | 11.6 | 47.7 / 59.6 / 78.9 |
| 11 | possessionK1 .7, midContestShare .45, homeLogOdds .45, chanceK2 .16 | 2.56 | 43.7/25.9/30.4 | 13.3/10.9 | 3.07 | 0.19 | 0.30 | 12.0 | 49.6 / 62.3 / 82.3 |
| 12 | possessionK1 1.0, chanceK2 .14 | 2.53 | 43.6/25.6/30.8 | 13.1/10.8 | 3.07 | 0.19 | 0.30 | 11.5 | 51.1 / 63.8 / 81.0 |
| 13 | homeLogOdds .6, xgBase ×1.03 | 2.62 | 44.7/25.0/30.3 | 13.3/10.6 | 3.07 | 0.19 | 0.30 | 12.7 | 51.2 / 64.0 / 81.7 |
| 14 | xgBase ×1.015 instead | 2.59 | 44.0/25.2/30.8 | 13.3/10.7 | 3.05 | 0.20 | 0.30 | 12.2 | 51.1 / 63.9 / 81.5 |
| 15 | homeLogOdds .7 (final) | 2.59 | 44.9/25.1/30.1 | 13.5/10.5 | 3.05 | 0.20 | 0.30 | 12.2 | 50.9 / 63.8 / 81.4 |

Final `cm calibrate --seed 1 --matches 10000`: goals 2.59; home/draw/away
44.9 / 25.1 / 30.1 %; shots 13.46 / 10.51; on target 4.82 / 3.72; xG
1.43 / 1.12; possession 55.1 % home; corners 1.78; fouls 11.72; yellows
3.05; reds 0.20 (second yellows 0.11, straight 0.09 — 43 % of the
sendings-off); injuries 0.30; substitutions 0.30; added time 3.4 per
half; 5+ goals 12.2 %; scores 1-1 11.8, 1-0 11.0, 2-1 8.8, 0-1 8.7, 2-0
7.9, 0-0 7.6, 1-2 7.3 %. Gap curve (4 000 matches each): +10 → 50.9 /
23.9 / 25.2, +20 → 63.8 / 21.3 / 14.9, +40 → 81.4 / 12.5 / 6.1 (spec 55 /
24 / 21, 65 / 20 / 15, 78 / 14 / 8, ±5); the stronger side's possession
averaged over home and away is 56.3 / 61.0 / 64.9 %. Season check (100
seasons): champion 86.0 points (74..102), last 19.7 (6..33), median 52.3,
strongest three in the top four in 81 % of their club-seasons (all three
at once in 49 seasons), strongest one champion in 59 seasons, top scorer
20.9.

Bands that the tuning could not centre, and why:

- **1-0 and 5+ goals.** With 2.56 goals per match and the home split the
  goal counts are close to Poisson, which already puts 1-0 at 11.0 % and
  5+ at 11.6 %; the set-piece clustering adds ~0.5 to each. The spec's
  1-0 ≤ 11 and 5+ ≤ 12 only hold together below 2.5 goals, so the test
  gates them at 12.5 and 13 %.
- **Strongest three in the top four.** Gated per club (≥ 80 % of
  club-seasons) rather than per season: with sd 13 the third and fourth
  strongest clubs are 2..5 CA apart, worth 1..3 points over 38 matches
  against a points noise of ~8.
- **The +10 row of the gap curve** sits at 50.9 % (spec 55, gate ≥ 50)
  while +40 is 81.4 % (spec 78, gate ≤ 83): the chance logistic is
  exponential in the gap and the contest is bounded, and the two meet the
  spec's concave curve only inside the tolerance. A steeper
  `possessionK1` lifts +10 but drifts back toward the saturated contest
  the Task 12 review rejected; a steeper `chanceK2` lifts +40 faster than
  +10. Rows 10–12 are that trade-off.
- **Resolved in Task 13:** straight reds (5 % of sendings-off → 43 %,
  `bookedYellowMul`), possession in an equal home match (56 / 44 → 55 /
  45, `homeLogOdds`) and the league's home advantage (42.4..44.7 % →
  43.2..44.4 % home wins; `long_sim_test` is back on the spec's 43..47).

### Tuning constants that differ from the spec

`lib/src/sim/match/tuning.dart` after Tasks 12–13; everything not listed
is at the spec's value.

| Constant | Spec | Final | Why |
| --- | --- | --- | --- |
| `possessionK1` | 0.25 on every possession | 1.0 on the contested share | With the coin-flip share capping what the contest decides, 0.5–0.7 left the +10 CA row of the 5.6 curve under 50 % (rows 10–12). |
| `midContestShare` | — (new) | 0.45 | The share of possessions the midfield decides; bounds a +40 CA side's possession at ~65 % and is what makes the gap curve concave. |
| `midBypass` | 0.0 / 0.1 / 0.2 / 0.3 | unchanged (Task 12's 0.5–0.8 reverted) | The style bypass is back to the spec now that `midContestShare` carries the floor. |
| `homeLogOdds` | ×1.06 on home att and mid (5.2) | 0.7 added to the contest logit at `homeAdvantage` 1.055 (att keeps ×homeAdvantage) | A multiplier on the mid was saturated away by the strength gap; additive log-odds keep the home edge constant across gaps (league home wins 42.4..44.7 → 43.2..44.4 %). |
| `chanceK2` | 0.20 | 0.14 | A +40 CA side won 88 % at 0.20. |
| `chanceBase` | ln(0.20 / 0.80) | ln(0.187 / 0.813) | Shots 10–14 per side with set pieces and counters on top. |
| `xgBase` (all but penalty) | 0.30 / 0.12 / 0.05 / 0.20 / 0.08 / 0.07 | ×0.64 (0.191 / 0.076 / 0.0325 / 0.129 / 0.0508 / 0.0457) | The spec's bases gave 4.2 goals a match; 2.5–2.9 needs ≈ 0.10 xG per shot. |
| `foulPerStep` | 0.10 | 0.12 | 11.7 fouls a match (penalties 0.25, free kicks). |
| `yellowPerFoul` | 0.12 | 0.28 | 3.05 first yellows a match (spec 3–4). |
| `bookedYellowMul` | — (new) | 0.5 | A booked player draws yellows at half rate, so 3 yellows a match give 0.11 second yellows instead of 0.23. |
| `redPerFoul` | 0.008 | 0.007 | Straight reds 0.085 a match, 43 % of the sendings-off; total 0.20. |
| `shooterForwardMul` | 3 / 2 / 2 | 4 / 3 / 3 | A top club's striker reaches the spec's 20+ goals a season. |

## Generator values that differ from the plan

Tuned during implementation; the tests in `test/gen` pin them.

- Weekly wage: `round(ca² × 0.9 / 1000) × 10` (the plan's prose said
  `/ 100`, but its examples ca 100 → 90, 150 → 200, 180 → 290 only hold
  with `/ 1000`).
- Attribute noise: position-relevant attributes are `ca/10 + g(0, 1.2)`,
  symmetric, instead of the planned upward-biased `g(0, 2)`; the biased
  form shifted CA by about +4 and broke the `ca == computeCa(attrs)`
  calibration. Irrelevant attributes stay at `ca/10 − 4 + g(0, 2)`.

## Saves

`JsonGzipSaveCodec` writes `gzip(utf8(jsonEncode({"schemaVersion": 3,
"world": worldToJson(world)})))` at gzip level 6. The JSON is byte-stable
and is the determinism oracle; the gzip bytes may differ between platforms
(native zlib vs. pure Dart). `decode` runs the `migrations` registry up to
`currentSchemaVersion` (3, defined in `model/world.dart`) and throws
`SaveError` (`corrupt`, `newerSchema`) otherwise.

Schema history:

- v1 (Faz 0A): initial shape.
- v2 (Faz 0B): every inbox message carries an `id` (`ids.next('inbox')`,
  JSON `{"id", "date", "event", "read"}`) so hosts can refer to a message
  across an isolate boundary (`EngineSession.markReadById`). Migration
  1 -> 2 numbers the stored messages `1..n` in order and sets `ids.inbox`
  to `n`.
- v3 (Faz 1a, unshipped: tactics + rules + result extensions land in the
  same step): every club carries `tactics` (exactly three `Tactic`
  objects, keys in field order; `instructions`/`arrows` keyed by decimal
  player id ascending) and `activeTactic` (0..2) in place of `formation`
  (`Club.formation` stays as a getter over the active tactic).
  `Formation.custom` tactics carry their own 11 `slots`. Migration 2 -> 3
  gives each club `'1'` = balanced preset on its old formation, `'2'`
  4-3-3, `'3'` 5-3-2 and `activeTactic: 0`, then drops the `formation`
  key.

`FileSaveStore` keeps one directory per slot (spec §18.3, Faz 0 subset):

```
<root>/slot_<n>/world.bin    the codec's bytes, written via temp file + rename
<root>/slot_<n>/meta.json    SlotInfo: manager, club, date, seasonYear, savedAt, bytes
```

`savedAt` is wall-clock metadata and never enters the world.
