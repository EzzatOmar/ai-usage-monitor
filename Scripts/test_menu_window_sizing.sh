#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
sources=()
for source in Sources/*.swift; do
    [[ "$source" == "Sources/AIUsageMonitorApp.swift" ]] || sources+=("$source")
done
swiftc -parse-as-library "${sources[@]}" scripts/MenuWindowSizingSmoke.swift \
    -lsqlite3 -o "$TEMP_DIR/MenuWindowSizingSmoke"
"$TEMP_DIR/MenuWindowSizingSmoke"
