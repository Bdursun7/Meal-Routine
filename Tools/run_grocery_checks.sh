#!/usr/bin/env bash
# Compiles the Foundation-only grocery merger and runs its checks. No Xcode.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFTC="${SWIFTC:-swiftc}"
OUT="${TMPDIR:-/tmp}/meal-grocery-checks"
"$SWIFTC" -swift-version 5 -o "$OUT" \
  "$ROOT/MealRoutine/Services/Catalog/RecipeCatalogDTO.swift" \
  "$ROOT/MealRoutine/Services/PortionScaler.swift" \
  "$ROOT/MealRoutine/Services/UnitNormalization.swift" \
  "$ROOT/MealRoutine/Services/GroceryMerger.swift" \
  "$ROOT/MealRoutine/Support/Formatters.swift" \
  "$ROOT/Tools/grocery_merge_checks.swift"
(cd "$ROOT" && "$OUT")
