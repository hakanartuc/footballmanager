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
| `test/slow/long_sim_test.dart` | small, seed 11, 5 seasons, `advanceDay` loop | `checkInvariants()` after every day: zero violations (this covers senior squads 18..28 daily). Per season: goals/match in 2.5..3.0, home wins 43..47 %, every archived champion equals both the first row of the archived `finalOrder` and the table computed on the morning of `seasonEnd`; youth squad per club ≤ 20 at every season end. Season 5 against season 2: total player count within ±10 %; age buckets 16–20 / 21–25 / 26–30 / 31+ within ±8 points. |
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
  fill over three seasons), so the player count and the age buckets are
  compared between the end of season 2 (baseline) and the end of season 5;
  the youth-squad cap of 20 holds at every season end. Outflow comes from
  retirement at 35 and the release of youth who are still unpromoted at 19
  (`YouthReleased`, players deleted; Faz 3 turns this into free agency).
  The spec's 30-season ±10 % gate arrives in Faz 4.

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

`JsonGzipSaveCodec` writes `gzip(utf8(jsonEncode({"schemaVersion": 1,
"world": worldToJson(world)})))` at gzip level 6. The JSON is byte-stable
and is the determinism oracle; the gzip bytes may differ between platforms
(native zlib vs. pure Dart). `decode` runs the `migrations` registry up to
`currentSchemaVersion` (1) and throws `SaveError` (`corrupt`,
`newerSchema`) otherwise.

`FileSaveStore` keeps one directory per slot (spec §18.3, Faz 0 subset):

```
<root>/slot_<n>/world.bin    the codec's bytes, written via temp file + rename
<root>/slot_<n>/meta.json    SlotInfo: manager, club, date, seasonYear, savedAt, bytes
```

`savedAt` is wall-clock metadata and never enters the world.
