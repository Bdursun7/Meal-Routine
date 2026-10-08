> **Status (V5.1):** V1–V5 Global Readiness Gates (§5–§10) and the existing-feature parts of the Cross-Version Audit (§29) are implemented on branch `V5.1-Globalization`; see `docs/v5.1-globalization-gate.md`. V6 (§11–§28) is not built yet. V7 is out of scope.

# MealRoutine — Globalization Readiness V1–V6

## Document Status

**Status:** Locked implementation directive  
**Purpose:** Make MealRoutine global-ready through V6 without turning V1–V6 into a full globalization release.  
**Actual globalization release:** V7 — Globalization & Localization

---

# 1. Core Decision

MealRoutine will not be built as a Turkey-only application that is later rewritten for global markets.

Instead:

> **V1–V6 = Global-ready architecture**  
> **V7 = Globalization & Localization release**

This means V1–V6 must avoid country-specific, language-specific, currency-specific, or measurement-specific assumptions in the data model and business logic.

However, V1–V6 do **not** need to support multiple countries/languages in the UI yet.

### Example

V6 may initially operate with:

- `PriceRegion = TR`
- `Currency = TRY`
- Turkish content
- Metric units

But the code must not assume:

```text
country == Turkey
currency == TRY
language == Turkish
measurement == metric
```

as permanent truths.

---

# 2. What Changes and What Does Not

## Changes

We will make the following global-ready foundations:

- Structured identifiers instead of display strings
- Locale abstraction
- Currency abstraction
- Measurement-system abstraction
- Unit normalization
- Ingredient identity independent of language
- Localized display names
- Region-aware price data
- Timezone-aware date/time handling
- Server-side country/region awareness
- Language-independent recommendation logic
- Language-independent cost calculations
- Global-safe recipe and pantry models

## Does NOT change

We do not add these to V1–V6 just for globalization:

- Multiple language UI
- Multiple-country onboarding
- Global launch
- Market integrations
- Global grocery providers
- Automatic translation of all recipe content
- International price databases
- Country-specific tax engines
- Global payment systems
- Region-specific legal flows beyond what V4.1 already requires

Those belong to V7.

---

# 3. Global Architecture Principle

The application must follow this rule:

> **Data and business logic use stable identifiers and normalized values. UI decides how those values are displayed.**

Bad:

```text
ingredientName = "Domates"
currency = "₺"
unit = "kg"
country = "Türkiye"
```

Good:

```text
ingredientId = tomato
quantity = 500
unit = g

currencyCode = TRY
regionCode = TR
locale = tr-TR
measurementSystem = metric
```

The user interface can then display:

```text
500 g Domates
```

or later:

```text
500 g Tomato
```

without changing the underlying data.

---

# 4. Globalization Foundations

These concepts must remain separate.

## 4.1 Locale

Example:

```text
tr-TR
en-US
en-GB
de-DE
fr-FR
```

Locale controls:

- UI language
- number formatting
- date formatting
- decimal separators
- localized text presentation

Locale does NOT define currency by itself.

---

## 4.2 Country / Region

Country/region represents where the user/household operates.

Examples:

```text
TR
US
GB
DE
FR
```

A region may later become more detailed where required.

Do not assume:

```text
locale == country
```

---

## 4.3 Currency

Currency is independent.

Examples:

```text
TRY
USD
EUR
GBP
```

Store currency as an ISO-style code, not as a symbol.

Good:

```text
amount = 250
currencyCode = TRY
```

Bad:

```text
amount = "₺250"
```

---

## 4.4 Measurement System

At minimum:

```text
metric
imperial
```

Do not infer measurement system from language.

---

## 4.5 Timezone

Store timestamps server-side in UTC.

User/household timezone controls display and week boundaries.

Example:

```text
Europe/Istanbul
America/New_York
America/Los_Angeles
Europe/London
```

Do not use device-local time as the authoritative server timestamp.

---

# 5. V1 — Global-Ready Core Meal Planning

V1 is already complete, so these are **global-readiness audit tasks**, not a new V1 feature release.

## Step 1 — Recipe ingredients

Recipe ingredient records must use:

```text
ingredientId
quantity
unit
```

Never use ingredient display name as identity.

Example:

```text
ingredientId = tomato
quantity = 500
unit = g
```

---

## Step 2 — Recipe categories

Categories, proteins, cuisines, meal types, etc. must use stable IDs.

Example:

```text
cuisineId = turkish
proteinId = chicken
mealTypeId = dinner
```

