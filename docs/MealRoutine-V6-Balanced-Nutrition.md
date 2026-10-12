# MealRoutine V6 — Balanced Nutrition

**Roadmap:** V1 Core Meal Planning → V2 Personal Meal Memory → V3 Personal Recipe Collection → V4 Household & Shared Planning → V4.1 Release Hardening → V5 Smart Pantry → **V6 Balanced Nutrition** → V7 Globalization & Localization

**Status:** Locked implementation specification.  
**Prerequisite:** V5 acceptance gate must pass. Run the Globalization Readiness V1–V6 audit first; fix P0/P1 findings before V6. A separate V5.1 release is created only if the audit proves code changes are needed.

## 1. Purpose

V6 makes weekly plans better reflect the user's preferred meal pattern, while preserving MealRoutine's main promise: less effort deciding what to cook. It adds controllable food-pattern preferences and simple, explainable variety. It does not turn MealRoutine into a medical nutrition tracker or grocery-price application.

**Product promise:** “A weekly meal plan that fits the way you want to eat.”

## 2. Locked scope

### Included
- Weekly meal-pattern preference: Balanced, Vegetable-forward, Protein-forward, Plant-forward.
- Explainable plan-level variety signals based on structured recipe metadata.
- A small summary showing the plan's food-pattern mix, with unknown metadata clearly excluded from counts.
- Integration with Personal Meal Memory, household preferences/vetoes and V5 pantry signals.
- Preference editing and reset.
- First WidgetKit widget: Today's Meal.
- Tests, accessibility, stale/offline widget behavior and migration-safe defaults.

### Excluded
- Calories, macros, micronutrients and exact nutrition totals.
- Medical diets, disease-specific advice, weight-loss targets or health outcome claims.
- Claims that a plan is nutritionally complete or clinically balanced.
- Automatic nutrition inference from recipe titles or unstructured instructions.
- Nutrition API dependency in the V6 critical path.
- Market prices, budget targets, cost optimization, price history or grocery provider integration.
- AI-generated recipes or chatbot.
- Grocery List and Pantry widgets in initial V6.
- Full multi-language UI/global launch (V7).

## 3. Plan modes and exact behavior

Modes are preferences that influence ranking, not guarantees or strict dietary filters. Existing explicit exclusions and hard constraints remain authoritative.

### Balanced (default)
- Aim for variety across available structured food-group signals and recipe categories.
- Avoid unnecessary repetition using existing V2 repetition signals.
- Do not claim the plan meets a formal dietary standard.

### Vegetable-forward
- Increase ranking preference for recipes with curated/structured vegetable-forward metadata.
- Do not infer vegetable content from recipe title or cuisine name.
- Recipes with unknown classification receive no positive or negative vegetable signal.

### Protein-forward
- Increase ranking preference for recipes with a known supported protein source (`proteinId` / curated recipe classification).
- This mode does not calculate grams of protein or claim high-protein nutrition.
- Unknown protein metadata is not guessed.

### Plant-forward
- Prefer recipes explicitly classified as plant-based or plant-dominant in structured recipe metadata.
- Do not assume a recipe is plant-based based on cuisine or title.
- V6 does not promise vegan/vegetarian safety; users must use explicit ingredient exclusions and inspect recipe details.

## 4. Preference model

```text
MealPatternPreference
  id
  ownerType          user | household
  ownerId
  mode               balanced | vegetableForward | proteinForward | plantForward
  enabled            boolean
  createdAt
  updatedAt
  version
```

Rules:
- Personal preference and household preference are separate.
- If a household plan exists, a household preference affects shared-plan ranking; individual preferences remain personal signals.
- V6 does not silently copy a personal preference into household settings.
- Default is `balanced`, enabled. The user can disable the feature and return to existing V5 ranking behavior.
- Unknown enum values from newer clients are rejected or handled by explicit API version rules, never guessed.

## 5. Recipe metadata

V6 uses curated metadata, not free-text parsing. Extend the existing recipe domain only where the field does not already exist.

```text
foodGroupIds[]       // stable IDs, e.g. vegetables, legumes, grains, fruit
proteinId?           // existing stable protein ID when applicable
plantPattern         // unknown | plantBased | plantDominant | mixed | animalForward
classificationSource // curated | userConfirmed | unknown
```

- Display labels are localized separately from IDs.
- A missing value is `unknown`, not a guessed default.
- Do not duplicate existing cuisine/category/protein fields under new names.
- Manual recipe creation may let users set supported food-group/pattern metadata, but those fields are optional and must not make recipe entry burdensome.
- Built-in recipe metadata is curated and version-controlled.

## 6. Ranking integration

Apply the following priority order:
1. Explicit hard exclusions and safety/user restrictions already supported by MealRoutine.
2. Current household veto.
3. `Never Again` and strong personal dislikes.
4. Feasibility and cooking-time constraints.
5. Household compatibility and Personal Meal Memory.
6. V5 pantry-use signal.
7. V6 meal-pattern preference and plan variety.
8. Discovery and controlled repetition.

V6 is a ranking signal. It must never override a higher-priority rule. The implementation must preserve the current deterministic planner; no LLM is introduced.

### Explainability
Examples:
- “Adds more vegetable-forward meals to your week.”
- “Chosen for variety across the recipes we can classify.”
- “Protein source is recorded for this recipe.”

Do not say “meets your protein needs”, “nutritionally complete” or “healthy for your condition”. Do not expose raw scoring weights.

