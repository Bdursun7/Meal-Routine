#!/usr/bin/env bash
# Foundation-only checks for API address priority and the household local-push gate.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFTC="${SWIFTC:-swiftc}"
OUT="${TMPDIR:-/tmp}/api-base-url-checks"
"$SWIFTC" -swift-version 5 -o "$OUT" \
  "$ROOT/MealRoutine/Auth/APIBaseURLResolver.swift" \
  "$ROOT/MealRoutine/Household/HouseholdLocalPushGate.swift" \
  "$ROOT/Tools/api_base_url_checks.swift"
"$OUT"
