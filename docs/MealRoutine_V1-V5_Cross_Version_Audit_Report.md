# MealRoutine — V1–V5 Cross-Version Audit Report

**Audit date:** 2026-10-10  
**Code under test:** `V5-Alignment-Audit` `1f07663` (application and server files unchanged)  
**Docs:** `cursor/v5-alignment-docs-audit-6904`  
**Specifications reviewed:** `docs/v5-alignment-execution-order.md`, `docs/v5-smart-pantry.md` (aligned this run), `docs/globalization-readiness.md`, `docs/MealRoutine_V1-V5_Cross_Version_Audit.md`, `docs/v5-release-gate.md`, `docs/v5-local-runbook.md`, `docs/v4-household.md`, `docs/v4.1-release-hardening.md`, V1–V3 docs in `docs/`  
**Auditor:** Cursor cloud agent. No Xcode, no device.  
**Decision:** `FAIL — V6 blocked`

```text
Open P0 findings: none
Open P1 findings: AUD-V5-001, AUD-V5-002
Deferred P2 findings: AUD-DOC-001, AUD-DOC-002, AUD-DOC-003, AUD-GLOB-001
Repository limits: Mac/Xcode/device items are Not verified (Mac). V6 was not started. V5.1 spec was not created.
```

`Not verified` is not `Pass`.

## 1. Commands and output

Host: Ubuntu 24.04, x86_64. Node v22.14.0. Swift 6.0.3 (swift-6.0.3-RELEASE). PostgreSQL 16.15. `DATABASE_URL=postgres://mealroutine:mealroutine@localhost:5432/mealroutine`.

### `cd server && npm test`

```text
 RUN  v3.2.7 /workspace/server

 ✓ test/pantry.test.ts (18 tests) 406ms
 ✓ test/household.test.ts (5 tests) 176ms
 ✓ test/migration.test.ts (4 tests) 146ms
 ✓ test/observability.test.ts (5 tests) 151ms
 ✓ test/privacy.test.ts (4 tests) 148ms
 ✓ test/auth.test.ts (12 tests) 138ms
 ✓ test/pantry.integration.test.ts (2 tests) 457ms
 ✓ test/integration.test.ts (2 tests) 427ms
 ✓ test/board.test.ts (3 tests) 137ms
 ✓ test/notifications.test.ts (3 tests) 159ms
 ✓ test/migrations.test.ts (3 tests) 32ms
 ✓ test/authorization.test.ts (1 test) 84ms
 ✓ test/log.test.ts (2 tests) 96ms
 ✓ test/rateLimit.test.ts (1 test) 88ms

 Test Files  14 passed (14)
      Tests  65 passed (65)
   Start at  10:12:34
   Duration  7.01s
```

Exit 0. The log contains no `skipped` line. Postgres integration tests ran.

Verbose re-run of the migration file:

```text
✓ test/pantry.integration.test.ts > postgres pantry > applies 0012 on a V4.1 database without losing household, board or account data
✓ test/pantry.integration.test.ts > postgres pantry > enforces the pantry rules in the database and through the API
```

### `cd server && npm run typecheck`

```text
> tsc --noEmit
```

Exit 0.

### `Tools/run_*.sh`

| Script | Exit | Last line / note |
| --- | --- | --- |
| `run_grocery_checks.sh` | 0 | `grocery merge checks passed` |
| `run_household_checks.sh` | 0 | `household checks passed`. Compiler warning: `HouseholdLogicChecks.swift:119` unused `resendInvite` result. Not a test failure. |
| `run_memory_checks.sh` | 0 | `meal memory checks passed` |
| `run_portion_checks.sh` | 0 | `portion scale checks passed` |
| `run_product_gap_checks.sh` | 0 | `product gap checks passed` |
| `run_recipe_photo_checks.sh` | 0 | `recipe photos: 195 with, 130 without` |
| `run_recommender_checks.sh` | 0 | `meal recommender checks passed` |
| `run_pantry_domain_tests.sh` | 0 | `Executed 31 tests, with 0 failures` |