The UI displays the localized name.

---

## Step 3 — Built-in recipe content

Existing V1 recipes may remain Turkish.

However:

- recipe identity must be language-independent
- ingredient identity must be language-independent
- category identity must be language-independent
- units must be structured

Do not store Turkish words as the only canonical identity.

---

## Step 4 — User preferences

Preferences must reference IDs where possible.

Do not build recommendation logic around strings such as:

```text
"tavuk"
"Türk mutfağı"
"akşam yemeği"
```

Use stable IDs.

---

## Step 5 — Localization strings

All user-facing UI strings should use localization keys.

Example:

```text
this_week
recipes
grocery
profile
favorite
replace_meal
```

Do not hardcode user-facing English/Turkish text directly inside business logic.

---

## V1 Global Readiness Gate

Before V2/V3 work continues:

- [ ] Ingredient identity is structured
- [ ] Units are structured
- [ ] Recipe categories use IDs
- [ ] Recommendation rules do not depend on Turkish strings
- [ ] UI strings are localizable
- [ ] No TRY/country assumptions exist in V1 code

---

# 6. V2 — Global-Ready Personal Meal Memory

V2 behavior is already implemented. Globalization work must ensure Meal Memory is language-independent.

## Step 1 — Memory signals

Store signals using stable identifiers.

Good:

```text
ingredientId
recipeId
cuisineId
proteinId
mealTypeId
```

Bad:

```text
"chicken"
"tavuk"
"poulet"
```

---

## Step 2 — Recommendation engine

The scoring engine must never depend on UI language.

For example:

```text
Preferred protein = chicken
```

not:

```text
Preferred protein = "tavuk"
```

---

## Step 3 — Cuisine and category memory

Cuisine IDs must remain language-independent.

Example:

```text
turkish
italian
mexican
japanese
```

Display names are localized later.

---

## Step 4 — Feedback

Feedback types remain stable IDs:

```text
loved
okay
neverAgain
tooTimeConsuming
tooDifficult
portionTooSmall
portionTooLarge
missingIngredients
tooManyIngredients
```

Never store the displayed text as the business value.

---

## Step 5 — Historical data

Historical Meal Memory must remain valid after a language change.

Changing:

```text
tr-TR → en-US
```

must not change the user's recommendation history.

---

## V2 Global Readiness Gate

- [ ] Memory uses IDs
- [ ] Recommendation engine is language-independent
- [ ] Feedback types are stable identifiers
- [ ] Cuisine/protein/category memory is language-independent
- [ ] Existing Turkish user data remains valid after future locale change

---

# 7. V3 — Global-Ready Personal Recipe Collection

V3 is the Personal Recipe Collection version.

The existing decision remains:

> V3 does not scrape or automatically reconstruct recipes from URLs.

URLs are sources only.

## Step 1 — Recipe source

Store:

```text
sourceType
sourceURL
sourceTitle
savedAt
```

`sourceType` must be an enum/stable identifier.

Example:

```text
instagram
tiktok
youtube
website
whatsapp
photo
manual
```

Do not use localized text as the source identity.

---

## Step 2 — Recipe ingredient model

Every ingredient must use:

```text
ingredientId
quantity
unit
```

Do not use:

```text
"2 cups flour"
```

as the canonical structured value.

---

## Step 3 — User-entered text

Free-form recipe notes/instructions can remain user text.

They are content, not business identifiers.

The system must not assume they are English or Turkish.

---

## Step 4 — Recipe serving count

Use numeric values:

```text
servings = 4
```

Do not store:

```text
"4 kişilik"
```

as the canonical value.

---

## Step 5 — Units

Units must be structured.

Initial normalized units should support the existing product needs, with the architecture able to add:

```text
g
kg
ml
l
piece
tsp
tbsp
cup
oz
lb
package
can
bottle
```

Do not implement every unit conversion in V3 unless needed by current product behavior.

The important requirement is that the model does not prevent them later.

---

## Step 6 — Recipe titles

Recipe title is user content.

It may be:

```text
Beyti Sarma
Beyti
Homemade Beyti
```

and does not need to be translated automatically.

The system must distinguish:

> user content

from:

> system-controlled localized labels.

---

## V3 Global Readiness Gate

- [ ] Recipe source types are IDs
- [ ] Ingredient identity is structured
- [ ] Quantities are numeric
- [ ] Units are structured
- [ ] Serving count is numeric
- [ ] User text is treated as content
- [ ] No URL scraping architecture is introduced

