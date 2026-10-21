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
  esac
done

format_dirs=(lib test)
[[ -d integration_test ]] && format_dirs+=(integration_test)
dart format --set-exit-if-changed "${format_dirs[@]}"
flutter analyze --fatal-infos
# Exit code 79 means no test carries the tag yet; that is not a failure.
flutter test -x golden || [[ $? -eq 79 ]]

if $golden; then
  flutter test -t golden || [[ $? -eq 79 ]]
fi

if $integration; then
  if [[ -d integration_test ]] && [[ -n "$(ls -A integration_test)" ]]; then
    flutter test integration_test -d macos
  else
    echo "No integration tests found; skipping."
  fi
fi