`testRowShowsSafetyForUseByAndQualityForBestBefore` passed. That test expects the badge prefix `Güvenlik uyarısı` (`MealRoutineTests/PantryDomainTests.swift:110`). A green run does not verify neutral copy.

## 2. Execution order §5.1–§5.4

### 5.1 Past `useBy` label

Searched Swift and TypeScript for `Güvenlik`, `Tazelik`, `güvenli`.

User-facing copies, all in `MealRoutine/Services/PantryDomain.swift`:

- Line 207: badge `Güvenlik uyarısı: son tüketim tarihi geçti` for `.pastUseBy`.
- Line 209: badge `Tazelik uyarısı: tavsiye edilen tarih geçti` for `.pastBestBefore`.
- Line 61: `PantryCopy.dateFooter` = `Son tüketim tarihi (STT) güvenlik içindir. Tavsiye edilen tüketim tarihi (TETT) tat ve tazelik içindir. ...`
- Shown from `PantryView.swift:835` (`Text(PantryCopy.dateFooter)`) and row presentation `PantryView.swift:239`.

No widget target exists. Planner copy does not use those sentences. `PantryPlanningSignal.explanation` returns `Evdeki malzemeleri kullanıyor` or `Tarihi yaklaşan malzemeyi kullanıyor` (`PantryDomain.swift:1214`). Past `useBy` is removed before scoring (`MealRecommender.swift:69`).

Comments that state a safety fact: `server/src/pantryTypes.ts:6` (`useBy` is the real last safe day); `PantryDomain.swift:89` (`useBy` is the last safe day).

**Result:** Fail. Finding `AUD-V5-001`. Code was not changed.

### 5.2 `0012_pantry` and the data model

Migration order is `0001` through `0012` (`server/db/migrations/`). `0012_pantry.sql` creates `ingredients`, `pantry_items`, `pantry_idempotency`. `pantry_items.date_value` is `DATE`. `date_type` is `bestBefore` or `useBy`. Check `pantry_items_date_pair` requires both null or both set. `unit_bucket` is generated. Unique key is `(household_id, ingredient_id, unit_bucket)`.

Server DTO `PantryItem` (`server/src/pantryTypes.ts:9`) uses `dateType` and `dateValue: string | null`. API create/patch is strict and rejects a `bestBefore` key (`server/src/app.ts:701`). `normalizeDatePair` (`server/src/pantryService.ts:384`) accepts only `YYYY-MM-DD` and does not invent a date. Postgres reads `to_char(date_value, 'YYYY-MM-DD')` (`server/src/pgPantry.ts:32`).

iOS SwiftData stores the day in `bestBefore: Date?` and the type in `dateTypeRaw` (`MealRoutine/Models/GroceryItem.swift:99`). The wire name is `dateValue` (`PantryRemoteItem`). `PantryItem.remote` formats with `PantryDay.string` (`PantryRules.swift:17`). `apply` parses with `PantryDay.date` (`PantryRules.swift:33`). Personal rows use `householdID == nil` and are not SQL rows.

Integration test `applies 0012 on a V4.1 database without losing household, board or account data` passed. There is no pantry table before `0012`, so there is no legacy pantry quantity, unit, or date to preserve. The test inserts a V4.1 household and plan, applies `0012`, and checks those counts and the plan slug `menemen` (`server/test/pantry.integration.test.ts:46`).

Household authorization: `pantry.test.ts` “returns the server version on a stale write and refuses other households”; integration test covers DB constraints and account deletion. Those tests passed. Personal-pantry device isolation is in `PantryTests.swift` (not run here) and in `PantryTransferPolicy` (`PantryDomain.swift:300`).

**Schema name alignment:** Pass for the canonical wire/SQL names `dateType` / `dateValue`.  
**Migration of existing V4.1 rows:** Pass (command above).  
**Date-only across a device timezone change:** Fail. Finding `AUD-V5-002` (P1, promoted 2026-10-10).

