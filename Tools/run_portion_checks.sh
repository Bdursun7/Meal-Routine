#!/usr/bin/env bash
# Compiles the Foundation-only portion helpers and runs their checks. No Xcode.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFTC="${SWIFTC:-swiftc}"
OUT="${TMPDIR:-/tmp}/meal-portion-checks"
"$SWIFTC" -swift-version 5 -o "$OUT" \
  "$ROOT/MealRoutine/Services/PortionScaler.swift" \
  "$ROOT/MealRoutine/Support/Formatters.swift" \
  "$ROOT/MealRoutine/Support/RegionalSettings.swift" \
  "$ROOT/MealRoutine/Support/L10n.swift" \
  "$ROOT/MealRoutine/Services/UnitNormalization.swift" \
  "$ROOT/MealRoutine/Services/GroceryMerger.swift" \
  "$ROOT/MealRoutine/Services/GroceryQuantityEdit.swift" \
  "$ROOT/MealRoutine/Services/GroceryListReconciler.swift" \
  "$ROOT/MealRoutine/Models/MealRating.swift" \
  "$ROOT/MealRoutine/Services/MealRecommender.swift" \
  "$ROOT/MealRoutine/Services/IngredientDictionary.swift" \
  "$ROOT/MealRoutine/Services/PantryDomain.swift" \
  "$ROOT/Tools/portion_scale_checks.swift"
(cd "$ROOT" && "$OUT")
