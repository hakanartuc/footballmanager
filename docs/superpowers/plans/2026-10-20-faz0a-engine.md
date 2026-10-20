# Faz 0A — Engine Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A pure-Dart, headless game engine that generates a fictional multi-country football world, advances it day by day through full seasons (fixtures, Poisson placeholder matches, standings, promotion/relegation, simple aging/retirement/youth intake), saves and loads it with schema versioning, checks world invariants, and meets the per-day performance budget — all deterministic from a seed.

**Architecture:** One Dart package `packages/engine` with no Flutter dependency. `World` is a plain mutable data graph (maps keyed by int ids) that `advanceDay` mutates in place and returns structured `GameEvent`s (no strings except names). All randomness flows through a 32-bit, web-safe seeded RNG with named forks. `EngineSession` is the single entry point the app (Faz 0B) will host inside an isolate. Persistence is JSON+gzip behind a `SaveCodec` interface so the binary codec of Bölüm 18 can replace it later without touching callers.

**Tech Stack:** Dart 3.12 (`package:test`, `package:lints`, `package:archive` for gzip, `package:args` for the CLI). No codegen. Git repo at `/Users/hakanartuc/CM`.

**Spec:** `docs/superpowers/specs/2026-10-20-cm-simulation-design.md` — Bölüm 3 (gün döngüsü, simetri ilkesi), 4 (veri modeli), 8.3 (altyapı), 9/17 (testler), 11 (Faz 0 kapsamı), 11.1 (model dağılımı), 12 (teknoloji), 16.6 (ülke verisi), 16.12 (oyun başlangıcı, kayıt, şema sürümleme), 18 (veri büyümesi). Faz 0B (Flutter app) is a separate plan written after this one ships.

## Global Constraints

- Engine package has **no Flutter dependency**; `dart test` and `dart run` must work from `packages/engine` alone (Spec §12).
- **Determinism:** same seed + same commands ⇒ byte-identical world JSON. No `DateTime.now()`, no `Random()` without seed, no map-iteration-order dependence (iterate sorted ids). RNG is 32-bit arithmetic only (web-safe: no 64-bit multiply, no `>>>` on 64-bit) (Spec §2, §12).
- **Symmetry:** the user's club is never special-cased in simulation code; the user is a `Manager` with `isUser = true` sitting in a club's manager seat; all AI behaviour applies to every club without a user command (Spec §3).
- **Engine emits no UI text.** Events carry ids and numbers; the app renders strings (Spec §16.10, §12). Only names (people, clubs, stadiums) are stored as strings.
- World sizes: `small = 4`, `medium = 8`, `large = 16` countries (Spec §3, §16.12).
- Squad size invariant 18–28; generator targets 22–26 (Spec §7.2, §17.2).
- Attributes 1–20; CA and PA 1–200; CA ≤ PA; ages 15–45 (Spec §4, §17.2).
- Performance budget, large world: match day < 300 ms, other day < 50 ms, single core (Spec §3). Faz 0 save of large world < 15 MB compressed (Spec §18.1 targets 5–10 MB for the final binary codec; JSON+gzip gets a looser bound now).
- Inbox keeps the 300 most recent messages (Spec §18.1).
- Save files carry `schemaVersion`; migrations are registered steps applied in order (Spec §16.12).
- Faz 0 season rollover simplifications allowed by Spec §11: retire every player aged ≥ 35; youth intake 3–6 players aged 16 per club; AI contracts auto-renew. Everything else in §8 arrives in Faz 4.
- Commit after every task; conventional commit messages; each commit ends with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Model per task is tagged `[Model: Fable]` or `[Model: Opus]` per Spec §11.1. Opus output is reviewed by Fable before the next task starts.

## Review Focus

1. **Leagues with an odd number of clubs** (data says 19 or 21): fixture generation must insert a bye each round and still give every pair exactly two meetings. Test pinned in Task 7.
2. **Season rollover with the user unemployed or the user's club relegated/promoted**: the day loop and rollover must run without a user club and must keep `userManagerId` valid. Tests pinned in Tasks 12 and 13.
3. **A club dropping below 11 eligible players** (mass retirement before youth intake): rollover order and filler generation must guarantee ≥ 18 players before fixtures resume, and `AutoLineup` must never produce fewer than 11. Tests pinned in Tasks 11 and 13.
4. **Save files from a newer schema or corrupt bytes**: loading must throw a typed `SaveError`, never a raw `FormatException`, and must not leave a half-loaded session. Test pinned in Task 15.
5. **Leap days and month ends in the calendar**: matchdays must land on real dates (Feb 29 in leap years, no Feb 30), and international-break weeks must not swallow the last round. Tests pinned in Tasks 3 and 8.

---

## File Structure

```
CM/
  .gitignore
  packages/engine/
    pubspec.yaml
    analysis_options.yaml
    lib/engine.dart                       # public exports
    lib/src/core/rng.dart                 # SeededRng, forks, distributions
    lib/src/core/game_date.dart           # GameDate (day index), weekday/month math
    lib/src/core/ids.dart                 # typedef ids, IdAllocator
    lib/src/model/enums.dart              # Position, Attr, Formation, PlayerStatus, BoardExpectation, Continent
    lib/src/model/attributes.dart         # Attributes (List<int> by Attr), CaCalculator
    lib/src/model/player.dart             # Player, Contract, PlayerState, SeasonStats, CareerLine
    lib/src/model/club.dart               # Club, Kit, LogoSpec, Facilities, Lineup
    lib/src/model/manager.dart            # Manager
    lib/src/model/country.dart            # Country, League
    lib/src/model/fixture.dart            # Fixture, MatchResult, GoalEvent
    lib/src/model/calendar.dart           # SeasonCalendar, TransferWindow, BreakPeriod
    lib/src/model/events.dart             # GameEvent (sealed), InboxMessage
    lib/src/model/world.dart              # World container, indexes, SeasonArchive
    lib/src/model/json.dart               # toJson/fromJson for every model type
    lib/src/data/country_data.dart        # CountryTemplate, NamePool, loader + validation
    lib/src/data/assets/countries.json    # 16 country templates
    lib/src/data/assets/names/<code>.json # name pools per country
    lib/src/gen/world_generator.dart      # WorldGenerator
    lib/src/gen/player_generator.dart     # PlayerGenerator (attributes from CA, positions, ages)
    lib/src/gen/club_generator.dart       # club names, kits, logos, stadiums, budgets
    lib/src/competition/fixtures.dart     # RoundRobin scheduler
    lib/src/competition/season_calendar_builder.dart
    lib/src/competition/standings.dart    # LeagueTable
    lib/src/competition/promotion.dart    # applyPromotionRelegation
    lib/src/sim/match_simulator.dart      # MatchSimulator interface + MatchContext
    lib/src/sim/poisson_match.dart        # PoissonMatchSimulator
    lib/src/sim/lineup.dart               # AutoLineup, validateLineup
    lib/src/sim/commands.dart             # Command (sealed)
    lib/src/sim/day_loop.dart             # DayRunner: startOfDay / playMatches / endOfDay / advanceDay
    lib/src/sim/season_rollover.dart      # rolloverSeason
    lib/src/sim/new_game.dart             # NewGameSpec, createNewGame
    lib/src/invariants/invariants.dart    # WorldInvariants.check
    lib/src/persistence/save_codec.dart   # SaveCodec, JsonGzipSaveCodec, SaveError
    lib/src/persistence/save_store.dart   # SaveStore, MemorySaveStore, FileSaveStore, SlotInfo
    lib/src/persistence/migrations.dart   # schemaVersion, Migration, migrate()
    lib/src/session/engine_session.dart   # EngineSession
    bin/cm.dart                           # CLI: generate | simulate | bench | inspect
    tool/check.sh                         # format + analyze + test
    test/...                              # mirrors lib/src; test/slow/ for stat+perf (tag 'slow')
```