---

# 8. V4 — Global-Ready Household & Shared Planning

V4 introduces backend, authentication, household and synchronization.

This is where global identity/context must become explicit.

## Step 1 — User settings

Create/retain a structured settings model:

```text
locale
countryCode
currencyCode
measurementSystem
timezone
```

These values are independent.

---

## Step 2 — Household settings

Household should have its own regional context where appropriate.

Minimum:

```text
currencyCode
measurementSystem
timezone
countryCode
```

The household context is important for:

- shared budget later
- dates/week boundaries
- units
- shared display

---

## Step 3 — Authentication identity

Authentication providers remain independent of locale.

Existing provider model:

```text
User
AuthIdentity
```

continues.

Never use email domain, country, language, or provider to infer localization rules.

---

## Step 4 — Weekly plan

Week boundaries must be timezone-aware.

A week must not be calculated simply from server UTC.

Example:

```text
household.timezone
→ local week start
→ server stores canonical UTC timestamps
```

---

## Step 5 — Household reactions

Reaction values remain stable:

```text
want
okay
veto
```

No localized strings in the database.

---

## Step 6 — Household recommendations

Compatibility scoring must remain language-independent.

The same household behavior must produce the same recommendation regardless of UI language.

---

## V4 Global Readiness Gate

- [ ] User locale is separate from country
- [ ] Currency is separate from locale
- [ ] Measurement system is separate from locale
- [ ] Timezone is explicit
- [ ] Household has regional context
- [ ] Week calculations are timezone-aware
- [ ] Reactions use stable IDs
- [ ] Recommendation logic is language-independent

---

# 9. V4.1 — Globalization Infrastructure Hardening

V4.1 is already the production-hardening release. Global-readiness foundations belong here.

## Step 1 — Database fields

Use explicit codes:

```text
locale
countryCode
currencyCode
measurementSystem
timezone
```

Do not use free-form names.

---

## Step 2 — API contracts

API models must transport structured codes.

Example:

```json
{
  "locale": "tr-TR",
  "countryCode": "TR",
  "currencyCode": "TRY",
  "measurementSystem": "metric",
  "timezone": "Europe/Istanbul"
}
```

---

## Step 3 — Server validation

Server validates:

- supported locale
- supported currency
- supported measurement system
- valid timezone
- valid country/region code

Unsupported values must fail deterministically.

---

## Step 4 — Data migration

Existing V1–V3 users need deterministic defaults.

For the current Turkey-first release:

```text
countryCode = TR
currencyCode = TRY
measurementSystem = metric
locale = tr-TR
timezone = existing user/device timezone where safely available
```

These are migration defaults, not permanent architectural assumptions.

---

## Step 5 — UTC timestamps

All server timestamps remain UTC.

UI converts them to the relevant user/household timezone.

---

## Step 6 — Week identity

Shared weekly data must have a deterministic week identity that accounts for household timezone.

Do not identify a week using a raw server UTC date alone.

---

## Step 7 — Analytics

Analytics event names remain language-independent.

Do not send localized labels as event identities.

Avoid sending:

- recipe titles
- ingredient names
- budget amounts
- individual prices

unless explicitly required by a future analytics decision.

---

## Step 8 — Error handling

Server error codes must be stable.

Example:

```text
invalid_currency
unsupported_locale
invalid_measurement_system
invalid_timezone
```

The client maps them to localized messages later.

---

## V4.1 Global Readiness Gate

- [ ] Locale/country/currency/unit/timezone are structured
- [ ] API contracts use codes
- [ ] Server validates codes
- [ ] Existing data has deterministic migration defaults
- [ ] UTC is authoritative for timestamps
- [ ] Weekly boundaries are timezone-aware
- [ ] Analytics are language-independent
- [ ] Error codes are localization-safe

---

# 10. V5 — Global-Ready Smart Pantry

V5 is particularly important because pantry, grocery and recipes meet.

## Step 1 — Ingredient identity

The V5 rule remains locked:

> `ingredientId` is the canonical identity.

Display name is never identity.

---

## Step 2 — Ingredient names

Ingredient dictionary must support localized names.

Conceptually:

```text
Ingredient
  id = tomato

IngredientName
  ingredientId
  locale
  displayName
```

Example:

```text
tomato
tr-TR → Domates
en-US → Tomato
de-DE → Tomate
```

---

## Step 3 — Aliases

Aliases must also be locale-aware.

Example:

```text
ingredientId = eggplant

tr-TR:
patlıcan

en-US:
eggplant

en-GB:
aubergine
```

