# Integration tests

Drive the real app (real engine isolate, real file saves in a temp
directory) on a device or desktop. They are not part of the default
`flutter test` run.

## Tests

- `app_flow_test.dart` (small world, TR): new game via the UI → advance to
  match day → auto lineup → play the match → result sheet → inbox item →
  manual save to slot 1 → restart the app widget → "Devam et" (newest
  autosave) shows the same date → load slot 1 shows the same date. The
  restart checks the autosave is at a day boundary: the date after
  continuing equals the date the last action ended on.
- `perf_test.dart` (LARGE world, unemployed): the device performance gate.
  Prints one `[perf] {...}` JSON line and asserts
  - new game (world generation + first home) < 10 s (debug: 30 s),
  - while one "Devam" runs in the engine isolate the UI keeps rendering:
    at least 10 frames and no frame longer than 100 ms (debug: 250 ms),
  - manual save < 2 s (debug: 5 s).

  The spec budgets apply in profile mode; `flutter test` builds debug, which
  is several times slower, so the test relaxes them there.

## Commands

macOS (debug):

    flutter test integration_test/app_flow_test.dart -d macos
    flutter test integration_test/perf_test.dart -d macos
    tool/check.sh --integration      # runs both

macOS (profile, the real gate):

    flutter drive --profile \
      --driver=test_driver/integration_test.dart \
      --target=integration_test/perf_test.dart -d macos

The macOS Profile configuration builds `arm64` only (`ARCHS = arm64` in
`macos/Runner.xcodeproj`): Flutter 3.44's framework check runs
`lipo -verify_arch arm64 x86_64`, which Xcode 27's `lipo` rejects, so a
universal profile build fails before compiling. Debug is already single-arch
and Release is unchanged.

A device: replace `-d macos` with `-d <id>` from `flutter devices`. On an
iOS device the Runner must be signed once: open `ios/Runner.xcworkspace`
in Xcode and pick a development team under Signing & Capabilities; the
device must be in Developer Mode.