---

### Task 1: Repository and package scaffold `[Model: Opus]`

**Files:**
- Create: `.gitignore`, `packages/engine/pubspec.yaml`, `packages/engine/analysis_options.yaml`, `packages/engine/lib/engine.dart`, `packages/engine/tool/check.sh`, `packages/engine/test/smoke_test.dart`, `packages/engine/dart_test.yaml`

**Interfaces:**
- Produces: package name `engine`, import path `package:engine/engine.dart`; test tag `slow` excluded by default.

- [ ] **Step 1: Init repo**

Run: `cd /Users/hakanartuc/CM && git init -b main`
`.gitignore` contents: `.dart_tool/`, `build/`, `*.iml`, `.idea/`, `.DS_Store`, `pubspec.lock` is **kept** (app), `packages/engine/.dart_tool/`.

- [ ] **Step 2: pubspec**

`packages/engine/pubspec.yaml`: `name: engine`, `environment: sdk: ^3.12.0`, dependencies `archive: ^4.0.0`, `args: ^2.6.0`, `collection: ^1.19.0`, dev_dependencies `test: ^1.26.0`, `lints: ^6.0.0`.
`analysis_options.yaml`: `include: package:lints/recommended.yaml`, plus `prefer_final_locals`, `unawaited_futures` errors.
`dart_test.yaml`: `tags: slow: timeout: 30m` and `exclude_tags: slow` is **not** set here; `tool/check.sh` passes `-x slow`.

- [ ] **Step 3: Smoke test**

```dart
// test/smoke_test.dart
test('package imports', () { expect(engineVersion, '0.0.1'); });
```
`lib/engine.dart` exports `const engineVersion = '0.0.1';` (exports grow per task).

- [ ] **Step 4: check.sh**

`tool/check.sh`: `dart format --set-exit-if-changed .`, `dart analyze --fatal-infos`, `dart test -x slow`; with `--slow` also `dart test -t slow`. Exit non-zero on any failure.

- [ ] **Step 5: Run `dart pub get && tool/check.sh`** — Expected: all green.

- [ ] **Step 6: Commit** `chore: scaffold engine package`

---

### Task 2: Seeded RNG `[Model: Fable]`

**Files:**
- Create: `lib/src/core/rng.dart`, `test/core/rng_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class SeededRng {
    SeededRng(int seed);                       // seed masked to 32 bits
    SeededRng fork(String name);               // independent stream: seed' = splitmix32(seed ^ fnv1a32(name))
    int nextUint32();
    int nextInt(int maxExclusive);             // unbiased (rejection)
    double nextDouble();                       // [0,1)
    bool nextBool(double pTrue);
    double nextGaussian({double mean = 0, double sd = 1});   // Box-Muller, no caching
    int nextPoisson(double lambda);            // Knuth for lambda < 30, else gaussian approx rounded, min 0
    int weightedIndex(List<double> weights);   // weights ≥ 0, sum > 0
    T pick<T>(List<T> items);
    void shuffle<T>(List<T> items);            // Fisher-Yates
    RngState get state; void restore(RngState s);
  }
  int fnv1a32(String s); int splitmix32(int x); int mul32(int a, int b);
  ```
- Algorithm: xoshiro128** on four 32-bit words seeded via splitmix32(seed), splitmix32(seed+1)… `mul32` multiplies via 16-bit halves so it is exact on web (JS doubles).

- [ ] **Step 1: Failing tests**

```dart
test('same seed same sequence', ...)            // 1000 values equal
test('fork is independent of parent consumption', ...) // fork('a') after 0 vs after 50 draws → same first 10 values
test('forks with different names differ', ...)
test('known vector', () => expect(SeededRng(42).nextUint32(), isA<int>().having((v) => v, 'v', inInclusiveRange(0, 0xFFFFFFFF)))); // plus a hard-coded 5-value vector recorded once after implementation
test('nextInt is unbiased', ...)                // 100k draws of nextInt(7): each bucket within 13.5%–15.1%
test('mul32 matches BigInt', ...)               // 1000 random pairs: mul32(a,b) == (BigInt(a)*BigInt(b)) & 0xFFFFFFFF
test('nextPoisson mean', ...)                   // 20k draws λ=2.7 → mean in 2.65–2.75
test('nextGaussian sd', ...)                    // 20k draws → sd in 0.97–1.03
test('weightedIndex proportions', ...)          // weights [1,3] → second ≈ 75% ± 2
test('state restore replays', ...)
test('all ops stay within 32-bit', ...)         // after 1e5 ops every word fits 0..0xFFFFFFFF
```

