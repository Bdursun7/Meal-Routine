# MealRoutine — V1–V5 Cross-Version Audit

**Document type:** Mandatory cross-version audit instruction  
**Applies to:** MealRoutine V1, V2, V3, V4, V4.1 and V5  
**Execution point:** After V5 implementation is complete and before V6 implementation begins  
**Status:** Required gate; do not skip

---

## 1. Purpose

Verify that the features delivered from V1 through V5 work together as one coherent application, that implementation matches the version specifications, and that the application is ready to begin V6 — Balanced Nutrition.

This is not another feature version and must not introduce new product scope. It is an audit and correction phase. Findings must be supported by the actual specifications and, wherever source access is available, the implementation, database, migrations, API contracts and tests.

## 2. When to run this audit

Run this document **now, after V5 is reported complete and before starting V6**.

Required sequence:
1. Finish and save the current Globalization Readiness V1–V6 document.
2. Run this V1–V5 Cross-Version Audit against the current specifications and the actual repository.
3. Record findings and their evidence in the audit report.
4. Fix only confirmed cross-version defects, missing requirements, data-integrity risks or blocking inconsistencies.
5. If corrections are needed, create and complete a narrowly scoped **V5.1 — Integration & Readiness Fixes** task/spec. Do not silently add those fixes to V6.
6. Re-run the failed checks and record the result.
7. Start V6 only when the exit criteria in Section 9 are met.

Do not run this audit after V6 as a substitute. V6 adds new behavior and would make it harder to identify whether a problem originated in V1–V5 or V6.

## 3. Required inputs

Collect and inspect:
- The latest approved specifications for V1, V2, V3, V4, V4.1 and V5.
- The latest Globalization Readiness V1–V6 document.
- Current application source code and project structure.
- Database schema, migrations and persistence configuration.
- API/service contracts and synchronization logic, if present.
- Existing automated tests and current test/build results.
- Any known bugs, TODOs, deferred decisions and manual test notes.

**Evidence rule:** A specification saying a feature exists is not proof that it is implemented. Mark each requirement as `Pass`, `Fail`, `Partial`, `Not implemented`, or `Not verifiable`. If repository access is unavailable, complete a document-only preliminary review but do not declare implementation readiness; request repository/source access before approving V6.

## 4. Audit procedure

For every requirement in every version:
1. Identify the source specification and exact requirement.
2. Find the implementation location (screen/view, model, service, API, database migration or test).
3. Verify the behavior in code and tests; run the relevant test where possible.
4. Check interactions with features from other versions, not only the feature in isolation.
5. Record evidence: file path/symbol, test name/output, migration, or a reproducible manual test.
6. Assign severity and an owner/action.
7. Do not mark an item `Pass` based only on a planned design or an unverified claim.

## 5. Cross-version checklist

### 5.1 V1 — Core Meal Planning
- [ ] Meal plans can be created, viewed, edited and regenerated without corrupting existing user data.
- [ ] Week boundaries and the selected planning week remain consistent across screens and persistence.
- [ ] Regeneration respects existing core preferences and does not unexpectedly erase user edits.
- [ ] Empty, loading, error and offline states are handled without crashing.

### 5.2 V2 — Personal Meal Memory
- [ ] Likes, dislikes, ratings/history and explicit “Never Again” exclusions persist correctly.
- [ ] V2 memory influences V1 plan generation and is not bypassed by regeneration.
- [ ] A user’s explicit rejection is not accidentally reintroduced by defaults, migrations or sync.
- [ ] Deleting or editing a recipe does not leave invalid history references or crash plan generation.

### 5.3 V3 — Personal Recipe Collection
- [ ] Manual recipe creation, editing, viewing and deletion work as specified.
- [ ] Ingredient quantities and units are stored as structured data, not only display strings.
- [ ] Recipe source URL, when supplied, is metadata only; automatic URL/social-media extraction is not a required dependency.
- [ ] Recipes remain usable by V1 planning and V2 memory after edits, deletes and app restarts.
- [ ] Missing or optional fields do not break older recipes or plan generation.

### 5.4 V4 — Household & Shared Planning
- [ ] Household membership, ownership and access checks prevent unauthorized reads/writes.
- [ ] Shared plan changes sync consistently across household members and devices.
- [ ] Member vetoes/preferences are respected by planning and cannot be silently overridden.
- [ ] Conflicts, duplicate actions, offline edits and retry behavior are handled predictably.
- [ ] Removing a member or leaving a household does not expose private data or orphan shared records.

