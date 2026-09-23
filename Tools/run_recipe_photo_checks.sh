#!/usr/bin/env bash
# Compiles the Foundation-only photo helpers and runs their checks. No Xcode.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFTC="${SWIFTC:-swiftc}"
OUT="${TMPDIR:-/tmp}/meal-recipe-photo-checks"
"$SWIFTC" -swift-version 5 -o "$OUT" \
  "$ROOT/MealRoutine/Services/Catalog/CatalogIntegrity.swift" \
  "$ROOT/MealRoutine/Services/Catalog/RecipeCatalogDTO.swift" \
  "$ROOT/MealRoutine/Services/RecipePhoto.swift" \
  "$ROOT/MealRoutine/Services/RecipePhotoLoader.swift" \
  "$ROOT/Tools/recipe_photo_checks.swift"
(cd "$ROOT" && "$OUT")
