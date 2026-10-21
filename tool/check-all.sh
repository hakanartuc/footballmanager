#!/usr/bin/env bash
# Run the engine and app checks. Flags:
#   --slow         engine: also run tests tagged `slow`
#   --golden       app: also run golden tests
#   --integration  app: also run integration tests on macOS
set -euo pipefail

cd "$(dirname "$0")/.."

engine_args=()
app_args=()
for arg in "$@"; do
  case "$arg" in
    --slow) engine_args+=(--slow) ;;
    --golden | --integration) app_args+=("$arg") ;;
    *) echo "Unknown flag: $arg" >&2; exit 2 ;;
  esac
done

packages/engine/tool/check.sh "${engine_args[@]+"${engine_args[@]}"}"
apps/cm_app/tool/check.sh "${app_args[@]+"${app_args[@]}"}"