### 5.5 V4.1 — Release Hardening & Account/Sync
- [ ] Authentication and account lifecycle behavior match the approved V4.1 spec.
- [ ] Sign-in, sign-out, account deletion and session expiration are handled safely.
- [ ] Server authorization is enforced independently of client-side UI restrictions.
- [ ] Sync retries are idempotent; duplicate requests do not duplicate recipes, pantry items or plan actions.
- [ ] Database migrations work from the prior released schema and preserve existing user data.
- [ ] Errors are observable enough to diagnose without exposing secrets or personal data.

### 5.6 V5 — Smart Pantry
- [ ] Pantry items have stable identities and structured quantities/units.
- [ ] Pantry stock is not silently deducted merely because a meal is planned.
- [ ] Stock deduction occurs only after the user marks a meal as cooked and confirms the deduction, according to the approved V5 behavior.
- [ ] Partial stock is handled correctly; unavailable quantities are not deducted and grocery additions are never made without the required explicit user action.
- [ ] Minimum-stock replenishment, if implemented, is opt-in as specified and idempotently updates existing grocery items rather than creating duplicates.
- [ ] Best-before and use-by concepts are not conflated. Date reminders use user-provided dates and do not make food-safety claims.
- [ ] Editing, consuming, deleting or changing a dated pantry item correctly updates/cancels related reminders.
- [ ] Pantry quantities, shopping-list actions and household synchronization remain consistent across devices.
- [ ] Pantry integration does not break meal planning when stock data is empty, stale or unavailable.
- [ ] No price/budget functionality has leaked into V5 unless explicitly approved in the V5 specification.

## 6. Cross-version integration checks

- [ ] Plan generation respects V2 preferences, V3 recipe data, V4 household constraints and V5 pantry context together.
- [ ] Pantry awareness does not silently mutate stock during plan generation.
- [ ] A meal being planned, selected, cooked or rejected has a clear, distinct state; actions in one state do not trigger another state’s side effects.
- [ ] Household users see a consistent source of truth for shared plans and pantry stock.
- [ ] All IDs and references remain stable across edits, sync, migrations and app restarts.
- [ ] Deleting or changing entities is handled safely wherever they are referenced by plans, history, recipes, pantry records or notifications.
- [ ] Repeated taps, retries and sync replay do not duplicate side effects.
- [ ] Existing user data survives upgrades and migrations.
- [ ] Localization-readiness rules are followed: stable IDs are separate from display names; units are structured; locale, country, currency, measurement system and time zone are distinct; week identity respects the user’s time zone.
- [ ] No new implementation assumes Turkey, Turkish language, TRY, metric units or a fixed time zone outside explicit migration/default settings.

## 7. Required test passes

Run the existing test suite and build checks. Add targeted tests for uncovered high-risk behavior before declaring readiness.

Minimum scenarios:
1. Create a plan, regenerate it, rate a meal and verify V2 memory affects a later plan.
2. Create a manual recipe with multiple ingredients and units, use it in a plan, edit it and verify references remain valid.
3. Use two household members on separate sessions/devices; verify plan changes, vetoes and pantry changes sync and access controls hold.
4. Plan a meal that uses pantry ingredients and verify stock does not change until the explicit cooked-and-confirmed flow.
5. Confirm a recipe needing more than available stock; verify only available stock is eligible for deduction and any shortage-to-grocery action requires explicit confirmation.
6. Trigger a minimum-stock replenishment twice and verify no duplicate grocery quantity/item is created.
7. Change or delete a pantry item with a reminder and verify the old reminder is rescheduled or cancelled correctly.
8. Upgrade a database containing representative V1–V5 user data and verify data integrity after migrations.
9. Test empty pantry, missing optional recipe fields, offline/retry conditions and duplicate submissions.
10. Verify a non-`tr-TR` locale and a non-TRY currency can be represented in the data model without changing stable IDs or breaking calculations. This is a readiness test, not a requirement to ship full localized UI in V1–V6.

Record exact commands, test names and results in the audit report. Do not claim a test passed if it was not run.

## 8. Findings and severity

Classify each finding:
- **P0 — Critical:** data loss/corruption, security/privacy breach, unauthorized household access, or unsafe irreversible side effect.
- **P1 — Blocking:** core cross-version flow broken, migration failure, sync inconsistency or a required specification not implemented.
- **P2 — Non-blocking defect:** limited defect with a reliable workaround and no data/security risk.
- **P3 — Documentation/cleanup:** wording, minor maintainability or non-blocking cleanup.