### 5.3 Automations the V5.0 doc must not claim

Searched for `autoAdd`, `dateReminder`, `UNCalendarNotification`, `lowStockNotification`. No matches.

| Claim in the pre-alignment v2 draft | Code |
| --- | --- |
| Auto add to grocery at minimum | No symbol. `minimumQuantity` only feeds the row badge `Azaldı` (`PantryDomain.swift:219`). |
| Low-stock notification | Server kinds are `invite`, `weekly_plan`, `meal_veto`, `meal_replacement`, `plan_finalized` (`server/src/notifications.ts:8`). |
| Date reminders (§18–§19 schedule) | No scheduler, no cancel-on-edit. |
| Cook then deduct | `WeekPlanService.markCooked` (`MealRoutine/Services/WeekPlanService.swift:582`) sets `cookedAt` and a behavior event. It does not read or write `PantryItem`. |

`reconcile-grocery` operations are `compute-missing` (no stock write), `consume`, and `restock` (`server/src/pantryService.ts:167`). Those are explicit API actions.

**Result:** Pass against the aligned V5 spec: the four automations are absent, and the spec no longer lists them as V5.0 features. The doc 04 checks “confirm deduction” and “reschedule reminder” have no V5.0 flow to execute. They are Not verified as product flows, not P1 gaps. See checklist 5.6.

### 5.4 V5 test and acceptance status

`docs/v5-release-gate.md` was not treated as fresh evidence. Each Linux row was re-run. Results are section 1. Xcode, `PantryTests`, VoiceOver, Dynamic Type, Dark Mode, and a two-simulator conflict remain **Not verified (Mac)**. The product gate in `docs/v5-smart-pantry.md` stays open because of `AUD-V5-001`, `AUD-V5-002`, and the Mac rows.

## 3. Checklist

