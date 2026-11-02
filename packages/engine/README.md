# engine

Pure-Dart football-manager simulation engine (Faz 0A + Faz 1a match
engine). Hosts (the Flutter app, the CLI in `bin/cm.dart`) talk to it only
through `EngineSession`.

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

Measured on an Apple Silicon Mac (JIT, `dart test`) with the possession
engine: large world generates in ~125 ms; match day p50 191 ms / p95 215
ms (up to ~250 matches a day), other day p50 1.8 ms / p95 2.4 ms; save
7.5 MB in ~1.2 s, load ~0.9 s (results now carry events, statistics and
ratings). Small world, 5 seasons with daily invariant checks: ~19 s.

### Band notes

- **Goals per match and home wins** are measured on the uncalibrated
  possession engine until Task 12 (calibration) restores the spec bands
  (goals 2.5..3.0, home wins 43..47 %; the gates carry `TODO(T12)`
  markers). Seed 11, 5 seasons, uncalibrated: goals/match 3.88, 3.72,
  3.77, 3.85, 3.71; home/draw/away ≈ 47/17/36 %; yellows ≈ 1.1 and reds
  ≈ 0.11 per match; injuries 6.4..6.9 per club-season; bans issued
  441, 374, 427, 410, 428 (yellow totals reset at the rollover). Gates until
  Task 12: goals 2.5..4.0, home wins 43..49 %.
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

The user's match can be played interactively through
`EngineSession.startUserMatch` / `finishUserMatch`: the first starts the
day and returns the `MatchSession` of the user's fixture (built with the
same `contextFor`), the second takes its result and plays the rest of
the day. With the AI left on (`userManaged: false`) and no commands the
pair is identical to `advanceDay` (world JSON equal). `save()` during a
match throws `StateError` (the world is saved only between days; hosts
guard their autosave with `userMatchInProgress`).

## CLI

`dart run bin/cm.dart simulate --seed 1 --size small --seasons 1
[--invariants] [--report r.json]` prints one JSON object per season:
`champions`, `matches`, `goals`, `goalsPerMatch`, `homeWinPct`,
`drawPct`, `awayWinPct`, `yellows`, `reds` (second yellows included),
`injuries`, `substitutions`, `violations`, `days`, `msTotal`. `generate`,
`bench` and `inspect` are described by `cm help`.

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
