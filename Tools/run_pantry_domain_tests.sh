#!/usr/bin/env bash
# Runs MealRoutineTests/PantryDomainTests.swift with XCTest through SwiftPM. No Xcode.
# The pantry domain, dictionary and planner signal are Foundation only; SwiftUI and
# SwiftData code (PantryView, PantryRules, PantryTests) still needs an Xcode run.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="${TMPDIR:-/tmp}/mealroutine-pantry-domain"
rm -rf "$PKG/Sources" "$PKG/Tests"
mkdir -p "$PKG/Sources/MealRoutine" "$PKG/Tests/PantryDomainTests"
for file in \
  Services/IngredientDictionary.swift \
  Services/PantryDomain.swift \
  Services/UnitNormalization.swift \
  Services/MealRecommender.swift \
  Services/GroceryQuantityEdit.swift \
  Services/GroceryListReconciler.swift \
  Services/GroceryMerger.swift \
  Support/Formatters.swift \
  Models/MealRating.swift; do
  ln -sf "$ROOT/MealRoutine/$file" "$PKG/Sources/MealRoutine/$(basename "$file")"
done
ln -sf "$ROOT/MealRoutineTests/PantryDomainTests.swift" "$PKG/Tests/PantryDomainTests/PantryDomainTests.swift"
# The tests look for MealRoutine/Recipes/ingredients.v1.json next to their own path.
ln -sfn "$ROOT/MealRoutine" "$PKG/MealRoutine"
cat > "$PKG/Package.swift" <<'SWIFT'
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PantryDomain",
    targets: [
        .target(name: "MealRoutine", path: "Sources/MealRoutine", swiftSettings: [.unsafeFlags(["-swift-version", "5"])]),
        .testTarget(name: "PantryDomainTests", dependencies: ["MealRoutine"], path: "Tests/PantryDomainTests"),
    ]
)
SWIFT
cd "$PKG" && swift test
