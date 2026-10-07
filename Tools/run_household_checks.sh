#!/usr/bin/env bash
# Compiles the Foundation-only V4 household checks. No Xcode.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFTC="${SWIFTC:-swiftc}"
OUT="${TMPDIR:-/tmp}/household-checks"
"$SWIFTC" -swift-version 5 -o "$OUT" \
  "$ROOT/MealRoutine/Models/MealRating.swift" \
  "$ROOT/MealRoutine/Models/FeedbackReason.swift" \
  "$ROOT/MealRoutine/Models/UserDiscoveryPreference.swift" \
  "$ROOT/MealRoutine/Models/RecipeMemoryScore.swift" \
  "$ROOT/MealRoutine/Models/MealMemorySnapshot.swift" \
  "$ROOT/MealRoutine/Services/ConfidenceCalculator.swift" \
  "$ROOT/MealRoutine/Services/MealRecommender.swift" \
  "$ROOT/MealRoutine/Services/PreferenceInsight.swift" \
  "$ROOT/MealRoutine/Services/PlanExplanationBuilder.swift" \
  "$ROOT/MealRoutine/Services/RecommendationReasonService.swift" \
  "$ROOT/MealRoutine/Services/PersonalizedScoringService.swift" \
  "$ROOT/MealRoutine/Services/MealReplacement.swift" \
  "$ROOT/MealRoutine/Household/HouseholdDomain.swift" \
  "$ROOT/MealRoutine/Household/HouseholdLogicChecks.swift" \
  "$ROOT/MealRoutine/Services/IngredientDictionary.swift" \
  "$ROOT/MealRoutine/Services/PantryDomain.swift" \
  "$ROOT/MealRoutine/Services/UnitNormalization.swift" \
  "$ROOT/MealRoutine/Support/Formatters.swift" \
  "$ROOT/MealRoutine/Services/GroceryMerger.swift" \
  "$ROOT/MealRoutine/Services/GroceryQuantityEdit.swift" \
  "$ROOT/MealRoutine/Services/GroceryListReconciler.swift" \
  "$ROOT/Tools/household_checks.swift"
"$OUT"