| Item | Result | Evidence |
| --- | --- | --- |
| V1 plan create / regenerate domain | Pass | `Tools/run_recommender_checks.sh` passed. `MealRecommender.pick` (`MealRecommender.swift:129`). |
| V1 week boundary on device | Pass for Monday-start device calendar; household timezone column absent | `WeekCalendar.swift:9` uses `TimeZone.current`. See `AUD-GLOB-001`. |
| V1 empty / error / offline UI | Not verified (Mac) | SwiftUI. Not compiled here. |
| V2 Never Again hard filter | Pass | `passesFilters` requires `candidate.rating != .never` (`MealRecommender.swift:203`). `run_memory_checks.sh` passed. |
| V2 memory survives locale change | Not verified | No locale field to switch. History tables are account-scoped (`0005_personal_data.sql`). |
| V3 manual recipe, no URL scrape | Pass | `RecipeImportService.swift:360` “does not read web pages.” `run_product_gap_checks.sh` passed. |
| V3 Quick Save vs ready to plan | Not verified (Mac) | `RecipeCollectionError.incomplete` exists (`RecipeImportService.swift:348`). UI flow not run. |
| V4 membership and 403 | Pass | `npm test`: `household.test.ts`, `authorization.test.ts`, pantry 403 paths. Limit 2 is SQL (`0003_households.sql:52`). |
| V4 two-device sync | Not verified (Mac) | Server board tests passed (`board.test.ts`, `integration.test.ts`). No second device. |
| V4 veto not overridden by pantry | Pass | `testEmptyPantryKeepsTheV41PlanAndPantryNeverBeatsHardFilters` in the 31 domain tests. |
| V4.1 account delete / export | Pass | `privacy.test.ts` passed. Pantry ownership test in `pantry.test.ts` “applies ownership rules on account deletion…”. Integration test deletes pantry rows with the household. |
| V4.1 idempotent retry | Pass | Pantry create replay and reconcile replay tests passed inside `npm test`. |
| V4.1 migrations preserve prior rows | Pass | `migrations.test.ts` and both integration files passed, including `0012` on V4.1 data. |
| V4.1 real Apple / APNs | Not verified (Mac) | `authService.ts` accepts `apple` and `google`. This run used the dev sign-in in tests. |
| V5 stable id, numeric quantity, structured unit | Pass | SQL and `pantry.test.ts` “merges compatible units…”. Domain unit tests in the 31. |
| V5 plan does not change stock | Pass (code); XCTest Not verified (Mac) | `markCooked` does not reference pantry (`WeekPlanService.swift:582`). `PantryTests.testPlanningAndCookingNeverChangePantry` was not executed. |
| V5 cook-confirmation deduct | Not verified | Not a V5.0 flow. Aligned spec forbids claiming it. |
| V5 shortage not deducted; grocery add is explicit | Pass | `compute-missing` returns stored items unchanged (`pantryService.ts:176`). `pantry.test.ts` “computes missing grocery quantities without double-applying a replay” passed. |
| V5 minimum-stock replenishment twice | Not verified | Feature absent. No duplicate to assert. Absence matches the aligned spec. |
| V5 date types not conflated | Pass | `pantry.test.ts` “keeps the two date kinds apart and never invents one” passed. Domain `testUseByAndBestBeforeWarnDifferently` passed. |
| V5 past-date copy is not a safety verdict | Fail | `AUD-V5-001`. |
| V5 reminder cancel on edit/delete | Not verified | No reminder records exist. |
| V5 household pantry sync | Pass on server; client conflict UI Not verified (Mac) | Conflict `409` + `current` covered by `pantry.test.ts` and the integration stale-write assertion. |
| V5 empty pantry leaves planning | Pass | Domain test `testEmptyPantryKeepsTheV41PlanAndPantryNeverBeatsHardFilters` passed. |
| V5 no price/budget logic | Pass | No price column in `0012_pantry.sql`. No budget module under `server/src` or `MealRoutine/`. |
| IDs stable across the migration | Pass | `0012` seed `ON CONFLICT (id) DO NOTHING`. Integration test kept the V4.1 plan. |
| Non-`tr-TR` locale and non-TRY currency stored without changing ids | Fail | No such columns. `AUD-GLOB-001` (P2, V7). |
| VoiceOver, Dynamic Type, Dark Mode | Not verified (Mac) | Release-gate text describes intended row layout. Not exercised. |

## 4. Findings

### AUD-V5-001

| Field | Value |
| --- | --- |
| ID | `AUD-V5-001` |
| Version / area | V5 pantry copy |
| Class | Code contradicts the aligned spec |
| Expected | Show `bestBefore` or `useBy` and that the entered date is past. No safety or edibility verdict. Example shape: “Girilen tarih geçti”. (`docs/v5-smart-pantry.md` §6; execution order §2.2 and §5.1.) |
| Actual | `MealRoutine/Services/PantryDomain.swift:207` badge `Güvenlik uyarısı: son tüketim tarihi geçti`. Line 209 `Tazelik uyarısı: tavsiye edilen tarih geçti`. Line 61 footer says STT “güvenlik içindir”. `PantryView.swift:835` shows the footer. `PantryDomainTests.swift:110` asserts the `Güvenlik uyarısı` prefix and line 118 asserts `Tazelik uyarısı`. That test passed in this run. `server/src/pantryTypes.ts:6` and `PantryDomain.swift:89` call `useBy` the last safe day. |
| Result | Fail |
| Priority | P1 |
| Fix | In `PantryRowPresentation.make`, replace both past badges with neutral copy that keeps the date type visible and says the entered date is past. Rewrite `PantryCopy.dateFooter` so it does not say the use-by date is for safety. Point `testRowShowsSafetyForUseByAndQualityForBestBefore` at the new strings and assert the banned phrases are absent for past, today, and future `bestBefore` and `useBy`. Adjust the two “last safe day” comments to the same rule. When the strings change, update `docs/v5-release-gate.md:30` and `docs/v5-local-runbook.md:84`, which still describe the old badges as the expected behavior (`AUD-DOC-003`). Do not add reminders or stock automation. |
| Test | `Tools/run_pantry_domain_tests.sh` after the assertion update. Search the app sources for `Güvenlik uyarısı` and `güvenlik içindir`. |
| Status | Open |

