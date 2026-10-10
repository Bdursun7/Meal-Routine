# MealRoutine V5.1 — Integration Readiness Fixes

**Status:** Implemented on `cursor/v51-integration-readiness-ef13`, not merged.  
**Scope:** AUD-V5-001 and AUD-V5-002 only. This is not a license to add V6 behavior.  
**Base:** `V5-Alignment-Audit`. `V5.0` was not modified.

The locked instruction is the attached spec `05_MealRoutine_V5.1_Integration_Readiness_Fixes`. This note records what the code does, including the exception the project owner accepted on 2026-10-10.

## AUD-V5-001

Past `useBy` reads “Girilen son tüketim tarihi geçti”. Past `bestBefore` reads “Girilen tavsiye edilen tüketim tarihi geçti”. The form footer tells the user to pick the date kind printed on the package and to enter that day as written. Client and server comments describe the date kind. They do not call `useBy` the last safe day.

## AUD-V5-002

New pantry dates are `YYYY-MM-DD` from the picker through storage, display, past/today/upcoming, and the sync body. The device time zone is not used to re-read a stored instant.

SwiftData keeps `bestBefore: Date?`. That column’s type does not change, so an existing store opens. `calendarDay: String?` is a new optional column and is nil on old rows. There is no custom `VersionedSchema`. New writes set `calendarDay` and leave `bestBefore` nil.

Household rows are not converted from the old instant. `PantryCache.apply` writes the server `DATE` into `calendarDay` and clears `bestBefore`. Until that refetch, an outbound update omits `dateType` and `dateValue`, so a stale local day is not written back and the server day is not cleared.

## Accepted exception (2026-10-10)

Spec §2.5 and §4.5 say a legacy personal date must not be guessed from the current time zone when the source of the old instant is missing, and that ambiguous rows need a documented recovery. Spec §6 allows an explicit exception accepted by the project owner.

The owner accepted data loss for dogfood: do not convert legacy personal pantry dates. `LegacyPersonalPantryDateUpgrade` runs once, gated by `UserDefaults` key `mealroutine.pantry.v51.legacyPersonalDatedRowsRemoved`.

| Row | Result |
| --- | --- |
| Personal row whose date is still the old `Date` (`householdID == nil`, `bestBefore != nil`, `calendarDay == nil`) | Deleted |
| Personal row with no date | Kept. The date pair stays empty |
| Second launch | No-op. The marker is set, and a repeat of the delete rule finds nothing new to delete |
| Household row, dated or not | Untouched. The server refetch is canonical |

The acceptance-matrix row “Eski kişisel kaydın tek seferlik dönüşümü” is **removed by this accepted exception**, not converted to `2026-10-09`.

## V6

V6 does not start from this note. The audit report records Pass / Fail / Not verified. A Not verified Mac check is not a Pass.
