#!/usr/bin/env bash
# Compiles the Foundation-only V2 memory and scoring checks. No Xcode.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFTC="${SWIFTC:-swiftc}"
OUT="${TMPDIR:-/tmp}/meal-memory-checks"
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
  "$ROOT/MealRoutine/Services/MealPatternService.swift" \
  "$ROOT/MealRoutine/Services/DiscoverySections.swift" \
  "$ROOT/MealRoutine/Services/MealReplacement.swift" \
  "$ROOT/MealRoutine/Support/WeekCalendar.swift" \
  "$ROOT/MealRoutine/Support/WeekPresentationRules.swift" \
  "$ROOT/Tools/meal_memory_checks.swift"
(cd "$ROOT" && "$OUT")