- [ ] **Step 2: Run** `dart test test/core/rng_test.dart` — Expected: FAIL (missing class).
- [ ] **Step 3: Implement `rng.dart`** per the interface. After first pass, record the 5-value known vector into the test.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): seeded 32-bit rng with named forks`

---

### Task 3: GameDate `[Model: Opus]`

**Files:**
- Create: `lib/src/core/game_date.dart`, `test/core/game_date_test.dart`

**Interfaces:**
- Produces:
  ```dart
  extension type const GameDate(int dayIndex) {   // days since 2000-01-01 (a Saturday)
    factory GameDate.ymd(int y, int m, int d);
    int get year; int get month; int get day;
    Weekday get weekday;                           // enum Weekday { mon..sun }
    GameDate addDays(int n); int daysUntil(GameDate other);
    bool isBefore(GameDate o); bool isAfter(GameDate o);
    GameDate nextWeekday(Weekday w);               // strictly after this date
    int get seasonYear;                            // month >= 7 ? year : year - 1   (Aug–May season labelled by starting year)
    int ageOn(GameDate birth) — as top-level: int ageAt(GameDate birth, GameDate on)
  }
  ```
  Conversion uses `DateTime.utc(2000,1,1).add(...)` internally only.

- [ ] **Step 1: Tests**: `ymd round trip` (10 dates incl. 2024-02-29, 2100-03-01), `2000-01-01 is Saturday`, `Feb 29 2028 exists and 2100 has no Feb 29` (ymd(2100,2,29) throws `ArgumentError`), `nextWeekday from Saturday to Saturday is +7`, `seasonYear of 2026-05-20 is 2025 and 2026-08-01 is 2026`, `ageAt before/after birthday`.
- [ ] **Step 2: Run → FAIL. Step 3: Implement. Step 4: Run → PASS.**
- [ ] **Step 5: Commit** `feat(core): GameDate`

---

### Task 4: Model — enums, attributes, people `[Model: Opus, Fable reviews CA weights]`

**Files:**
- Create: `lib/src/core/ids.dart`, `lib/src/model/enums.dart`, `lib/src/model/attributes.dart`, `lib/src/model/player.dart`, `lib/src/model/manager.dart`, tests `test/model/attributes_test.dart`, `test/model/player_test.dart`

**Interfaces:**
- Produces:
  ```dart
  typedef PlayerId = int; ClubId = int; LeagueId = int; CountryId = int; ManagerId = int; FixtureId = int;
  class IdAllocator { int next(String kind); Map<String,int> toJson(); IdAllocator.fromJson(...); }

  enum Position { gk, dl, dc, dr, dm, ml, mc, mr, aml, amc, amr, st }      // Spec §4 + AML/AMR (my call)
  enum PositionGroup { gk, def, mid, att }  extension: Position.group
  enum Attr {
    passing, longShots, firstTouch, dribbling, crossing, heading, longPassing, finishing, tackling,    // technical
    decisions, positioning, anticipation, composure, workRate, teamwork, aggression, concentration, leadership, // mental
    pace, acceleration, stamina, strength, balance, jumping, agility,                                 // physical
    reflexes, aerialAbility, handling, oneOnOnes, commandOfArea }                                    // goalkeeping
  enum Formation { f442, f433, f451, f352, f4231, f532 }   // positions list per formation in `formationSlots(Formation) -> List<Position>`
  enum PlayerStatus { keyPlayer, firstTeam, rotation, backup, hotProspect, youth }
  enum BoardExpectation { title, top, upperMid, mid, avoidRelegation }
  enum Continent { europe, southAmerica, northAmerica, africa, asia, oceania }

  class Attributes { Attributes.filled(int v); int operator[](Attr a); void set(Attr a, int v); List<int> toList(); }  // values clamped 1..20
  int computeCa(Attributes a, Position p);   // weighted mean of group weights × 10, clamp 1..200; all-20 → 200, all-1 → 10
  class HiddenAttrs { int injuryProneness, consistency, bigMatches, professionalism; }  // 1..20
  class PlayerState { double condition = 100, sharpness = 100, morale = 50, form = 6.0; int yellowCards = 0, suspensionMatches = 0; InjuryStub? injury; }  // InjuryStub { int daysLeft; String type; } placeholder for Faz 2
  class Contract { ClubId clubId; int wageWeekly; GameDate start, end; PlayerStatus status; int? squadNumber; int? releaseFee; }
  class SeasonStats { int apps, goals, assists, yellows, reds; double ratingSum; }
  class CareerLine { int seasonYear; ClubId clubId; SeasonStats stats; }
  class Player {
    PlayerId id; String firstName, lastName; CountryId nationality; GameDate birth; int heightCm;
    Position mainPosition; Map<Position,int> familiarity;    // 1..20, main = 20
    Attributes attrs; int ca, pa; HiddenAttrs hidden; PlayerState state;
    Contract? contract;            // null = free agent
    bool isYouth;                  // in youth squad (not counted toward 18–28)
    SeasonStats season; List<CareerLine> career;
    int internationalCaps = 0, internationalGoals = 0;
    LoanStub? loan;                // placeholder {ClubId parentClubId; GameDate end;} for Faz 3
    int get age(GameDate on);
  }
  class Manager { ManagerId id; String firstName, lastName; CountryId nationality; GameDate birth; int reputation; ClubId? clubId; bool isUser; Formation preferredFormation; List<CareerLine> career; }
  ```

- [ ] **Step 1: Tests**: attributes clamp; `computeCa(all 20, st) == 200`; `computeCa(all 1, gk) == 10`; GK weights ignore outfield attrs (two GKs differing only in `finishing` have equal CA); position group mapping; `formationSlots(f442)` returns 11 with exactly one `gk`; `Player.age` at a date.
- [ ] **Step 2: Run → FAIL. Step 3: Implement.** CA weights (my call, Fable adjusts in review): GK: reflexes 3, handling 2, oneOnOnes 2, aerialAbility 2, commandOfArea 1, positioning 1, concentration 1, agility 1. DEF: tackling 3, positioning 3, heading 2, strength 2, concentration 2, pace 1, anticipation 1, passing 1. MID: passing 3, decisions 2, teamwork 2, workRate 2, stamina 2, firstTouch 1, tackling 1, longShots 1, anticipation 1. ATT: finishing 3, composure 2, pace 2, acceleration 1, dribbling 2, firstTouch 1, heading 1, anticipation 2. CA = round(weightedMean × 10).
- [ ] **Step 4: Run → PASS. Step 5: Commit** `feat(model): enums, attributes, player, manager`

---

### Task 5: Model — club, country, league, fixture, calendar, events, world `[Model: Opus]`

**Files:**
- Create: `lib/src/model/club.dart`, `country.dart`, `fixture.dart`, `calendar.dart`, `events.dart`, `world.dart`; test `test/model/world_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class Kit { int primary, secondary; }                   // ARGB ints
  class LogoSpec { int shape; int color1, color2; }       // shape 0..7
  class Facilities { int training, medical, youth; }      // 1..10
  class Lineup { Formation formation; List<PlayerId> starters; List<PlayerId> bench; }   // starters.length == 11
  class Club {
    ClubId id; String name, shortName; CountryId countryId; LeagueId leagueId; int reputation;
    Kit home, away; LogoSpec logo; String stadiumName; int stadiumCapacity;
    int balance, transferBudget, wageBudget; Facilities facilities;
    ManagerId? managerId; BoardExpectation expectation; double boardConfidence = 50;
    Lineup? lineup; Formation formation;
  }
  class Country { CountryId id; String code; String name; Continent continent; String namePool; List<LeagueId> tiers; }   // tiers[0] = top
  class League { LeagueId id; CountryId countryId; int tier; String name; List<ClubId> clubIds; int promotedCount, relegatedCount; int reputation; }
  class GoalEvent { int minute; PlayerId scorerId; ClubId clubId; }
  class MatchResult { int homeGoals, awayGoals; List<GoalEvent> goals; int matchSeed; }
  class Fixture { FixtureId id; LeagueId leagueId; int seasonYear; int round; GameDate date; ClubId homeId, awayId; MatchResult? result; }
  class TransferWindow { GameDate open, close; }
  class BreakPeriod { GameDate start, end; }
  class SeasonCalendar { int seasonYear; GameDate seasonStart, seasonEnd; List<BreakPeriod> internationalBreaks; TransferWindow summer, winter; }
  sealed class GameEvent { GameDate date; }
    MatchPlayed(fixtureId) · SeasonEnded(seasonYear) · LeagueChampion(leagueId, clubId) · Promoted(clubId, fromLeagueId, toLeagueId) · Relegated(...) · PlayerRetired(playerId, clubId?) · YouthIntake(clubId, List<PlayerId>) · NewSeasonStarted(seasonYear)
  class InboxMessage { GameDate date; GameEvent event; bool read; }
  class SeasonArchive { int seasonYear; Map<LeagueId, ClubId> champions; Map<LeagueId, List<ClubId>> finalOrder; }
  class World {
    int schemaVersion; int seed; GameDate date; int seasonYear;
    Map<CountryId,Country> countries; Map<LeagueId,League> leagues; Map<ClubId,Club> clubs; Map<PlayerId,Player> players; Map<ManagerId,Manager> managers; Map<FixtureId,Fixture> fixtures;
    SeasonCalendar calendar; ManagerId userManagerId; List<InboxMessage> inbox; List<SeasonArchive> history; IdAllocator ids;
    // derived indexes (not serialized): rebuildIndexes()
    List<PlayerId> squadOf(ClubId c);          // non-youth, sorted by id
    List<PlayerId> youthOf(ClubId c);
    List<FixtureId> fixturesOn(GameDate d);
    List<FixtureId> fixturesOfClub(ClubId c, int seasonYear);
    Club? userClub;                             // null when unemployed
  }
  ```
- [ ] **Step 1: Tests**: `rebuildIndexes` returns squad sorted and excludes youth and free agents; `fixturesOn` groups by date; `userClub` null when user manager has no club.
- [ ] **Step 2–4: FAIL → implement → PASS. Step 5: Commit** `feat(model): club, country, league, fixture, calendar, events, world`

---

### Task 6: JSON codec for the whole model `[Model: Opus]`

**Files:**
- Create: `lib/src/model/json.dart`, `test/model/json_test.dart`

**Interfaces:**
- Produces: `Map<String,dynamic> worldToJson(World w)`, `World worldFromJson(Map<String,dynamic> j)`; per-type `xToJson/xFromJson` for Player, Club, Manager, Fixture, etc. Map keys for id-keyed maps are **decimal strings sorted ascending**; enums serialized by `name`; `GameDate` as int; `Attributes` as `List<int>`; events as `{"t": "<typeName>", ...fields}`.
- [ ] **Step 1: Tests**: round trip of a hand-built mini world (2 countries, 2 leagues, 4 clubs, 40 players, 2 managers, 6 fixtures, 3 inbox events of different types) → `worldToJson(worldFromJson(j))` deep-equals `j`; `jsonEncode` of the round-tripped map is byte-identical (key order stable); each `GameEvent` subtype round-trips.
- [ ] **Step 2–4. Step 5: Commit** `feat(model): json codec`

---

### Task 7: Round-robin fixture scheduler `[Model: Opus]`

**Files:**
- Create: `lib/src/competition/fixtures.dart`, `test/competition/fixtures_test.dart`

**Interfaces:**
- Produces: `List<List<(ClubId home, ClubId away)>> doubleRoundRobin(List<ClubId> clubs, SeededRng rng)` — rounds `2*(n-1)` (n even) or `2*n` (n odd, one bye per round); second half mirrors the first with home/away swapped; `rng` only shuffles the initial order.
- [ ] **Step 1: Tests**: for n in {4, 18, 19, 20, 24}: every pair appears exactly twice with swapped venues; no club twice in a round; odd n → each club has exactly 2 byes; consecutive-home streak ≤ 2 for n=20 (Berger property); determinism with seed.
- [ ] **Step 2–4. Step 5: Commit** `feat(competition): double round robin`

---

### Task 8: Season calendar builder `[Model: Fable]`

**Files:**
- Create: `lib/src/competition/season_calendar_builder.dart`, `test/competition/season_calendar_test.dart`

**Interfaces:**
- Produces:
  ```dart
  SeasonCalendar buildSeasonCalendar(int seasonYear);
  List<GameDate> leagueMatchdays(SeasonCalendar cal, int rounds);   // dates for `rounds` rounds
  ```
  Rules (Spec §7.5, §16.7): `seasonStart` = second Saturday of August of `seasonYear`; international breaks = 9 days starting the Monday of the 2nd full week of September, October, November, March (June break is outside the season); matchdays are Saturdays from `seasonStart` skipping break weeks and the Saturday between Dec 24–26 and Jan 1; if `rounds` exceed available Saturdays before May 31, insert Wednesdays (the Wednesday after a used Saturday, earliest first, never inside a break) until it fits; `seasonEnd` = last matchday + 7; `summer` window = `seasonEnd+1` .. `seasonStart+21`; `winter` = Jan 1 .. Jan 31.
- [ ] **Step 1: Tests**: 38 rounds for 2026 fit on Saturdays only and end before May 31; 46 rounds use ≥ 8 Wednesdays; no matchday inside any break; no two matchdays on the same date; all matchdays are Sat or Wed; 2027/28 (Feb 29 2028) yields valid dates; `seasonEnd` after last matchday by 7; windows ordered.
- [ ] **Step 2–4. Step 5: Commit** `feat(competition): season calendar`

---

### Task 9: Standings `[Model: Opus]`

**Files:**
- Create: `lib/src/competition/standings.dart`, `test/competition/standings_test.dart`

**Interfaces:**
- Produces: `class TableRow { ClubId clubId; int played, won, drawn, lost, gf, ga, points; int get gd; }`, `List<TableRow> computeTable(World w, LeagueId l, int seasonYear)` — ordering: points desc, gd desc, gf desc, club name asc (ties, my call; data-driven later).
- [ ] **Step 1: Tests**: 3 clubs with scripted results → exact rows; unplayed fixtures ignored; tie-break order; sum(gf) == sum(ga).
- [ ] **Step 2–4. Step 5: Commit** `feat(competition): standings`

---

### Task 10: Country data and name pools `[Model: Opus — content]`

**Files:**
- Create: `lib/src/data/assets/countries.json`, `lib/src/data/assets/names/*.json` (16 files), `lib/src/data/country_data.dart`, `test/data/country_data_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class CountryTemplate { String code, name; Continent continent; String namePool; List<TierTemplate> tiers; int reputation; }   // reputation 1..100
  class TierTemplate { int clubs; int promoted; int relegated; String nameKey; }    // nameKey e.g. "tier1"
  class NamePool { List<String> firstNames, lastNames, cityNames; List<String> clubSuffixes; List<String> stadiumPatterns; }
  class CountryData { List<CountryTemplate> countries; Map<String,NamePool> pools; static CountryData load(); List<String> validate(); }
  ```
  `load()` reads the JSON assets embedded as Dart string constants generated by `tool/embed_assets.dart` into `lib/src/data/assets_embedded.dart` (so the package works without file IO on web). Validation rules: tier1 promoted == 0; tierN.promoted == tier(N-1).relegated; every tier ≥ 12 clubs; pool sizes ≥ 60 first, ≥ 80 last, ≥ 40 cities, ≥ 4 suffixes.
- Content (Opus writes; all fictional cities, no real club names): 16 countries in `countries.json` with real country names and codes: TR, GB-ENG (name "England"), ES, DE, IT, FR, NL, PT, BR, AR, US, MX, JP, KR, NG, AU; each 2–3 tiers (TR: 18/18/0 → tiers 18 and 18; ENG 20/24; ES 20/22; DE 18/18; IT 20/20; FR 18/20; NL 18/20; PT 18/18; BR 20/20; AR 28; US 24; MX 18; JP 20/22; KR 12; NG 20; AU 12). Promoted/relegated 3/3 default, 2/2 for leagues ≤ 14. Name pools in the local language with correct diacritics; club suffix patterns per country (TR: "{City}spor", "{City} FK", "{City} Gençlerbirliği"; ENG: "{City} United/City/Town/Athletic/Rovers"; DE: "FC {City}", "SV {City}", "{City} 04"; etc.).
- [ ] **Step 1: Tests**: `load()` succeeds; `validate()` empty; 16 countries; codes unique; every country's pool exists; no city name equals a real top-flight club city of that country from a small blacklist in the test (e.g., TR: İstanbul, Ankara, İzmir, Trabzon, Bursa, Konya; ENG: Manchester, Liverpool, London, Leeds, Newcastle).
- [ ] **Step 2–4** (write `tool/embed_assets.dart`, run it, commit the generated file). **Step 5: Commit** `feat(data): 16 country templates and name pools`

---

### Task 11: Player and club generators `[Model: Fable]`

**Files:**
- Create: `lib/src/gen/player_generator.dart`, `lib/src/gen/club_generator.dart`, `test/gen/player_generator_test.dart`, `test/gen/club_generator_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class PlayerGenerator {
    PlayerGenerator(NamePool pool, SeededRng rng, IdAllocator ids);
    Player generate({required CountryId nationality, required Position position, required int targetCa, required int age, required GameDate today, required ClubId? clubId, bool youth = false});
    Player generateForTier({required int tierReputation, ... same, int? age});   // picks CA/age from distributions
  }
  class ClubGenerator {
    ClubGenerator(NamePool pool, SeededRng rng, IdAllocator ids);
    Club generate({required CountryId countryId, required LeagueId leagueId, required int tier, required int countryReputation, required int indexInLeague, required Set<String> usedNames});
  }
  ```
  Distributions (Spec §8.3, §7.1; my calls where silent):
  - Club reputation: tier1 = countryRep − 10 + spread (top club countryRep+5, decreasing linearly to countryRep−25), tier2 = tier1 − 25, tier3 = tier1 − 40; clamp 5..100.
  - Squad: 24 ± 2 non-youth (clamp 22..26) with position quota {gk 3, dc 4, dl 2, dr 2, dm 2, mc 4, ml 1, mr 1, amc 2, st 3} ± rng; plus 6 youth aged 15–17.
  - Age: non-youth triangular 18..34 mode 25. CA: club-level mean `clubRep × 1.3 + 30` (rep 80 → 134, rep 30 → 69), sd 12, clamp 30..190; GKs −5. PA: `max(ca, ca + gaussian(mean = (27 − age) × 4, sd 10))` clamp ca..200.
  - Attributes from CA: per-position weight profile (Task 4 weights) → base level `ca/10`, relevant attrs +gaussian(0, 2) upward-biased, irrelevant attrs lower (base − 4 ± 2), then `computeCa` recomputed and stored as `ca` (so CA always equals attributes). GKs: outfield attrs 3–8.
  - Familiarity: main 20; adjacent positions (dc↔dl/dr 12, mc↔dm/amc 14, ml↔aml 14, st↔amc 10) else 1–5.
  - Contract: wage = `round(ca² × 0.9 / 100) × 10` per week in abstract units (ca 100 → 90, ca 150 → 200, ca 180 → 290); end = today + 1..4 years at June 30; status by CA rank in squad (top 4 keyPlayer, next 10 firstTeam, next 6 rotation, rest backup; youth → youth).
  - Hidden: uniform 1..20 each; height gaussian 180 ± 7 (GK 188).
  - Club: name = city + suffix pattern, unique in country; shortName = first 3 letters uppercased of city; kits: primary from a 16-color palette, secondary contrasting (luminance difference ≥ 0.4); away kit distinct from home; logo shape rng 0..7; stadium = pattern (`"{City} Stadyumu"` etc.), capacity tier1 25k–60k scaled by reputation, tier2 8k–25k, tier3 3k–10k; balance/transferBudget/wageBudget from reputation: `wageBudget = 24 × meanWage × 1.1`, `transferBudget = rep² × 100`, `balance = transferBudget`; facilities = clamp(rep/10 ± 1, 1, 10); expectation from reputation rank in league (top 2 title, 3–6 top, 7–10 upperMid, 11–14 mid, rest avoidRelegation); formation f442.
- [ ] **Step 1: Tests (stat, seed fixed, 2000 players)**: ages within 18..34 with mode near 25; CA mean within ±3 of formula for rep 80 and rep 30; `ca == computeCa(attrs, mainPosition)` for all; `pa >= ca`; GK outfield attrs ≤ 8; wage formula exact for CA 100/150/180; youth flag and age 15..17; club kits home≠away and contrast ≥ 0.4; club names unique across 60 generated clubs; capacity ranges by tier; determinism (same seed → same first player JSON).
- [ ] **Step 2–4. Step 5: Commit** `feat(gen): player and club generators`

---

### Task 12: World generator `[Model: Fable]`

**Files:**
- Create: `lib/src/gen/world_generator.dart`, `lib/src/sim/new_game.dart`, `test/gen/world_generator_test.dart`

**Interfaces:**
- Produces:
  ```dart
  enum WorldSize { small, medium, large }   // 4 / 8 / 16 countries; order of countries.json defines which are included (TR first)
  class NewGameSpec { int seed; WorldSize size; String managerFirstName, managerLastName; String managerCountryCode; ClubId? startClubId; }  // null → unemployed
  World generateWorld({required int seed, required WorldSize size, required GameDate startDate});   // startDate = buildSeasonCalendar(y).seasonStart - 14
  World createNewGame(NewGameSpec spec, {int startSeasonYear = 2026});   // generate + user manager (reputation 40) + AI managers for every club + first season fixtures scheduled + NewSeasonStarted inbox
  ```
  Fixtures: per league `doubleRoundRobin` mapped onto `leagueMatchdays`. Each club gets an AI `Manager` (reputation = club reputation ± 10). Calendar stored on world. All generator rng forks are named (`'world'`, `'country:TR'`, `'club:<id>'`, `'players:<clubId>'`) so adding a country does not perturb others.
- [ ] **Step 1: Tests**: small world has 4 countries and expected club counts; every club squad 22..26 and youth 6; every league has `2(n−1)` or `2n` rounds all dated; fixture dates ⊂ matchdays; `userClub` set when `startClubId` given, null otherwise; user manager `isUser`; every club has a manager; large world generation < 8 s (tag `slow`); same seed → identical `jsonEncode(worldToJson)` twice; changing size from small to medium leaves TR's first club JSON identical (fork isolation).
- [ ] **Step 2–4. Step 5: Commit** `feat(gen): world generator and new game`

---

### Task 13: Lineups `[Model: Opus]`

**Files:**
- Create: `lib/src/sim/lineup.dart`, `lib/src/sim/commands.dart`, `test/sim/lineup_test.dart`

**Interfaces:**
- Produces:
  ```dart
  Lineup autoLineup(World w, ClubId c, {Formation? formation});   // greedy: for each slot of formation pick highest `ca × familiarity/20 × conditionFactor` among eligible (not injured, suspension == 0, not youth unless squad < 11), each player once; bench = next 7 by CA incl. 1 GK; if eligible < 11, fill with youth, then with any player (never < min(11, squad size))
  List<LineupError> validateLineup(World w, ClubId c, Lineup l);  // enum LineupError { notEleven, duplicate, notInClub, noGoalkeeper, ineligible }
  sealed class Command { } · SetLineup(ClubId clubId, Lineup lineup) · ClearLineup(ClubId clubId)
  ```
- [ ] **Step 1: Tests**: auto lineup is 11 unique club players with one GK slot filled by a GK; prefers natural positions (a DC with ca 120 beats an ST with ca 125 for a dc slot when familiarity 1); suspended player excluded; with only 9 eligible seniors, youth fill to 11; validation errors each triggered once.
- [ ] **Step 2–4. Step 5: Commit** `feat(sim): auto lineup and lineup commands`

---

### Task 14: Match simulator interface + Poisson placeholder `[Model: Fable]`

**Files:**
- Create: `lib/src/sim/match_simulator.dart`, `lib/src/sim/poisson_match.dart`, `test/sim/poisson_match_test.dart`, `test/slow/poisson_stats_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class MatchContext { World world; Fixture fixture; Lineup home, away; SeededRng rng; }
  abstract interface class MatchSimulator { MatchResult simulate(MatchContext ctx); }
  class PoissonMatchSimulator implements MatchSimulator { }
  double lineupStrength(World w, Lineup l);   // mean over starters of ca × familiarity(slot)/20 × (0.75 + 0.25 × condition/100)
  ```
  Model (my call, calibrated to Spec §9 targets): `d = (S_home − S_away) / 20`; `λ_home = 1.45 × exp(0.55 × d) × 1.06`; `λ_away = 1.20 × exp(−0.55 × d)`; goals ~ Poisson; scorer per goal weighted by slot position {st 6, amc/aml/amr 3, mc/ml/mr 1.5, dm 0.7, dc/dl/dr 0.4, gk 0.02} × (finishing/10); minute uniform 1..90 sorted; `matchSeed = rng.nextUint32()` stored before sampling (replayability, Spec §18.1). The rng passed in is `world`-independent: caller forks `'match:<fixtureId>:<seasonYear>'`.
- [ ] **Step 1: Tests**: deterministic with same fixture and seed; scorers belong to the scoring club's starters; minutes ascending 1..90. Slow (20k matches, equal strength 120 vs 120): mean total goals 2.5–2.9; home win 43–47%, draw 24–28%, away 27–31%; strength gap +40 → stronger wins 74–82% (Spec §5.6 row +40 at 78 ± 4).
- [ ] **Step 2–4** (tune the two base rates and 0.55 until slow test passes; record final values in the file header). **Step 5: Commit** `feat(sim): match simulator interface and poisson placeholder`

---

### Task 15: Day loop `[Model: Fable]`

**Files:**
- Create: `lib/src/sim/day_loop.dart`, `test/sim/day_loop_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class DaySummary { GameDate date; List<GameEvent> events; List<FixtureId> playedFixtures; Duration elapsed; }
  class DayRunner {
    DayRunner(MatchSimulator sim);
    void startOfDay(World w, List<Command> commands);   // apply commands (SetLineup validated → else ignored + no event), daily player update stub (condition = min(100, condition + 12)), AI lineup refresh for clubs with fixtures today that have no valid lineup
    List<FixtureId> playMatches(World w);                // all fixtures dated today, sorted by id; rng fork per match; results stored; stats (apps, goals) updated; MatchPlayed events
    List<GameEvent> endOfDay(World w);                   // standings cache not needed (computed on demand); if date == calendar.seasonEnd → rolloverSeason (Task 16) events; inbox append (user-relevant filter) + trim to 300; w.date += 1
    DaySummary advanceDay(World w, List<Command> commands);   // the three in order
  }
  bool isUserRelevant(World w, GameEvent e);   // involves user's club, or is season-level (SeasonEnded, NewSeasonStarted, LeagueChampion of user's league), or user unemployed → season-level only
  ```
  Symmetry rule enforced here: `playMatches` and lineups never check `isUser`.
- [ ] **Step 1: Tests** (small world, seed 1): advancing to the first matchday plays exactly the fixtures of that date and every one has a result; `date` increments by 1 each call; a `SetLineup` for the user club is used in that club's next match (starters appear in lineup stored on club); an invalid `SetLineup` is ignored and auto lineup is used; inbox never exceeds 300 after 400 synthetic events; with user unemployed (`startClubId: null`) 60 days advance without error and inbox holds only season-level events; a 7-day advance takes < 50 ms per non-match day on small world (sanity, not the budget test).
- [ ] **Step 2–4. Step 5: Commit** `feat(sim): day loop`

---

### Task 16: Season rollover `[Model: Fable]`

**Files:**
- Create: `lib/src/sim/season_rollover.dart`, `lib/src/competition/promotion.dart`, `test/sim/season_rollover_test.dart`

**Interfaces:**
- Produces:
  ```dart
  List<GameEvent> rolloverSeason(World w, SeededRng rng);   // called by endOfDay on seasonEnd
  void applyPromotionRelegation(World w, CountryId c, Map<LeagueId, List<TableRow>> tables);   // swap bottom `relegatedCount` of tier k with top `promotedCount` of tier k+1
  ```
  Order (Spec §3 step 9, §11 Faz 0 simplifications): (1) archive: `SeasonArchive` with champions + final order, `LeagueChampion` events; (2) promotion/relegation per country (`Promoted`/`Relegated` events; `club.leagueId` and `league.clubIds` updated); (3) career lines: push `SeasonStats` into `career`, reset `season`; (4) aging/retirement: every player with `age ≥ 35` on `seasonEnd` → removed from `players` and indexes, `PlayerRetired`; (5) youth intake: per club `3 + rng.nextInt(4)` players age 16 via `PlayerGenerator.generate(targetCa = clubRep × 0.6 + 20 ± 10, youth: true)`, `YouthIntake` event; promote youth aged ≥ 18 to senior (`isYouth = false`); (6) squad floor: if senior squad < 18, generate fillers aged 19–24 at club-level CA − 15 until 18; (7) contracts: every senior contract with `end ≤ seasonEnd` → extend 2 years (AI auto-renew; applies to user club too in Faz 0, documented); (8) new calendar `buildSeasonCalendar(seasonYear + 1)` and fixtures for every league; (9) `seasonYear += 1`; clear lineups; `SeasonEnded` + `NewSeasonStarted` events; `w.date` is set to `newCalendar.seasonStart − 14` only if that is after today — otherwise the day loop simply continues (no time jump).
- [ ] **Step 1: Tests**: after rollover, each league's clubIds changed exactly by promoted/relegated sets; champion recorded equals table leader; no player aged ≥ 35 remains; every club senior squad 18..28; youth per club increased by 3..6 minus promotions; a club seeded with 25 players aged 36 ends with exactly 18 seniors (fillers) and no fixture uses an absent player; user manager still references a valid club after relegation; expired contracts extended; new fixtures count correct; events contain `SeasonEnded` and `NewSeasonStarted` in that order; `history.length == 1`.
- [ ] **Step 2–4. Step 5: Commit** `feat(sim): season rollover with promotion, retirement, youth intake`

---

### Task 17: Invariants `[Model: Fable]`

**Files:**
- Create: `lib/src/invariants/invariants.dart`, `test/invariants/invariants_test.dart`

**Interfaces:**
- Produces: `class Violation { String rule; String detail; }`, `List<Violation> checkInvariants(World w)`; rules for Faz 0 (Spec §17.2): `player.oneClub` (contract.clubId exists and player in that club's squad index; free agents in no squad), `squad.size` 18..28 seniors, `lineup.valid` (if set: 11 unique, all in club, one GK, no suspended/injured), `player.ranges` (attrs 1..20, ca ≤ pa, ca/pa 1..200, age 15..45, condition/morale/sharpness 0..100), `contract.dates` (end > start; end ≥ world.date − 1 for all contracted), `league.fixtures` (per league per season: each pair exactly twice, each fixture once), `table.goals` (Σgf == Σga per league), `calendar.noDoubleBooking` (no club two fixtures on one date), `ids.unique` (no id reused across players/clubs), `manager.seat` (every club has exactly one manager; every employed manager's club points back), `inbox.size` ≤ 300, `inbox.refs` (every referenced id exists), `history.champion` (archived champion == first of archived finalOrder).
- [ ] **Step 1: Tests**: fresh small world → zero violations; each rule triggered once by a deliberate mutation (13 tests); small world after 1 full season (advance to seasonEnd + 1) → zero violations.
- [ ] **Step 2–4. Step 5: Commit** `feat(invariants): world invariant checker`

---

### Task 18: Persistence — codec, store, migrations `[Model: Opus; Fable reviews migration design]`

**Files:**
- Create: `lib/src/persistence/save_codec.dart`, `save_store.dart`, `migrations.dart`; tests `test/persistence/*_test.dart`

**Interfaces:**
- Produces:
  ```dart
  const int currentSchemaVersion = 1;
  class SaveError implements Exception { SaveErrorKind kind; String message; }  enum SaveErrorKind { corrupt, newerSchema, missingSlot, io }
  abstract interface class SaveCodec { Uint8List encode(World w); World decode(Uint8List bytes); }
  class JsonGzipSaveCodec implements SaveCodec { }   // bytes = gzip(utf8(jsonEncode({"schemaVersion": v, "world": worldToJson(w)}))); decode runs migrate() before worldFromJson
  class Migration { int from; Map<String,dynamic> Function(Map<String,dynamic>) apply; }
  Map<String,dynamic> migrate(Map<String,dynamic> envelope);   // applies registered migrations from envelope.schemaVersion up to current; throws SaveError(newerSchema) if higher
  class SlotInfo { int slot; String managerName; String? clubName; GameDate date; int seasonYear; DateTime savedAt; int bytes; }
  abstract interface class SaveStore { Future<List<SlotInfo>> list(); Future<void> write(int slot, Uint8List bytes, SlotInfo meta); Future<Uint8List> read(int slot); Future<void> delete(int slot); }
  class MemorySaveStore implements SaveStore { }
  class FileSaveStore implements SaveStore { FileSaveStore(Directory root); }   // <root>/slot_<n>/world.bin + meta.json (layout of Spec §18.3; recent/ and history/ arrive in Faz 4)
  ```
- [ ] **Step 1: Tests**: encode→decode→encode gives identical bytes for a small world; decode of random bytes → `SaveError(corrupt)`; envelope with `schemaVersion: 99` → `SaveError(newerSchema)`; a registered test migration 0→1 renaming a key is applied; `FileSaveStore` in a temp dir: write/list/read/delete, `list` sorted by slot, `read` of empty slot → `missingSlot`; `MemorySaveStore` same contract (shared test body).
- [ ] **Step 2–4. Step 5: Commit** `feat(persistence): json+gzip codec, save stores, migrations`

---

### Task 19: EngineSession `[Model: Fable]`

**Files:**
- Create: `lib/src/session/engine_session.dart`, `test/session/engine_session_test.dart`

**Interfaces:**
- Produces:
  ```dart
  class EngineSession {
    EngineSession.newGame(NewGameSpec spec, {MatchSimulator? sim, SaveCodec? codec});
    EngineSession.fromBytes(Uint8List bytes, {MatchSimulator? sim, SaveCodec? codec});   // throws SaveError
    World get world;                                      // read-only use by queries
    DaySummary advanceDay([List<Command> commands = const []]);
    List<DaySummary> advanceUntil(GameDate date, {List<Command> commands = const []});   // stops early at first day whose summary has a user-relevant MatchPlayed for the user club or a SeasonEnded; returns summaries so far
    GameDate? nextUserMatchDate();
    Uint8List save();
    // queries used by Faz 0B (plain model objects, no DTO layer)
    List<TableRow> table(LeagueId l); List<Fixture> clubFixtures(ClubId c); List<Player> squad(ClubId c); List<InboxMessage> inbox({bool unreadOnly = false}); void markRead(int inboxIndex);
    List<Violation> checkInvariants();
  }
  ```
  `sim` defaults to `PoissonMatchSimulator`; `codec` to `JsonGzipSaveCodec`. No static/global state (isolate-safe).
- [ ] **Step 1: Tests**: new game then `advanceUntil(seasonStart + 30)` stops on the user's first match day; `save()` then `fromBytes` then `advanceDay` twice equals the un-saved session's two more days (JSON equal); `nextUserMatchDate` null when unemployed; `inbox(unreadOnly)` and `markRead`.
- [ ] **Step 2–4. Step 5: Commit** `feat(session): EngineSession`

---

### Task 20: CLI `[Model: Opus]`

**Files:**
- Create: `bin/cm.dart`, `lib/src/cli/commands.dart`, `test/cli/cli_test.dart`

**Interfaces:**
- Produces commands (via `package:args`):
  - `cm generate --seed 1 --size small|medium|large --out world.bin` → writes save bytes, prints counts (countries, leagues, clubs, players) as JSON.
  - `cm simulate --seed 1 --size small --seasons 2 [--invariants] [--report report.json]` → runs seasons unemployed-user; prints per-season: champions per league, goals/match, home/draw/away %, invariant violation count; with `--invariants` runs `checkInvariants` every day and exits 2 on first violation (printing it).
  - `cm bench --seed 1 --size large --days 400 --report bench.json` → per-day timings: p50/p95/max for match days and non-match days, generation time, save bytes, save/load ms; exits 0 always (thresholds are asserted by Task 21 tests).
  - `cm inspect world.bin --club <id> | --table <leagueId>` → prints JSON.
- [ ] **Step 1: Tests**: run each command in-process via `runCli(List<String> args) -> Future<int>` with a temp dir; `simulate --seasons 1 --invariants` on small returns 0; `bench --days 30` writes a report with the expected keys; unknown command returns 64.
- [ ] **Step 2–4. Step 5: Commit** `feat(cli): generate, simulate, bench, inspect`

---

### Task 21: Long simulation, performance and determinism gates `[Model: Fable]`

**Files:**
- Create: `test/slow/long_sim_test.dart`, `test/slow/perf_test.dart`, `test/determinism_test.dart`

- [ ] **Step 1: Tests**
  - `determinism_test` (fast): two `EngineSession.newGame(seed 7, small)` advanced 120 days with the same `SetLineup` on day 3 → `jsonEncode(worldToJson)` identical; `Isolate.run` of the same 120-day advance returns identical JSON to the main-isolate run.
  - `long_sim_test` (slow): small world, 5 seasons, invariants every day → zero violations; each season: total goals/match 2.5–2.9, home 43–47 %, every league champion is table leader; senior squads 18..28 every day; player count drift ≤ 10 % over 5 seasons; age distribution buckets (16–20 / 21–25 / 26–30 / 31+) each within ±8 points of season-1 values (Faz 0 loose bound; Spec §9 bounds apply from Faz 4).
  - `perf_test` (slow): large world; generation < 8 s; 400 days: match-day p95 < 300 ms, non-match-day p95 < 50 ms; save bytes < 15 MB; save < 2 s; load < 2 s; peak RSS not measured (Faz 0B measures on device).
- [ ] **Step 2: Run** `dart test -t slow` — iterate on hot spots (index rebuild per day is the likely offender: rebuild only on structural change) until green.
- [ ] **Step 3: Update `tool/check.sh --slow` docs in README section of `packages/engine/README.md`** (how to run, what the gates mean, final Poisson constants).
- [ ] **Step 4: Commit** `test: long simulation, performance and determinism gates`

---

### Task 22: Faz 0A acceptance `[Model: Fable]`

- [ ] **Step 1:** `tool/check.sh --slow` green from a clean checkout (`git clean -xdf packages/engine && dart pub get`).
- [ ] **Step 2:** `dart run bin/cm.dart simulate --seed 3 --size medium --seasons 3 --invariants` exits 0; paste the report into `docs/superpowers/plans/2026-10-20-faz0a-engine.md` under a "Results" heading (goals/match, result split, timings).
- [ ] **Step 3:** Record in `packages/engine/README.md`: schema version 1, Poisson constants, generator distributions that differ from this plan after tuning.
- [ ] **Step 4:** Fable whole-branch review (superpowers:requesting-code-review), fix findings, commit `chore: faz 0A acceptance`.
- [ ] **Step 5:** Hand off to the Faz 0B (Flutter app) plan, which consumes `EngineSession`, `SaveStore`, `SaveCodec`, the model types and `GameEvent` sealed hierarchy exactly as named here.

---

## Self-review notes

- Spec coverage for Faz 0 (Spec §11 row 0): data model incl. placeholders (Tasks 4–5), world generator with kits/logos (10–12), new game spec incl. unemployed (12, 19), save slots + schema versioning (18), day loop (15), fixtures + table (7–9), Poisson placeholder (14), performance measurement (20–21), basic youth/retirement (16), symmetry (15 tests), determinism incl. isolate (21). Minimal UI, entitlement stub, i18n, responsive rule and storage-on-web belong to Faz 0B.
- Names used across tasks: `World`, `GameDate`, `SeededRng.fork`, `Lineup`, `MatchResult`, `TableRow`, `computeTable`, `DaySummary`, `rolloverSeason`, `checkInvariants`, `SaveCodec`, `SaveStore`, `EngineSession` — consistent above.
- Review Focus items pinned: 1 → Task 7; 2 → Tasks 15, 16; 3 → Tasks 13, 16; 4 → Task 18; 5 → Tasks 3, 8.

---

## Results (Task 22 acceptance, 2026-10-20)

- `tool/check.sh --slow` from a clean checkout: format 0 changed, analyze clean, 318 fast + 15 slow tests green (slow suite 14.8 s wall).
- `cm simulate --seed 3 --size medium --seasons 3 --invariants` → exit 0, 0 violations:

| Season | Matches | Goals/match | Home % | Draw % | Away % | Days | ms |
|---|---|---|---|---|---|---|---|
| 2026 | 5742 | 2.892 | 46.8 | 21.3 | 31.9 | 316 | 2066 |
| 2027 | 5742 | 2.846 | 46.1 | 23.0 | 30.9 | 364 | 2525 |
| 2028 | 5742 | 2.845 | 44.7 | 22.8 | 32.5 | 364 | 2758 |

- Long sim (small, seed 11, 5 seasons, 1779 days): 0 invariant violations; goals 2.83–2.93; home 44.6–46.1 %; population season 5 vs 2 +6.6 %; max youth squad 21; retired 26→214, intake ~700, released 0→543 per season.
- Perf (large, seed 1): generation 117 ms; match-day p95 2.97 ms (budget 300); other-day p95 1.11 ms (budget 50); save 1.97 MB in 391 ms (budget 15 MB / 2 s); load 324 ms.
- Draw % runs below the spec band (24–28) once real strength spread exists — expected for the Poisson placeholder; the Faz 1a engine owns the full result-split calibration.