Do not automatically merge ingredients solely because names look similar.

---

## Step 4 — Units

Pantry quantities remain:

```text
quantity
unit
```

with deterministic normalization.

Examples:

```text
500 g
1 kg
1 L
2 pieces
```

---

## Step 5 — Measurement system

Display can later convert:

```text
metric ↔ imperial
```

but the canonical storage must remain deterministic.

Do not store:

```text
"about one pound"
```

as the canonical quantity.

---

## Step 6 — Pantry date semantics

Existing V5 rules remain:

```text
bestBefore
useBy
```

No automatic food-safety judgment.

Dates are timezone-aware in display.

---

## Step 7 — Grocery reconciliation

Ingredient matching must happen by `ingredientId`.

Never compare:

```text
"tomato"
"domates"
"Tomate"
```

as raw strings.

---

## Step 8 — Household pantry

Household pantry remains server-authoritative.

Regional context must not change ownership rules.

---

## V5 Global Readiness Gate

- [ ] Ingredient IDs are global
- [ ] Ingredient display names are locale-aware
- [ ] Aliases are locale-aware
- [ ] Pantry quantities are structured
- [ ] Grocery matching uses ingredient IDs
- [ ] Unit normalization is deterministic
- [ ] Date display is timezone-aware
- [ ] No language-specific pantry logic exists

---

# 11. V6 — Global-Ready Meal Budget

V6 must be redesigned from the previous Turkey-only assumption.

## 11.1 Core Product Decision

V6 is:

> **A market-independent budget and estimated meal-cost engine.**

It is NOT:

- a Migros app
- a grocery marketplace
- a market comparison app
- a personal finance app
- a receipt tracker
- a real-time price tracker

---

# 12. V6 Budget Model

Budget belongs to the household.

Minimum:

```text
BudgetSettings
  householdId
  weeklyTarget
  currencyCode
  createdAt
  updatedAt
  version
```

### Locked change

Remove:

```text
TRY only
```

from V6.

V6 must support a currency abstraction from day one, even if the first production dataset is only TR/TRY.

---

# 13. V6 Price Model

The price model must be region-aware.

Do not create a single global:

```text
tomato = 85
```

record.

Use:

```text
ingredientId
regionCode
currencyCode
price
quantity
unit
observedAt
sourceType
confidence
```

Conceptually:

```text
Tomato
TR → TRY → 85 / kg

Tomato
US → USD → 2.50 / lb

Tomato
DE → EUR → 3.00 / kg
```

---

# 14. V6 Price Sources

V6 must NOT depend on a single market.

The architecture should support multiple source types.

Initial source types:

```text
reference
userOverride
householdObserved
```

Future sources may be added in V7 without changing the cost engine.

The first V6 implementation may use a Turkey reference dataset, but:

> Turkey must be represented as data, not as business logic.

---

# 15. V6 User Price Entry

The user must NOT be required to enter product prices.

This is a locked product decision.

Bad flow:

```text
Set budget
→ Enter 15 ingredient prices
→ See budget
```

Correct flow:

```text
Set budget
→ MealRoutine estimates cost
→ User can optionally correct a price
```

User price correction is a personalization feature, not a mandatory setup task.

---

# 16. V6 Price Reference

MealRoutine needs a central reference-price layer.

Concept:

```text
PriceReference
  ingredientId
  regionCode
  currencyCode
  price
  quantity
  unit
  sourceType
  observedAt
  confidence
```

The first dataset can be Turkey-focused.

However, no code may assume:

```text
TR
TRY
metric
```

as universal values.

---

# 17. V6 Cost Engine

The cost engine must be completely independent of UI language.

Pipeline:

```text
Weekly Plan
    ↓
Recipes
    ↓
Ingredient IDs
    ↓
Pantry
    ↓
Missing quantities
    ↓
Package normalization
    ↓
Regional price reference
    ↓
Currency
    ↓
Estimated purchase cost
```

---

# 18. V6 Consumption Cost vs Purchase Cost

This distinction remains mandatory.

### Consumption cost

Value of the exact quantity used.

Example:

```text
500 g cheese
```

### Purchase cost

What the user needs to actually buy.

Example:

```text
500 g required
500 g package = ₺120

Purchase cost = ₺120
```

Budget uses **purchase cost**.

---

# 19. V6 Currency Rules

Never embed currency symbols in business logic.

Store:

```text
amount
currencyCode
```

Display:

