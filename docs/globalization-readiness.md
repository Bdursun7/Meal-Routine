# MealRoutine — Globalization Readiness V1–V6

**Status:** Locked architecture directive and audit checklist  
**Scope:** V1–V6 global-ready foundations; V7 is the actual globalization/localization release.  
**Roadmap:** V1 Core Meal Planning → V2 Personal Meal Memory → V3 Personal Recipe Collection → V4 Household & Shared Planning → V4.1 Release Hardening → V5 Smart Pantry → V6 Balanced Nutrition → V7 Globalization & Localization

## 1. Purpose and product decision

MealRoutine must not be designed as a Turkey-only application that requires a data-model rewrite for global markets. V1–V6 establish language-independent identifiers, structured quantities, regional context, timezone-safe behavior and localizable UI foundations. V7 introduces the user-facing multi-locale/global launch.

**Global-ready does not mean globally launched.** Until V7, the product may ship with Turkish UI and a Turkey-first content catalogue. TR/TRY/metric/tr-TR are migration or current-release defaults only, never permanent business rules.

V6 is **Balanced Nutrition**. This document does not authorize price databases, grocery price integrations, budget targets, price history or purchase-cost optimization. Nutrition values and quantitative calorie/macro claims are also deferred; V6 focuses on meal-pattern variety and user-selected food emphasis unless reliable structured nutrition data is separately approved.

## 2. Non-negotiable global architecture rules

1. Stable IDs are canonical; localized labels are presentation only.
2. Locale, country/region, currency, measurement system and timezone are independent fields.
3. Quantities are numeric and units are structured. Never parse display strings as canonical data.
4. Dates, timestamps and weekly boundaries use explicit semantics and timezone rules.
5. User-authored recipe names, instructions and notes are content; do not silently translate or overwrite them.
6. Recommendation and scoring logic must not branch on UI language or translated names.
7. Unsupported or unknown values are handled explicitly; the system must not invent data.
8. Existing user data must survive locale changes and migrations without changing identity or history.
9. Every completed-version section below is an audit checklist, not a claim that the current code has passed it. Mark an item complete only after code/test evidence.

## 3. Distinct regional concepts