### AUD-V5-002

| Field | Value |
| --- | --- |
| ID | `AUD-V5-002` |
| Version / area | V5 `dateValue` |
| Class | Code contradicts the date-only rule on one path |
| Expected | `dateValue` is a calendar day and does not move when a timezone conversion is applied. |
| Actual | SQL `date_value DATE` and API `YYYY-MM-DD` stay on that day. Integration create returned `dateValue: '2030-01-05'` unchanged. iOS cache stores `Date` and `PantryDay` uses the calendar it is given, defaulting to `.current` (`PantryDomain.swift:113`, `PantryRules.swift:17` and `:33`). Verbatim copy of `PantryDay.date` / `string`, Swift 6.0.3: Istanbul `2026-10-09` formatted in `America/Los_Angeles` prints `2026-10-08`. Same calendar round-trips `2026-10-09`. Domain test `testCalendarDaysRoundTripAndInvalidDaysAreRejected` passed for one UTC calendar. |
| Result | Fail |
| Priority | P1 |
| Fix | User decision 2026-10-10: Option A. Store the pantry date as a `YYYY-MM-DD` calendar-day value on iOS, matching server `DATE` and the API string. Migration: household cache rows are re-fetched from the server; personal rows (`householdID == nil`) are converted once at upgrade using the device timezone at that moment. Details and the test plan are in §6 and §7. Acceptance test: a date entered as `2026-10-09` stays `2026-10-09` in storage, display, sync payload, and comparisons (past/today/future) after the device timezone changes (Europe/Istanbul → America/Los_Angeles → Pacific/Auckland), for both personal (local) and household (synced) pantry, including existing cached rows. |
| Test | The acceptance test above. A Linux domain test can cover pure day conversion. SwiftData personal and household rows, and rows already cached as `Date`, need the Mac `PantryTests` path. Server `DATE` already returned `2030-01-05` unchanged in this run. |
| Status | Open |

### AUD-DOC-001

| Field | Value |
| --- | --- |
| ID | `AUD-DOC-001` |
| Version / area | Roadmap docs outside the two files this run rewrote |
| Class | Doc contradicts the aligned roadmap |
| Expected | V6 is Balanced Nutrition. V7 is Globalization & Localization. V6 is not a budget release. |
| Actual | `docs/v4.1-release-hardening.md:3` and `:518` still say `V6 Meal Budget`. `docs/v5-release-gate.md:46` says price/budget are “(V6)”. `docs/v5-smart-pantry.md` and `docs/globalization-readiness.md` no longer use the old version name. |
| Result | Fail |
| Priority | P2 |
| Fix | Edit those two leftover sentences when a later doc pass is requested. Do not start a budget feature. |
| Test | `rg "Meal Budget" docs` |
| Status | Open. Deferred to a doc pass, not V6. |

### AUD-DOC-002

| Field | Value |
| --- | --- |
| ID | `AUD-DOC-002` |
| Version / area | V4 architecture doc |
| Class | Doc contradicts code |
| Expected | Household sync matches the server that ships: versioned HTTP API and Postgres (`0003_households.sql`, `server/src/app.ts`). |
| Actual | `docs/v4-household.md:7` still specifies Sign in with Apple + CloudKit and a CloudKit share. V4.1 and the server tests implement the API. `npm test` covered household, board, and auth. |
| Result | Fail |
| Priority | P2 |
| Fix | Add a pointer at the top of `docs/v4-household.md` that V4.1 replaced CloudKit with the server in this tree, or archive the CloudKit description. Do not revive CloudKit. |
| Test | Read `docs/v4-household.md` against `server/db/migrations/0003_households.sql`. |
| Status | Open. Deferred. |

### AUD-DOC-003