## 7. Plan summary UI

Add a compact “Your week at a glance” section to the existing weekly plan. Show counts only for known metadata, e.g. `Vegetable-forward: 2 meals`, `Plant-forward: 1 meal`. If data coverage is incomplete, show “Based on recipe information available” and do not present unknown meals as zero.

The summary must not use percentages that imply nutritional adequacy. It is a descriptive mix of recipe classifications, not a nutrient analysis. Keep the existing meal cards, replace flow and household decision flow intact.

## 8. Today's Meal widget

The first widget is a WidgetKit widget named **Today's Meal**.

### Small
- Today's planned dinner title.
- Recipe image when available; otherwise a stable placeholder.
- Prep time only when known.

### Medium
- Today's and tomorrow's planned dinner.
- Title, image/placeholder and known prep time.

### Behavior
- Read from the app's shared local data container/cache; never require a network request during widget rendering.
- If there is no plan, show a friendly empty state and an action to open MealRoutine.
- If cached data is stale or offline, display the last known plan without implying it is freshly synced.
- Widget taps open the relevant meal detail in the app.
- WidgetKit timelines request refreshes; exact refresh time is not guaranteed. Do not promise instant updates.
- No pantry or grocery-list widget in V6 initial release.
- Widget functionality is supplementary; the app's core plan works without adding a widget.

## 9. Data and migration

- Add only the preference model and recipe metadata fields that do not already exist.
- Use a new versioned migration; never edit already-applied migrations.
- Existing recipes migrate to `unknown` metadata, except values that can be mapped with certainty from existing structured fields. No title keyword inference.
- Existing users default to `balanced` without rewriting Meal Memory. The first launch after upgrade must not force a new onboarding flow.
- Household preference records are created only when the user explicitly enables or changes the household-level setting.
- Widget cache/schema changes must not break existing app data.

## 10. API and sync

Use existing V4.1/V5 versioning, authentication, authorization, idempotency and conflict conventions. Proposed endpoints if server-owned preferences are needed:

```text
GET   /v1/users/me/meal-pattern-preference
PATCH /v1/users/me/meal-pattern-preference
GET   /v1/households/:id/meal-pattern-preference
PATCH /v1/households/:id/meal-pattern-preference
```

- Personal endpoint requires the authenticated user identity.
- Household endpoint requires current household membership.
- Household preference writes follow existing household permission rules.
- The server validates stable enum values.
- The client does not send an authoritative computed ranking score.
- If the app architecture keeps this preference local-only initially, document that decision in code and do not create unused endpoints; however shared household preference must be server-authoritative if it affects shared plan results.

## 11. Nutrition values are deferred

V6 does not calculate calories, macros or micronutrients. Before a future nutrition-data release, a separate decision document must define source licensing, region coverage, ingredient matching, raw/cooked basis, quantity conversions, serving normalization, missing-data behavior, data freshness, rounding and user-facing disclaimers. A single national dataset must not be described as globally complete.

## 12. Privacy and user control

- Meal-pattern preference is user/household data and follows existing access-control rules.
- Do not infer medical conditions, weight goals or health status.
- Do not send recipe or preference data to an external nutrition/AI provider in V6.
- Users can change/disable the preference and delete their account under existing V4.1 rules.

## 13. Implementation order

1. Audit current recipe metadata and reuse existing fields.
2. Define stable food-group and plant-pattern enums.
3. Add migration and server validation only for missing fields.
4. Implement preference persistence and UI.
5. Integrate deterministic ranking after all existing hard constraints.
6. Add plan summary with unknown-data handling.
7. Implement Today's Meal widget and shared cache.
8. Add unit/integration tests and V1–V5 regression tests.
9. Validate VoiceOver, Dynamic Type, Dark Mode, empty/offline/stale states.
10. Update API, migration, runbook and Globalization Readiness audit.

## 14. Required tests

- Each mode ranks supported recipes as specified.
- Unknown food-group/protein/plant metadata is not guessed.
- Existing hard exclusions, `Never Again` and household veto always win.
- Existing Meal Memory behavior is unchanged when preference is disabled.
- Personal preferences are not silently copied into household preferences.
- Locale changes do not change ranking or identifiers.
- Migration preserves all V1–V5 user data.
- Shared preference authorization and conflict handling are correct.
- Widget shows empty, stale, no-image, missing-time and available-plan states.
- Widget taps open the correct meal.
- Core app planning works when widget is not installed or refreshed.
- No nutrition totals or unsupported health claims appear anywhere in V6 UI.

## 15. V6 acceptance gate

V6 is complete only when all are true:
- [ ] All four modes are implemented and user-controllable.
- [ ] Food-pattern labels rely on structured metadata.
- [ ] Unknown metadata is represented honestly.
- [ ] V1–V5 constraints and deterministic planner are preserved.
- [ ] Plan summary does not imply medical/nutritional adequacy.
- [ ] Today's Meal widget meets its empty/stale/navigation requirements.
- [ ] Migrations and API authorization tests pass.
- [ ] V1–V5 regression suite passes.
- [ ] Accessibility and offline states are checked.
- [ ] Globalization Readiness checklist is updated with verified evidence.

## 16. V6 completion outcome

MealRoutine helps the user choose a weekly plan that better matches a preferred food pattern, explains the plan mix without unsupported nutrition claims, and surfaces today's meal in a lightweight widget. It remains a personalized meal decision product—not a medical nutrition tracker, price database or grocery marketplace.