```text
locale             tr-TR, en-US, en-GB, de-DE
countryCode        TR, US, GB, DE
currencyCode       TRY, USD, GBP, EUR
measurementSystem  metric, imperial, usCustomary (only if explicitly supported)
timezone           Europe/Istanbul, America/New_York
````

- Locale controls language and number/date formatting; it does not determine currency.
- Country/region represents the user's or household's operating region; it does not have to equal locale.
- Currency is stored as a code, never as a symbol or formatted string. V6 has no price feature, so currency is infrastructure only.
- Measurement system is an explicit preference/context, not inferred from language.
- Server timestamps are UTC. Display and weekly boundaries use the relevant user/household timezone. Date-only concepts such as pantry dates must remain calendar dates and must not shift when converted to UTC.

## 4. Domain identity and localized labels

Use stable identifiers for `ingredientId`, `recipeId`, `categoryId`, `cuisineId`, `mealTypeId`, `proteinId`, `cookingMethodId`, `feedbackType`, `sourceType`, household reactions and statuses.

Recommended localization pattern:

```text
Ingredient(id = tomato)
IngredientName(ingredientId = tomato, locale = tr-TR, displayName = Domates)
IngredientName(ingredientId = tomato, locale = en-US, displayName = Tomato)
```

Do not use `Domates`, `Tomato` or another display label as the ingredient key. Cuisine, category, meal type, protein and cooking method are distinct dimensions. `cuisineIds[]` may contain multiple IDs for fusion recipes.

## 5. V1 — Core Meal Planning audit

V1 is complete. These are audit/cleanup criteria, not a new V1 feature release.

- Recipe ingredients use `ingredientId`, numeric `quantity` and structured `unit`.
- Category, cuisine, protein and meal-type references use stable IDs.
- Recipe identity is independent of recipe title/language.
- Preferences and recommendation rules use IDs/enums, not Turkish strings.
- UI text uses localization keys rather than literals embedded in business logic.
- Grocery aggregation operates on ingredient IDs and unit compatibility, not display-name equality.
- No TRY, Turkey, Turkish-language or metric-only assumptions are embedded in generic domain logic.

**V1 gate:** verify each item in code; record any required fixes in the cross-version audit.

## 6. V2 — Personal Meal Memory audit

- Memory references stable recipe/ingredient/cuisine/protein/category IDs.
- Feedback values remain stable enums such as `loved`, `okay`, `neverAgain`, `tooTimeConsuming`, `tooDifficult`, `portionTooSmall`, `portionTooLarge`, `missingIngredients`, `tooManyIngredients`.
- Explicit feedback remains stronger than inferred behavior. `Never Again` remains a hard exclusion independent of locale.
- Scoring and recommendation explanations are based on domain signals, not translated text.
- Locale changes do not reset or rewrite history.
- User-authored notes remain unchanged unless the user edits them.

**V2 gate:** test that identical data produces identical ranking inputs across UI locales.

## 7. V3 — Personal Recipe Collection audit

- Share source is a stable enum such as `instagram`, `tiktok`, `youtube`, `website`, `whatsapp`, `photo`, `manual`.
- URLs are source metadata only; V3 does not scrape URLs or reconstruct recipe content automatically.
- Recipe ingredients, quantities, units and serving count are structured.
- User-entered title, instructions and notes may be in any language and are not silently translated.
- Incomplete Quick Saves remain distinct from ready-to-plan recipes.
- Source URL duplicate checks do not depend on localized text.

Supported unit IDs include the units already needed by the app (for example `g`, `kg`, `ml`, `l`, `piece`, `tsp`, `tbsp`, `cup`, `oz`, `lb`, `package`, `can`, `bottle`). Do not claim conversion unless a valid conversion rule exists. Count, mass and volume are different unit families.

**V3 gate:** test manual recipes and saved sources without assuming Turkish content.

## 8. V4 — Household & Shared Planning audit

User and household regional context are separate. Preserve these fields where supported:

```text
User: locale, countryCode, measurementSystem, timezone
Household: countryCode, currencyCode, measurementSystem, timezone
```

- Authentication provider is independent of locale or country.
- Weekly plan identity and date boundaries are based on household timezone, not server UTC alone.
- Reactions (`want`, `okay`, `veto`) and plan/meal statuses are stable values.
- Personal Meal Memory and shared household signals remain separate data domains.
- Server authorization and ownership checks do not depend on language.
- Household activity timestamps are stored in UTC and displayed in the relevant timezone.

**V4 gate:** test weekly boundary behavior across at least two timezones and verify that localized UI does not change server state.

## 9. V4.1 — Release hardening and regional defaults

V4.1 is the hardening and account/sync completion release. Confirm: account linking, account deletion, authorization, versioned APIs, migration safety, retry/idempotency, conflict recovery, monitoring, error/offline UX and accessibility remain correct.

- Validate locale, country, currency code, measurement system and timezone independently.
- Use structured codes in API and database contracts.
- Keep all server timestamps UTC.
- Use migration defaults only when no existing value is available: `countryCode=TR`, `currencyCode=TRY`, `measurementSystem=metric`, `locale=tr-TR`; derive timezone only from a reliable existing setting or explicit user/device choice.
- Never overwrite a user's explicit setting with a migration default.
- Account deletion and data export respect ownership boundaries.

Example API representation:

```json
{
  "locale": "tr-TR",
  "countryCode": "TR",
  "currencyCode": "TRY",
  "measurementSystem": "metric",
  "timezone": "Europe/Istanbul"
}
```

**V4.1 gate:** migration, API validation, account lifecycle and sync tests pass; regional defaults are not hard-coded into domain decisions.

## 10. V5 — Smart Pantry audit

V5 uses the same global-ready ingredient and unit system. Pantry ownership is household/server-authoritative when shared; personal local pantry does not silently merge into household pantry.

These bullets are audit targets. They are not claims that the current code has passed them, and they do not add scope to V5.0.

- Pantry records reference `ingredientId`, not localized display name.
- Quantity and unit are structured; conversion only occurs within supported compatible unit families. Language or country is not a conversion rule.
- `bestBefore` and `useBy` are distinct date types. `dateValue` is date-only (`YYYY-MM-DD` / SQL `DATE`), not a UTC instant, and must not shift by a timezone conversion. On iOS the canonical field is `calendarDay`, the same string. The old `bestBefore: Date` column remains so an existing store opens; new writes do not read a stored instant back through the device time zone. On 2026-10-10 the project owner accepted an exception to spec §2.5 / §4.5 (spec §6 “açık istisna”): legacy personal rows that still hold that `Date` are deleted once, not converted, because dogfood data loss is acceptable. Personal rows with no date stay. Household rows are not deleted and are replaced by the server `DATE`. The step is idempotent (`mealroutine.pantry.v51.legacyPersonalDatedRowsRemoved`).
- User-entered dates are never invented or inferred from country or ingredient. A date is not a food-safety decision. Past-date UI names the entered kind and that the entered day is past (`Girilen son tüketim tarihi geçti`, `Girilen tavsiye edilen tüketim tarihi geçti`). It does not use a safety or freshness verdict such as “Güvenlik uyarısı” or “Tazelik uyarısı”.
- V5.0 does not implement date reminders, low-stock notifications, or automatic add-to-grocery. Do not describe those as implemented features. If a later version adds reminders, that version must define household timezone, device notification permission, reschedule and cancel rules, idempotency, and tests. Notification copy must stay a reminder, not a food-safety guarantee.
- V5.0 does not deduct pantry stock when a meal is planned or marked cooked. Stock changes only by an explicit user action. A cook-confirmation deduct flow is not a V5.0 feature.
- `minimumQuantity` is an optional threshold on the row. In V5.0 it does not create a grocery line.
- Minimum quantities and grocery quantities use compatible units only.
- No prices, currencies, budget targets, price history or market-provider assumptions are introduced in V5.
- User-authored recipe titles, notes and instructions are not translated by pantry or planning.

**V5 gate:** verify these behaviors and all V1–V4.1 regressions before V6.

## 11. V6 — Balanced Nutrition audit

V6 adds user-controlled meal-pattern preferences, not medical nutrition or a global calorie database.

Initial plan modes/signals:

- `balanced` — variety across supported food groups and existing recipe metadata.
- `vegetableForward` — give greater preference to recipes with reliable vegetable/plant-food metadata.
- `proteinForward` — give greater preference to recipes with a supported protein source. This is a food preference, not a high-protein health claim.
- `plantForward` — prefer plant-based or plant-dominant recipes where the recipe metadata supports that classification.

Rules:

- Modes are preferences, not hard filters, unless the user explicitly sets a dietary exclusion. Allergies and medical restrictions are not inferred.
- Existing `Never Again`, household vetoes, ingredient exclusions, time limits and recipe feasibility remain higher-priority constraints.
- The planner must not label a plan “nutritionally complete”, “healthy for you”, or make calorie/macro claims without reliable recipe-level data and a separately approved calculation specification.
- No invented nutrient values. Unknown nutrition remains unknown.
- Food-group classification uses structured metadata/curated mappings, not localized recipe-title keyword matching.
- Users can change or disable the meal-pattern preference; existing memory is not rewritten.
- The first “Today's Meal” WidgetKit widget may surface the selected meal, title, image and prep time. It does not calculate nutrition and does not guarantee exact-time refresh. Widget support must not be a dependency for core planning.
- Grocery List and Pantry widgets are not part of V6 initial scope.

**V6 gate:** test each mode against representative recipes, hard constraints, missing metadata, household vetoes and V1–V5 regression. Test widget empty/loading/stale data states.

## 12. V6 deferred nutrition data policy

Quantitative nutrition is deferred to a future explicitly scoped release. Before implementation, decide: source coverage and license, regional food matching, raw-vs-cooked ingredient basis, recipe serving normalization, missing-data behavior, rounding, user-facing disclaimers and update policy. Do not treat a single country's database as globally complete.

## 13. V7 — Actual Globalization & Localization release

V7 is the release where multi-language and multi-region experience becomes a product commitment. It must include a separately scoped plan for: localized UI resources; locale-aware formatting; translated curated content; fallback language; country/region selection; measurement preferences; timezone-aware notifications; accessibility and layout expansion for longer strings; regional privacy/legal review; analytics that avoid locale assumptions; App Store metadata and support content; data migration; and rollout/QA by locale.

V7 does not automatically translate user-created recipes. User content remains as entered unless a future translation feature is explicitly designed.

## 14. Explicitly out of scope through V6

- Full multi-language UI and global launch (V7).
- Automatic translation of user-authored recipes.
- Global market-price providers, store comparison, price history or budget optimization.
- Calories/macros or medical diet recommendations in V6 initial scope.
- AI-generated recipes, ingredient inference or nutrition invention.
- Country inferred from language, currency inferred from locale, or unit system inferred from country without explicit product rules.

## 15. Cross-version audit workflow

This document defines the target architecture; it does not prove implementation compliance. Run a code-and-test audit before starting V6. Classify findings:

- **P0:** data loss, privacy/authorization flaw, wrong ingredient identity or unsafe silent mutation — fix before release.
- **P1:** global architecture blocker (localized strings used as IDs, broken unit/date semantics, migration/data incompatibility) — fix before V6.
- **P2:** non-blocking localization polish — track for V7 unless it affects data correctness.

Create a V5.1 hardening directive only if audit findings require code changes. Do not create a nominal V5.1 release solely to preserve numbering. If no blockers exist, proceed to V6.

## 16. Final acceptance checklist

- [ ] V1–V5 domain IDs and unit models reviewed in code.
- [ ] Recommendation and Meal Memory logic does not depend on localized strings.
- [ ] User content is not silently translated or overwritten.
- [ ] Locale/country/currency/measurement/timezone are separate.
- [ ] UTC timestamps and timezone-aware week boundaries are verified.
- [ ] Pantry date-only semantics are an audit target. Date-reminder rescheduling is not a V5.0 feature and must not be marked passed.
- [ ] No market-price/budget logic remains as an assumed V6 dependency.
- [ ] V6 plan modes are food-pattern preferences, not unsupported health claims.
- [ ] Nutrition calculations remain deferred until a separate data-quality decision.
- [ ] V1–V5 regression suite passes before V6 begins.
- [ ] V7 localization tasks remain explicitly assigned to V7.
