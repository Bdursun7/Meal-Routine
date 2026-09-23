#!/usr/bin/env bash
# Compiles the Foundation-only recommender and runs its checks. No Xcode.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFTC="${SWIFTC:-swiftc}"
OUT="${TMPDIR:-/tmp}/meal-recommender-checks"
"$SWIFTC" -swift-version 5 -o "$OUT" \
  "$ROOT/MealRoutine/Models/MealRating.swift" \
  "$ROOT/MealRoutine/Services/Catalog/RecipeCatalogDTO.swift" \
  "$ROOT/MealRoutine/Services/MealRecommender.swift" \
  "$ROOT/MealRoutine/Services/MealExposureLog.swift" \
  "$ROOT/Tools/meal_recommender_checks.swift"
(cd "$ROOT" && "$OUT")
