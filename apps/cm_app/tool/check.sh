#!/usr/bin/env bash
# Format, analyze and test the app. Flags:
#   --golden       also run tests tagged `golden`
#   --integration  also run integration_test/ on macOS
set -euo pipefail

cd "$(dirname "$0")/.."

golden=false
integration=false
for arg in "$@"; do
  case "$arg" in
    --golden) golden=true ;;
    --integration) integration=true ;;
    *) echo "Unknown flag: $arg" >&2; exit 2 ;;
  esac
done

format_dirs=(lib test)
[[ -d integration_test ]] && format_dirs+=(integration_test)
dart format --set-exit-if-changed "${format_dirs[@]}"
flutter analyze --fatal-infos
# Exit code 79 means no test matched the tag filter; that is not a failure.
# The exit code is checked explicitly because bash 3.2's errexit does not
# fire on a failing `[[ ]]` after `||`.
rc=0
flutter test -x golden || rc=$?
if [[ $rc -ne 0 && $rc -ne 79 ]]; then exit "$rc"; fi

if $golden; then
  rc=0
  flutter test -t golden || rc=$?
  if [[ $rc -ne 0 && $rc -ne 79 ]]; then exit "$rc"; fi
fi

if $integration; then
  if [[ -d integration_test ]] && [[ -n "$(ls -A integration_test)" ]]; then
    # One run per file: launching the macOS app a second time within one
    # `flutter test` run fails with "Error waiting for a debug connection".
    for f in integration_test/*_test.dart; do
      flutter test "$f" -d macos
    done
  else
    echo "No integration tests found; skipping."
  fi
fi