```text
₺1.200
$42.50
€38.00
```

through locale-aware formatting.

Do not manually format decimal separators.

---

# 20. V6 Measurement Rules

Price and recipe quantities must use structured units.

Example:

```text
price = 85
currency = TRY
quantity = 1
unit = kg
```

The cost engine converts compatible units deterministically.

Do not automatically convert incompatible units.

Example:

```text
kg ↔ g
L ↔ ml
```

are compatible.

But:

```text
piece ↔ g
```

requires ingredient-specific conversion data and must not be guessed.

---

# 21. V6 Budget Optimization

Budget optimization remains the main V6 differentiator.

User explicitly chooses:

> Reduce this plan to fit my budget.

The optimizer can use:

```text
Personal Meal Memory
+
Household Compatibility
+
Pantry Utility
+
Current Constraints
+
Budget Fit
-
Recent Repetition
-
Veto
-
Never Again
```

Budget mode is explicit.

MealRoutine must never silently make meals cheaper.

---

# 22. V6 Price Confidence

Every estimate should carry enough metadata to determine whether it is reliable.

At minimum:

```text
observedAt
sourceType
confidence
```

UI can later say:

```text
≈ Estimated
Updated recently
Price unavailable
```

Never present an approximate reference price as an exact market price.

---

# 23. V6 Missing Price

If an ingredient has no usable regional price:

```text
Price unavailable
```

Do not:

- invent a price
- silently use another country's price
- silently use another currency
- silently use an unrelated ingredient
- pretend the total is exact

The total should distinguish known and unknown cost.

---

# 24. V6 Market Independence

V6 must not require:

- Migros
- CarrefourSA
- BİM
- A101
- Şok
- any single retailer

to function.

Retailer data can be a future source, but the core cost engine must operate independently.

This allows V7 to introduce regional price sources without rewriting the budget engine.

---

# 25. V6 Data Model

Recommended core model:

```text
BudgetSettings
  id
  householdId
  weeklyTarget
  currencyCode
  createdAt
  updatedAt
  version

PriceReference
  id
  ingredientId
  regionCode
  currencyCode
  price
  quantity
  unit
  sourceType
  confidence
  observedAt
  updatedAt
  version

UserPriceOverride
  id
  householdId
  ingredientId
  regionCode
  currencyCode
  price
  quantity
  unit
  observedAt
  updatedAt
  version

PriceHistory
  id
  priceReferenceId or userPriceOverrideId
  price
  quantity
  unit
  currencyCode
  observedAt
  createdAt

WeeklyBudgetSnapshot
  id
  householdId
  weekStart
  estimatedPurchaseCost
  currencyCode
  knownCost
  unknownIngredientCount
  budgetTarget
  status
  createdAt
  version
```

The exact relational implementation may be refined during V6 implementation, but the separation between regional reference prices and household overrides is mandatory.

---

# 26. V6 API Principle

APIs must never assume TRY.

Example:

```text
GET  /v1/households/:id/budget
PATCH /v1/households/:id/budget

GET  /v1/households/:id/prices
POST /v1/households/:id/prices
PATCH /v1/households/:id/prices/:priceId
DELETE /v1/households/:id/prices/:priceId

GET /v1/households/:id/budget/weeks/:weekStart
POST /v1/households/:id/budget/weeks/:weekStart/recalculate
```

Server remains authoritative for calculated cost.

---

# 27. V6 Migration

Existing households must receive deterministic regional defaults.

For the first Turkey deployment:

```text
countryCode = TR
currencyCode = TRY
measurementSystem = metric
```

These values come from household/user settings.

They are not hardcoded into the calculation engine.

---

# 28. V6 Global Readiness Gate

Before V6 is considered complete:

### Architecture

- [ ] No TRY-only business logic
- [ ] No Turkey-only business logic
- [ ] Currency is structured
- [ ] Region is structured
- [ ] Units are structured
- [ ] Locale is separate from currency
- [ ] Measurement system is separate from locale
- [ ] Timezone is explicit

### Pricing

- [ ] Price references are region-aware
- [ ] User price entry is optional
- [ ] No single retailer dependency
- [ ] Unknown prices remain unknown
- [ ] Price source is tracked
- [ ] Price freshness is tracked

### Cost engine

- [ ] Ingredient IDs are used
- [ ] Compatible units normalize deterministically
- [ ] Package cost is separated from consumption cost
- [ ] Pantry deduction works
- [ ] Currency formatting is locale-aware
- [ ] Budget optimization is explicit

