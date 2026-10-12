# MealRoutine V5.1 — Integration Readiness Fixes

**Status:** Closed 2026-10-12. The owner verified on a Mac: tests pass, migrations `0012`–`0015` applied, cook sheet correct, recipe hero photos load, pantry dates stable across relaunch. `AUD-V5-002` is Pass. V6 is unblocked. The two-simulator household test was not executed: Not verified, optional, non-blocking. VoiceOver, Dynamic Type, Dark Mode, OS notification delivery, APNs, and `AUD-GLOB-001` are not Pass.  
**Scope of the original note:** AUD-V5-001 and AUD-V5-002 only. Later V5.1 cook, threshold, and location work is in the audit report. This note is not a license to add V6 behavior.  
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

The 2026-10-12 owner verification closed V5.1 and unblocked V6. The audit report is the decision record. A Not verified Mac check is still not a Pass. The two-simulator household test stays Not verified and does not block V6. V6 behavior is not added by this note.