| Field | Value |
| --- | --- |
| ID | `AUD-DOC-003` |
| Version / area | V5 release notes |
| Class | Doc contradicts the aligned spec; doc matches current code |
| Expected | Past-date copy is neutral (`docs/v5-smart-pantry.md` §6). |
| Actual | `docs/v5-release-gate.md:30` records the safety and freshness badges as the passing behavior. `docs/v5-local-runbook.md:84` tells the operator the same badges appear. |
| Result | Fail |
| Priority | P2 |
| Fix | Update both sentences in the same change as `AUD-V5-001`, after the strings exist. Listed in that finding’s fix. |
| Test | `rg "Güvenlik uyarısı" docs` |
| Status | Open |

### AUD-GLOB-001

| Field | Value |
| --- | --- |
| ID | `AUD-GLOB-001` |
| Version / area | Globalization checklist, V1–V5 |
| Class | Untested / not implemented against the checklist. Checklist items are targets, not claims (`docs/globalization-readiness.md` §2). |
| Expected | `locale`, `countryCode`, `currencyCode`, `measurementSystem`, and `timezone` are independent stored fields. Week boundaries use the household timezone. Domain logic does not embed `tr-TR` or TRY. |
| Actual | No migration in `server/db/migrations/` declares those columns (`rg` over `*.sql` found none). `WeekCalendar.swift:11` sets `timeZone = .current`. `Formatters.swift:27` and `WeekCalendar.swift:45` use `Locale(identifier: "tr_TR")`. `MealRecommender.swift:95` scores `trDogfoodScore`. Turkish UI copy is allowed through V6. Currency is unused, which matches “no price feature”. |
| Result | Fail |
| Priority | P2 |
| Fix | Do not add the columns in V5.1. Track for V7: separate fields, household timezone for week identity, and removal of locale-locked domain formatters where they affect stored data. |
| Test | Schema dump contains the five fields; a week-boundary test in two timezones; ingredient ids unchanged. |
| Status | Open. Deferred to V7. |

## 5. Classes

**Code contradicts the aligned doc**

- `AUD-V5-001` safety and freshness verdict copy.
- `AUD-V5-002` cached `Date` can change calendar day across timezones. Server `DATE` does not.

**Doc contradicts code**

- `AUD-DOC-002` V4 CloudKit description.
- `AUD-DOC-003` release gate and runbook still require the safety badge (they match the code and contradict the aligned spec).
- `AUD-DOC-001` leftover `V6 Meal Budget` / “bütçe (V6)” lines.

**Not verified**

- All Xcode, SwiftData, and SwiftUI tests, including `MealRoutineTests/PantryTests.swift`.
- VoiceOver, Dynamic Type, Dark Mode, two-simulator conflict.
- Real Apple, Google, APNs, CloudKit, TestFlight.
- Date-reminder reschedule and minimum-stock auto-replenish, because those flows are not in V5.0.
- Cook-confirmation deduct, because that flow is not in V5.0.
- A non-Turkish locale switch. There is no locale field.

## 6. Step 5 draft (not created)

Open P1 findings are `AUD-V5-001` and `AUD-V5-002`. Suggested title: V5.1 Integration Readiness Fixes. The spec file was not created. For `AUD-V5-002` the user chose Option A on 2026-10-10.

### AUD-V5-001

- Neutral past-date badge for `useBy` and `bestBefore`.
- Neutral `PantryCopy.dateFooter`.
- Comments at `server/src/pantryTypes.ts:6` and `MealRoutine/Services/PantryDomain.swift:89`.
- Update `PantryDomainTests` so it fails if a safety verdict returns.
- Doc sentences in `docs/v5-release-gate.md` and `docs/v5-local-runbook.md` (`AUD-DOC-003`) so they follow the new strings.

### AUD-V5-002

User decision 2026-10-10: **Option A**. Store the pantry date as a `YYYY-MM-DD` calendar-day value on iOS, matching the server `DATE` and the API string. The fixed-calendar / UTC-noon `Date` option is not chosen.