### Product

- [ ] User can use V6 without entering prices
- [ ] Budget is the primary input
- [ ] Estimated cost is clearly approximate
- [ ] Budget optimization respects Memory and household vetoes

---

# 29. Cross-Version Globalization Audit

Before moving to V7, perform one complete audit.

## Data

- [ ] No business-critical Turkish strings
- [ ] No display name used as identity
- [ ] Ingredients use stable IDs
- [ ] Recipes use stable IDs
- [ ] Categories use stable IDs
- [ ] Units are structured
- [ ] Currencies are structured
- [ ] Regions are structured
- [ ] Locales are structured
- [ ] Timezones are structured

## Business Logic

- [ ] Recommendation engine is language-independent
- [ ] Meal Memory is language-independent
- [ ] Household logic is language-independent
- [ ] Pantry logic is language-independent
- [ ] Cost engine is language-independent
- [ ] Budget engine is currency-independent
- [ ] Week calculations are timezone-aware

## UI

- [ ] Strings are localization keys
- [ ] Numbers use locale-aware formatting
- [ ] Dates use locale-aware formatting
- [ ] Currency uses locale-aware formatting
- [ ] Units are display-localizable
- [ ] Dynamic Type is preserved
- [ ] No text is embedded into images/icons

## Backend

- [ ] API uses stable codes
- [ ] Server validates locale/country/currency/unit values
- [ ] UTC is authoritative for timestamps
- [ ] Household data remains isolated
- [ ] Price data remains region-aware
- [ ] Database schema does not assume Turkey

---

# 30. What V7 Will Then Do

After V6, V7 becomes an actual globalization release rather than a large architectural rewrite.

V7 scope:

## Localization

- Multiple UI languages
- Localized system text
- Localized ingredient names
- Localized categories
- Localized onboarding
- Localized notifications
- Localized errors

## Regionalization

- Country/region selection
- Regional defaults
- Currency availability
- Measurement defaults
- Timezone handling
- Week conventions where necessary

## Food data

- Localized ingredient dictionary
- Regional aliases
- Regional cuisines
- Regional recipe content
- Country-specific food conventions

## Price data

- Regional price references
- Regional price sources
- Currency-specific reference datasets
- Country/region-specific freshness

## Launch strategy

V7 should not attempt to launch every country simultaneously.

Start with a controlled set of markets and expand based on real usage.

---

# 31. Final Roadmap

```text
V1
Core Meal Planning
    ↓
Global-ready identifiers + localization-safe UI

V2
Personal Meal Memory
    ↓
Language-independent recommendation engine

V3
Personal Recipe Collection
    ↓
Structured recipe / ingredient / unit data

V4
Household & Shared Planning
    ↓
Locale / country / currency / measurement / timezone context

V4.1
Production Hardening
    ↓
Global-safe backend, API, migration, timestamps and validation

V5
Smart Pantry
    ↓
Global ingredient identity + aliases + unit normalization

V6
Meal Budget
    ↓
Region-aware pricing
    ↓
Currency abstraction
    ↓
Market-independent cost engine
    ↓
Budget optimization

V7
Globalization & Localization
    ↓
Languages
    ↓
Regional food data
    ↓
Regional price sources
    ↓
Global launch
```

---

# 32. Locked Principles

These rules apply to the entire project from now on:

1. **MealRoutine is not Turkey-specific.**
2. **V1–V6 are global-ready, not globally localized.**
3. **V7 is the actual globalization release.**
4. **Ingredient identity is never a display string.**
5. **Locale, country, currency, measurement system and timezone are separate concepts.**
6. **Currency is stored as a code, never as a symbol.**
7. **Quantities and units are structured.**
8. **Business logic never depends on UI language.**
9. **Meal Memory and recommendation logic are language-independent.**
10. **Pantry and grocery matching use ingredient IDs.**
11. **V6 does not require users to enter prices.**
12. **V6 does not depend on a single retailer.**
13. **V6 price references are region-aware.**
14. **V6's first region may be Turkey, but Turkey is configuration/data, not business logic.**
15. **Approximate price must always be presented as approximate.**
16. **Unknown price must remain unknown.**
17. **V6 budget optimization is explicit, never silent.**
18. **Server timestamps are UTC; display uses user/household timezone.**
19. **Existing V1–V5 product scope remains intact; globalization work is primarily architectural/readiness work.**
20. **No V7 implementation begins until the V6 Global Readiness Gate and Cross-Version Globalization Audit pass.**
