# cm_app — Flutter client (Faz 0B)

Portrait Flutter client for the CM-style football manager game. The game logic lives in `packages/engine` (pure Dart); this app hosts it in an isolate and renders snapshots.

## Run

```bash
cd apps/cm_app
flutter pub get                 # also generates lib/l10n/generated/
flutter run -d macos            # desktop (fastest dev loop)
flutter run -d <ios-device-id>  # needs a signing team in Xcode once
flutter run -d <android-id>
```

## Test

```bash
tool/check.sh                 # format + analyze + unit/widget tests (goldens excluded)
tool/check.sh --golden        # 80 golden screenshots (macOS only; regenerate with
                              #   flutter test --update-goldens -t golden test/golden)
tool/check.sh --integration   # real engine + isolate, macOS: app flow + perf gate (debug)
../../tool/check-all.sh --slow --golden --integration   # engine + app, everything
```

Profile-mode performance gate:

```bash
flutter drive --profile --driver=test_driver/integration_test.dart \
  --target=integration_test/perf_test.dart -d macos
```

## Architecture

```
UI (lib/ui/**)  ──watch──▶  GameController (lib/state)  ──▶  GameRepository (lib/data: saves, autosave)
                                      │
                                      ▼
                          EngineGateway (lib/engine/engine_gateway.dart)
                 ┌────────────────────┴────────────────────┐
        IsolateGateway (real app)                InProcessGateway (tests)
        worker isolate ──▶ InProcessGateway ──▶ SnapshotBuilder ──▶ EngineSession (packages/engine)
```

- Screens never touch `World`; they receive immutable snapshots (`lib/engine/snapshots.dart`).
- `GameController` is a small state machine: `NoGame | Busy | Ready | Failed`; every action is funnelled through one `_run`, autosaves after every advance, and recovers from save failures without re-applying commands.
- Saves: engine `SaveStore` (`FileSaveStore` under `<documents>/saves`); slots 1–5 manual, 6–8 rotating autosaves; save schema v2 with migrations.
- Localization: ARB (`lib/l10n/app_{en,tr}.arb`), `EventText` maps engine events to copy; league names are derived (`"Türkiye 1. Lig"`).
- Widget tests use `FakeGateway` + `pumpApp`; strings are resolved through `AppLocalizations`, never literals.

## Known Faz 0 limitations

- Match engine is the Poisson placeholder (Faz 1a replaces it); no player development yet, so squad quality decays over many seasons (engine README).
- App name "Futbol Menajeri / Football Manager" and bundle id `com.hakanartuc.cm_app` are placeholders.
- Transfer tab, cups, injuries/condition dynamics and the tutorial arrive in later phases.
- macOS Profile builds pin `ARCHS = arm64` to work around a Flutter 3.44 / Xcode 27 `lipo` incompatibility (revert when fixed upstream).
- iOS device runs require Developer Mode on the phone and a signing team in Xcode.