Acceptance test: a date entered as `2026-10-09` stays `2026-10-09` in storage, display, sync payload, and comparisons (past/today/future) after the device timezone changes (Europe/Istanbul → America/Los_Angeles → Pacific/Auckland), for both personal (local) and household (synced) pantry, including existing cached rows.

Today the server stores `date_value DATE` and the API sends `YYYY-MM-DD`. The iOS cache stores `bestBefore: Date?` (`MealRoutine/Models/GroceryItem.swift:99`). `PantryDay` reads and writes that instant with the calendar it is given, default `.current` (`PantryDomain.swift:113`, `PantryRules.swift:17` and `:33`). Personal rows stay on device (`householdID == nil`). Household rows sync as `dateValue`.

**Chosen storage.** The on-device value is the calendar-day string. Display, sync payload, and past/today/future use that string. A `DatePicker` may build a temporary `Date` at the UI edge from the string. Readers do not take year-month-day from `Calendar.current` applied to a stored instant. A timezone change after the string is stored does not rewrite it.

**Migration policy (user decision 2026-10-10).**

- Household pantry cache rows are re-fetched from the server. The authoritative value is the server `DATE` (`YYYY-MM-DD`). The old cached `Date` is not interpreted into the new string.
- Personal pantry rows (`householdID == nil`) are converted once at upgrade time. The converter reads the stored `Date` with the device’s current timezone at that moment and writes `YYYY-MM-DD`. Later launches do not convert again. A user who already changed timezone before this upgrade can keep the shifted day; that is the accepted policy.

**Test plan for Option A**

- Linux domain test: store `2026-10-09` as `YYYY-MM-DD`. Switch the calendar through `Europe/Istanbul`, `America/Los_Angeles`, and `Pacific/Auckland`. The stored string, the display string, and the sync `dateValue` stay `2026-10-09`. Past, today, and future against a fixed today of `2026-10-08`, `2026-10-09`, and `2026-10-10` still name that same day. Cover `bestBefore`, `useBy`, and a row with no date.
- Personal upgrade: a V5.0 `Date` written as Istanbul local midnight for `2026-10-09`, converted once while the device timezone is still `Europe/Istanbul`, becomes `2026-10-09`. A second launch in `America/Los_Angeles` or `Pacific/Auckland` leaves `2026-10-09`. The conversion does not run again.
- Household upgrade: the cache row is replaced by a server fetch. The string equals the server `DATE`, including when the device timezone at upgrade differs from the timezone that wrote the old `Date`. The sync payload sent afterward is that same `YYYY-MM-DD`.
- Mac `PantryTests` covers the SwiftData personal conversion and the household re-fetch. That part is Not verified until Xcode. Server `npm test` should stay green; the wire format is already `YYYY-MM-DD`.

Out of scope for that spec: reminders, low-stock push, auto-add to grocery, cook-deduct, nutrition, prices, version bump, V6, V7 fields, CloudKit.

P2 items stay deferred (section 4): `AUD-DOC-001`, `AUD-DOC-002`, `AUD-DOC-003`, `AUD-GLOB-001`. No P0 findings.

## 7. AUD-V5-002 decision

On 2026-10-10 the user promoted `AUD-V5-002` from P2 to P1 and chose **Option A**: store the pantry date as a `YYYY-MM-DD` calendar-day value on iOS, matching the server `DATE` and the API string.

Migration policy, same date: household pantry cache rows are re-fetched from the server (authoritative `DATE`). Personal pantry rows (`householdID == nil`) are converted once at upgrade time using the device’s current timezone at that moment. The fixed-calendar `Date` option is not chosen. The acceptance test and the Option A test plan are in §6.

## 8. Gate

V6 must not start. `AUD-V5-001` and `AUD-V5-002` are open. Mac rows are Not verified and do not count as passes. P2 items are not V6 work.

`MealRoutine_V5.1_Integration_Readiness_Fixes.md` was not added. That file belongs to execution-order step 5.
