#!/usr/bin/env bash
# Format, analyze and test the engine package. Pass --slow to also run
# tests tagged `slow`.
set -euo pipefail

cd "$(dirname "$0")/.."

dart format --set-exit-if-changed .
dart analyze --fatal-infos
dart test -x slow

if [[ "${1:-}" == "--slow" ]]; then
  # Exit code 79 means no test carries the tag yet; that is not a failure.
  dart test -t slow || [[ $? -eq 79 ]]
fi
