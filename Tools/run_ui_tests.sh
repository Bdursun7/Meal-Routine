#!/usr/bin/env bash
# MealRoutineUITests on the iPhone 17 Pro simulator. Requires Xcode on a Mac.
# -only-testing runs the whole UI target, including HouseholdFlowUITests.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
exec xcodebuild test \
  -scheme MealRoutine \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MealRoutineUITests
