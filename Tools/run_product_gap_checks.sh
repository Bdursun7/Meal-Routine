#!/usr/bin/env bash
# Compiles the Foundation-only product-gap checks. No Xcode.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFTC="${SWIFTC:-swiftc}"
OUT="${TMPDIR:-/tmp}/meal-product-gap-checks"
"$SWIFTC" -swift-version 5 -o "$OUT" \
  "$ROOT/MealRoutine/Models/MealRating.swift" \
  "$ROOT/MealRoutine/Services/MealRecommender.swift" \
  "$ROOT/MealRoutine/Services/RecipeBrowse.swift" \
  "$ROOT/MealRoutine/Services/MealReplacement.swift" \
  "$ROOT/MealRoutine/Services/PreferenceInsight.swift" \
  "$ROOT/MealRoutine/Services/Analytics.swift" \
  "$ROOT/MealRoutine/Support/Formatters.swift" \
  "$ROOT/Tools/product_gap_checks.swift"
(cd "$ROOT" && "$OUT")