For each finding record: ID, severity, affected versions, expected behavior, actual behavior, evidence, reproduction steps, fix, regression test and status.

P0 and P1 findings must be fixed and re-tested before V6 begins. P2/P3 items may be deferred only if explicitly documented with rationale, impact, target version and acceptance criteria. A missing mandatory feature cannot be reclassified as cleanup merely to pass the gate.

## 9. V6 entry / exit gate

V6 may begin only when all conditions below are true:
- [ ] All V1–V5 specifications have been checked against implementation, or any unverified scope is explicitly disclosed and resolved before approval.
- [ ] No open P0 or P1 findings remain.
- [ ] Build and relevant test suites pass, or failures are documented and proven unrelated to V1–V5 with an agreed decision.
- [ ] Database migration and existing-data integrity checks pass.
- [ ] Cross-version meal planning, memory, recipes, household sync and pantry flows pass the required scenarios.
- [ ] All deferred P2/P3 findings have a named target version and acceptance criteria.
- [ ] The audit report contains evidence and a final decision: `PASS — V6 may start` or `FAIL — V6 blocked`.

A document-only review is **not** sufficient for `PASS — V6 may start` when implementation access is available but has not been inspected.

## 10. Deliverables

Create and keep these files together with the MealRoutine version specifications:
1. `MealRoutine_V1-V5_Cross_Version_Audit.md` — this procedure.
2. `MealRoutine_V1-V5_Cross_Version_Audit_Report.md` — completed checklist, evidence, findings, test results and final gate decision.
3. `MealRoutine_V5.1_Integration_Readiness_Fixes.md` — create only if blocking/confirmed fixes are needed; otherwise record `V5.1 not required` in the report.

Do not replace this instruction document with the completed report. The procedure is reusable; the report records the actual audit result for this release.

## 11. Final decision template

```text
Audit date:
Audited commit/branch:
Specifications reviewed:
Build result:
Test result:
Migration/data-integrity result:
Open P0 findings:
Open P1 findings:
Deferred P2/P3 findings:
Repository/code coverage limitations:
Decision: PASS — V6 may start / FAIL — V6 blocked
Decision rationale:
Auditor:
```

## 12. Explicit out-of-scope items

This audit does not implement V6 Balanced Nutrition, full V7 localization, nutrition/calorie/macronutrient calculations, grocery pricing or budget features. It only verifies the V1–V5 foundation and records readiness gaps that must be fixed before V6.


---

## 13. This repository — commands and recording rule

This section is the execution addendum for `V5-Alignment-Audit`. It does not replace sections 1–12.

**Branch under audit:** `V5-Alignment-Audit` at `1f07663`, plus the documentation commit that adds this file. Do not audit or modify `V5.0`.

**Result vocabulary for the report:** `Pass`, `Fail`, or `Not verified`, as required by `docs/v5-alignment-execution-order.md` §4.3. `Not verified` is not `Pass`. When this procedure’s labels differ: `Partial` and `Not implemented` are `Fail` if the code, SQL, or API was inspected; `Not verifiable` is `Not verified`. Doc 04’s P3 documentation items are recorded as P2 when they do not meet the P0 or P1 definitions in the execution order. A missing V5.0 feature that the aligned V5 spec explicitly excludes is not a failed implementation of that feature.

**Linux commands to run and paste into the report:**

```text
Tools/run_grocery_checks.sh
Tools/run_household_checks.sh
Tools/run_memory_checks.sh
Tools/run_pantry_domain_tests.sh
Tools/run_portion_checks.sh
Tools/run_product_gap_checks.sh
Tools/run_recipe_photo_checks.sh
Tools/run_recommender_checks.sh
cd server && npm test
```

`npm test` must be run with a real `DATABASE_URL` so Postgres integration tests, including `0012` on existing V4.1 rows, do not skip. Also run `cd server && npm run typecheck`.

**Mac-only, always `Not verified (Mac)` unless an Xcode log is attached:** `MealRoutineTests` (`PantryTests` and any SwiftUI/SwiftData target), simulator or device VoiceOver, Dynamic Type, Dark Mode, two-simulator conflict, Sign in with Apple, CloudKit, APNs, TestFlight.

**Report file:** `docs/MealRoutine_V1-V5_Cross_Version_Audit_Report.md`.

**V5.1 spec:** Create `MealRoutine_V5.1_Integration_Readiness_Fixes.md` only in execution-order step 5, and only when the report has open P0 or P1 findings. The run that adds this instruction stops before step 5 and does not create that spec.
