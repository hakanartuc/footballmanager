# engine

Pure-Dart football-manager simulation engine (Faz 0A). Hosts (the Flutter
app, the CLI in `bin/cm.dart`) talk to it only through `EngineSession`.

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
| `test/slow/poisson_stats_test.dart` | 20k matches per case | Equal sides: goals 2.5..2.9, home 43..47 %, draw 24..28 %, away 27..31 %; +40 strength gap: stronger side wins 74..82 %. |

Measured on an Apple Silicon Mac (JIT, `dart test`): large world generates
in ~120 ms; match day p50 2.3 ms / p95 3 ms, other day p50 0.9 ms / p95
1.1 ms; save 1.97 MB in ~0.4 s, load ~0.3 s. Small world, 5 seasons with
daily invariant checks: ~6 s.

### Band notes

- **Goals per match 2.5..3.0.** Spec §9's 2.5..2.9 is a single-match,
  equal-strength target and is enforced as such in `poisson_stats_test`.
  A league season mixes sides of different strength and the Poisson
  placeholder's `exp(slope × d)` is convex, so with the generator's
  within-league strength spread (sd ≈ 13 strength points, stable across
  seasons) a season's expectation is ≈ 2.87 with σ ≈ 0.03 for ~3000
  matches; seed 11 gave 2.83, 2.93, 2.90, 2.88, 2.88. The 3.0 ceiling is a
  Faz 0 placeholder bound; the Faz 1a engine gets its own calibration.
- **Home wins 43..47 %** is a ±2σ band around 45 % for ~3000 matches
  (σ ≈ 0.9 points); seed 11 gave 45.8, 44.6, 45.1, 45.8, 46.1.
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
Measured on the large world: the gzip save grows by about 0.53 MB per
season (uncompressed JSON about 5 MB per season) and `save()` takes about
100 ms longer per season on desktop. The daily cost is flat: the day loop
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

## Match model (Faz 0 placeholder)

`lib/src/sim/poisson_match.dart`: independent Poisson goal counts with

```
d        = (strength_home − strength_away) / 20
λ_home   = baseHome × exp(strengthSlope × d) × homeAdvantage
λ_away   = baseAway × exp(−strengthSlope × d)
baseHome 1.45   baseAway 1.20   homeAdvantage 1.06   strengthSlope 0.33
```

`strengthSlope` was planned as 0.55; that made a +40 gap win 94 %, so it
was lowered to 0.33 (78 % measured). Scorers are drawn by `positionWeight`
times finishing.

## Generator values that differ from the plan

Tuned during implementation; the tests in `test/gen` pin them.

- Weekly wage: `round(ca² × 0.9 / 1000) × 10` (the plan's prose said
  `/ 100`, but its examples ca 100 → 90, 150 → 200, 180 → 290 only hold
  with `/ 1000`).
- Attribute noise: position-relevant attributes are `ca/10 + g(0, 1.2)`,
  symmetric, instead of the planned upward-biased `g(0, 2)`; the biased
  form shifted CA by about +4 and broke the `ca == computeCa(attrs)`
  calibration. Irrelevant attributes stay at `ca/10 − 4 + g(0, 2)`.
- `strengthSlope` 0.33 (above).

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
