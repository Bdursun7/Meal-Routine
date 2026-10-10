import Foundation
import XCTest
@testable import MealRoutine

/// Pure V5 pantry rules. Foundation only, so this file also runs outside Xcode.
final class PantryDomainTests: XCTestCase {
    private static let dictionary: IngredientDictionary = {
        if !IngredientDictionary.shared.entries.isEmpty { return IngredientDictionary.shared }
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<4 {
            let url = directory.appendingPathComponent("MealRoutine/Recipes/ingredients.v1.json")
            if let data = try? Data(contentsOf: url), let loaded = try? IngredientDictionary(data: data) { return loaded }
            directory.deleteLastPathComponent()
        }
        return IngredientDictionary(entries: [])
    }()

    private var dictionary: IngredientDictionary { Self.dictionary }

    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }()

    private func day(_ text: String) -> Date { PantryDay.date(from: text, calendar: utc)! }

    // MARK: Dictionary

    func testDictionaryLoadsTheSeedTheServerUses() {
        XCTAssertGreaterThan(dictionary.entries.count, 300)
        XCTAssertEqual(dictionary.entry("tomato")?.name, "Domates")
        XCTAssertEqual(Set(dictionary.entries.map(\.id)).count, dictionary.entries.count)
    }

    func testCatalogIdsMeetOnOneIngredientIdOnlyWhenTheDictionarySaysSo() {
        XCTAssertEqual(dictionary.canonicalId("tomatoes"), "tomato")
        XCTAssertTrue(dictionary.sameIngredient("tomatoes", "tomato"))
        XCTAssertEqual(dictionary.canonicalId("pepper"), "blackpepper")
        XCTAssertFalse(dictionary.sameIngredient("pepper", "peppers"))
        XCTAssertFalse(dictionary.sameIngredient("cherry-tomato", "tomato"))
        XCTAssertFalse(dictionary.sameIngredient("tomatopaste", "tomato"))
    }

    func testImportedNamesResolveOnlyThroughADeclaredNameOrSynonym() {
        XCTAssertEqual(dictionary.canonicalId("import:domates"), "tomato")
        XCTAssertEqual(dictionary.canonicalId("import:iridomates"), "tomato")
        XCTAssertNil(dictionary.canonicalId("import:domatesler"))
        XCTAssertNil(dictionary.canonicalId("manual:\(UUID().uuidString)"))
        XCTAssertNil(dictionary.canonicalId("domates"))
        XCTAssertEqual(dictionary.matchKey("domates"), "unresolved:domates")
        XCTAssertFalse(dictionary.sameIngredient("domates", "domates"))
    }

    func testCustomIngredientsAreRandomAndMatchOnlyThemselves() {
        let first = IngredientDictionary.newCustomId()
        let second = IngredientDictionary.newCustomId()
        XCTAssertTrue(IngredientDictionary.isCustom(first))
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(first.contains("kestane"))
        XCTAssertEqual(dictionary.canonicalId(first.uppercased()), first)
        XCTAssertFalse(dictionary.sameIngredient(first, second))
        XCTAssertFalse(IngredientDictionary.isCustom("custom:kestane"))
        XCTAssertNil(dictionary.canonicalId("custom:kestane"))
    }

    func testSearchSuggestsButNeverDecidesIdentity() {
        let results = dictionary.search("domates")
        XCTAssertEqual(results.first?.id, "tomato")
        XCTAssertTrue(results.contains { $0.id == "cherry-tomato" })
        XCTAssertNil(dictionary.exactMatch(for: "cherry"))
        XCTAssertEqual(dictionary.exactMatch(for: "Cherry domates")?.id, "cherry-tomato")
        let custom = IngredientEntry(id: IngredientDictionary.newCustomId(), name: "Kestane")
        XCTAssertEqual(dictionary.search("kest", including: [custom]).first, custom)
    }

    func testFoldMatchesTheServerFold() {
        XCTAssertEqual(IngredientDictionary.fold("İri Domates"), "iridomates")
        XCTAssertEqual(IngredientDictionary.fold("Çarliston biber"), "carlistonbiber")
        XCTAssertEqual(IngredientDictionary.fold("  Şeker (toz) "), "sekertoz")
        XCTAssertEqual(IngredientDictionary.fold("ılık süt"), "iliksut")
    }

    // MARK: Dates

    func testUseByAndBestBeforeWarnDifferently() {
        XCTAssertEqual(PantryDateStatus.evaluate(type: .useBy, day: "2026-10-05", today: "2026-10-07"), .pastUseBy(daysAgo: 2))
        XCTAssertEqual(PantryDateStatus.evaluate(type: .bestBefore, day: "2026-10-05", today: "2026-10-07"), .pastBestBefore(daysAgo: 2))
        XCTAssertEqual(PantryDateStatus.evaluate(type: .useBy, day: "2026-10-07", today: "2026-10-07"), .approaching(daysLeft: 0))
        XCTAssertEqual(PantryDateStatus.evaluate(type: .bestBefore, day: "2026-10-10", today: "2026-10-07"), .approaching(daysLeft: 3))
        XCTAssertEqual(PantryDateStatus.evaluate(type: .bestBefore, day: "2026-10-11", today: "2026-10-07"), .upcoming(daysLeft: 4))
        XCTAssertEqual(PantryDateStatus.evaluate(type: nil, day: nil, today: "2026-10-07"), .none)
        XCTAssertNotEqual(PantryDateType.useBy.title, PantryDateType.bestBefore.title)
    }

    func testCalendarDaysRoundTripAndInvalidDaysAreRejected() {
        XCTAssertEqual(PantryDay.string(from: day("2026-02-28"), calendar: utc), "2026-02-28")
        XCTAssertNil(PantryDay.date(from: "2026-02-30", calendar: utc))
        XCTAssertNil(PantryDay.date(from: "yarın", calendar: utc))
        XCTAssertNil(PantryDay.canonical("2026-02-30"))
        XCTAssertNil(PantryDay.canonical("2026-10-09T00:00:00Z"))
        XCTAssertEqual(PantryDay.canonical("2026-10-09"), "2026-10-09")
    }

    func testCalendarDayStaysPutAcrossTimeZones() throws {
        let stored = "2026-10-09"
        let zones = ["Europe/Istanbul", "America/Los_Angeles", "Pacific/Auckland"]
        let todays = ["2026-10-08", "2026-10-09", "2026-10-10"]
        for zone in zones {
            let calendar = gregorian(zone)
            let picked = PantryDay.date(from: stored, calendar: calendar)
            XCTAssertEqual(PantryDay.string(from: try XCTUnwrap(picked), calendar: calendar), stored, zone)
            XCTAssertEqual(PantryDay.format(stored, calendar: calendar), "9 Ekim 2026", zone)
            for type in [PantryDateType.useBy, PantryDateType.bestBefore] {
                for today in todays {
                    let row = PantryRowPresentation.make(
                        name: "Süt", ingredientResolved: true, quantity: 1, unit: "l", location: .refrigerator,
                        minimumQuantity: nil, dateType: type, dateValue: stored, today: today, calendar: calendar
                    )
                    XCTAssertTrue(row.date?.contains("9 Ekim 2026") == true, "\(zone) \(type) \(today) \(row.date ?? "")")
                    XCTAssertFalse(row.date?.contains("8 Ekim") == true, zone)
                    XCTAssertFalse(row.date?.contains("10 Ekim") == true, zone)
                }
            }
            let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(datedBody(stored))) as? [String: Any]
            XCTAssertEqual(body?["dateValue"] as? String, stored, zone)
            XCTAssertEqual(PantryHouseholdDate.canonicalDay(serverDateValue: stored), stored, zone)
        }
        let istanbul = PantryDay.date(from: stored, calendar: gregorian("Europe/Istanbul"))
        let shifted = PantryDay.string(from: try XCTUnwrap(istanbul), calendar: gregorian("America/Los_Angeles"))
        XCTAssertEqual(shifted, "2026-10-08")
        XCTAssertEqual(PantryHouseholdDate.canonicalDay(serverDateValue: stored), stored)
        XCTAssertNotEqual(PantryHouseholdDate.canonicalDay(serverDateValue: stored), shifted)

        XCTAssertEqual(PantryDateStatus.evaluate(type: .useBy, day: stored, today: "2026-10-08"), .approaching(daysLeft: 1))
        XCTAssertEqual(PantryDateStatus.evaluate(type: .bestBefore, day: stored, today: "2026-10-09"), .approaching(daysLeft: 0))
        XCTAssertEqual(PantryDateStatus.evaluate(type: .useBy, day: stored, today: "2026-10-10"), .pastUseBy(daysAgo: 1))
        XCTAssertEqual(PantryDateStatus.evaluate(type: .bestBefore, day: stored, today: "2026-10-10"), .pastBestBefore(daysAgo: 1))
        XCTAssertEqual(PantryDateStatus.evaluate(type: .useBy, day: "2026-10-20", today: stored), .upcoming(daysLeft: 11))
        XCTAssertEqual(PantryDateStatus.evaluate(type: nil, day: nil, today: stored), .none)
    }

    func testLegacyPersonalDatedRowsAreRemovedOnce() {
        let personalDated = LegacyPersonalPantryDateRow(id: UUID(), isPersonal: true, hasLegacyDateInstant: true)
        let personalPlain = LegacyPersonalPantryDateRow(id: UUID(), isPersonal: true, hasLegacyDateInstant: false)
        let householdDated = LegacyPersonalPantryDateRow(id: UUID(), isPersonal: false, hasLegacyDateInstant: true)
        let householdPlain = LegacyPersonalPantryDateRow(id: UUID(), isPersonal: false, hasLegacyDateInstant: false)
        let rows = [personalDated, personalPlain, householdDated, householdPlain]
        let first = LegacyPersonalPantryDatePolicy.rowsToDelete(rows, alreadyRan: false)
        XCTAssertEqual(first, Set([personalDated.id]))
        XCTAssertFalse(first.contains(personalPlain.id))
        XCTAssertFalse(first.contains(householdDated.id))
        XCTAssertFalse(first.contains(householdPlain.id))
        let kept = rows.filter { first.contains($0.id) == false }
        XCTAssertTrue(LegacyPersonalPantryDatePolicy.rowsToDelete(kept, alreadyRan: false).isEmpty)
        XCTAssertTrue(LegacyPersonalPantryDatePolicy.rowsToDelete(rows, alreadyRan: true).isEmpty)
    }

    func testLegacyHouseholdDateIsNotWrittenBack() throws {
        let outbound = PantryOutboundDate.make(calendarDay: nil, dateType: nil, hasLegacyInstant: true)
        XCTAssertEqual(outbound, .omit)
        let omitted = PantryRemoteItem(
            id: UUID(), householdId: UUID(), ingredientId: "tomato", displayName: "Domates",
            quantity: 1, unit: "kg", location: .pantry, minimumQuantity: nil,
            dateType: outbound.dateType, dateValue: outbound.dateValue, version: 2, sendsDate: outbound.sendsDate
        )
        let patch = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(PantryItemBody.patch(omitted))) as? [String: Any])
        XCTAssertNil(patch["dateValue"])
        XCTAssertNil(patch["dateType"])
        XCTAssertEqual(PantryHouseholdDate.canonicalDay(serverDateValue: "2026-10-09"), "2026-10-09")

        let fresh = PantryOutboundDate.make(calendarDay: "2026-10-09", dateType: .useBy, hasLegacyInstant: false)
        XCTAssertEqual(fresh, .send(type: .useBy, day: "2026-10-09"))
        let cleared = PantryOutboundDate.make(calendarDay: nil, dateType: nil, hasLegacyInstant: false)
        XCTAssertEqual(cleared, .send(type: nil, day: nil))
        XCTAssertEqual(PantryDateForm.edit(authority: .legacyInstant, hasDate: false, type: .useBy, pickedDay: nil), .leave)
        XCTAssertEqual(PantryDateForm.edit(authority: .none, hasDate: false, type: .useBy, pickedDay: nil), .clear)
        XCTAssertEqual(PantryDateForm.edit(authority: .legacyInstant, hasDate: true, type: .bestBefore, pickedDay: "2026-10-09"), .set(.bestBefore, "2026-10-09"))
    }

    private func gregorian(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier) ?? utc.timeZone
        return calendar
    }

    private func datedBody(_ day: String) -> PantryItemBody {
        let item = PantryRemoteItem(
            id: UUID(), householdId: UUID(), ingredientId: "milk", displayName: "Süt",
            quantity: 1, unit: "l", location: .refrigerator, minimumQuantity: nil,
            dateType: .useBy, dateValue: day, version: 1
        )
        return PantryItemBody.create(item, confirmSeparate: false)
    }

    func testRowShowsSafetyForUseByAndQualityForBestBefore() {
        let safety = PantryRowPresentation.make(
            name: "Süt", ingredientResolved: true, quantity: 1, unit: "l", location: .refrigerator,
            minimumQuantity: nil, dateType: .useBy, dateValue: "2026-10-06", today: "2026-10-07", calendar: utc
        )
        XCTAssertEqual(safety.badges.first?.tone, .critical)
        XCTAssertEqual(safety.badges.first?.text, PantryCopy.pastUseBy)
        XCTAssertTrue(safety.date?.hasPrefix("Son tüketim tarihi (STT)") == true)

        let quality = PantryRowPresentation.make(
            name: "Makarna", ingredientResolved: true, quantity: 500, unit: "g", location: .pantry,
            minimumQuantity: nil, dateType: .bestBefore, dateValue: "2026-10-06", today: "2026-10-07", calendar: utc
        )
        XCTAssertEqual(quality.badges.first?.tone, .warning)
        XCTAssertEqual(quality.badges.first?.text, PantryCopy.pastBestBefore)
        XCTAssertTrue(quality.date?.hasPrefix("Tavsiye edilen tüketim tarihi (TETT)") == true)
        assertNoSafetyVerdict(in: [safety, quality])
    }

    /// User-facing pantry date copy only: `PantryCopy`, the two date-type titles, and the
    /// row text for both types across past, today, and later days. This is not a scan of
    /// every word that happens to contain "güven".
    func testDateCopyDoesNotReturnASafetyVerdict() {
        let phrases = [
            "Güvenlik uyarısı",
            "Tazelik uyarısı",
            "güvenlik içindir",
            "son güvenli gün",
            "last safe day",
            "bu ürün yenmez",
            "güvenli değildir",
            "güvenlidir",
            "yenilmez",
        ]
        var texts = PantryCopy.userFacing
        texts.append(contentsOf: PantryDateType.allCases.flatMap { [$0.title, $0.shortTitle] })
        let samples = ["2026-10-08", "2026-10-09", "2026-10-10", "2026-10-20"]
        for type in [PantryDateType.useBy, PantryDateType.bestBefore] {
            for sample in samples {
                let row = PantryRowPresentation.make(
                    name: "Süt", ingredientResolved: true, quantity: 1, unit: "l", location: .refrigerator,
                    minimumQuantity: nil, dateType: type, dateValue: sample, today: "2026-10-09", calendar: utc
                )
                texts.append(contentsOf: row.badges.map { $0.text })
                if let date = row.date { texts.append(date) }
                texts.append(row.accessibilityLabel)
            }
        }
        let undated = PantryRowPresentation.make(
            name: "Tuz", ingredientResolved: true, quantity: 1, unit: "kg", location: .pantry,
            minimumQuantity: nil, dateType: nil, dateValue: nil, today: "2026-10-09", calendar: utc
        )
        texts.append(contentsOf: undated.badges.map { $0.text })
        texts.append(undated.accessibilityLabel)
        for text in texts {
            for phrase in phrases {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(phrase), "\(phrase) in \(text)")
            }
        }
        XCTAssertEqual(PantryCopy.pastUseBy, "Girilen son tüketim tarihi geçti")
        XCTAssertEqual(PantryCopy.pastBestBefore, "Girilen tavsiye edilen tüketim tarihi geçti")
        XCTAssertFalse(PantryCopy.dateFooter.localizedCaseInsensitiveContains("güvenlik"))
    }

    private func assertNoSafetyVerdict(in rows: [PantryRowPresentation]) {
        let banned = ["Güvenlik uyarısı", "Tazelik uyarısı", "güvenlik içindir", "son güvenli gün"]
        for row in rows {
            let texts = row.badges.map { $0.text } + [row.date ?? "", row.accessibilityLabel]
            for text in texts {
                for phrase in banned {
                    XCTAssertFalse(text.localizedCaseInsensitiveContains(phrase), phrase)
                }
            }
        }
    }

    func testRowListsEveryGuideFieldAndSpeaksThem() {
        let row = PantryRowPresentation.make(
            name: "Un", ingredientResolved: true, quantity: 200, unit: "g", location: .pantry,
            minimumQuantity: 500, dateType: .bestBefore, dateValue: "2026-10-09", sync: .pending, today: "2026-10-07", calendar: utc
        )
        XCTAssertEqual(row.amount, "200 g")
        XCTAssertEqual(row.location, "Kiler")
        XCTAssertEqual(row.minimum, "Minimum 500 g")
        XCTAssertEqual(row.date, "Tavsiye edilen tüketim tarihi (TETT): 9 Ekim 2026 (2 gün kaldı)")
        XCTAssertEqual(row.badges.map { $0.text }, ["Tavsiye edilen tarih yaklaşıyor", PantryCopy.lowStock, PantryCopy.pending])
        for piece in ["Un", "200 g", "Kiler", "Minimum 500 g", "TETT", PantryCopy.lowStock, PantryCopy.pending] {
            XCTAssertTrue(row.accessibilityLabel.contains(piece), piece)
        }
        let plain = PantryRowPresentation.make(
            name: "Tuz", ingredientResolved: false, quantity: 0, unit: "g", location: .other,
            minimumQuantity: nil, dateType: nil, dateValue: nil, today: "2026-10-07", calendar: utc
        )
        XCTAssertNil(plain.date)
        XCTAssertEqual(plain.badges.map { $0.text }, [PantryCopy.outOfStock, PantryCopy.unmatched])
    }

    // MARK: Units and Bitti

    func testUnknownUnitsAreRejectedEvenWhenTheUserAsksForASeparateRow() {
        XCTAssertEqual(PantryUnitPolicy.decision(existingUnit: nil, existingQuantity: 0, incomingUnit: "kova", incomingQuantity: 1, confirmSeparate: true), .invalid)
        XCTAssertEqual(PantryUnitPolicy.decision(existingUnit: "g", existingQuantity: 400, incomingUnit: "piece", incomingQuantity: 2, confirmSeparate: false), .choiceRequired(existingUnit: "g"))
        XCTAssertEqual(PantryUnitPolicy.decision(existingUnit: "g", existingQuantity: 400, incomingUnit: "piece", incomingQuantity: 2, confirmSeparate: true), .separate)
        XCTAssertEqual(PantryUnitPolicy.decision(existingUnit: "g", existingQuantity: 400, incomingUnit: "kg", incomingQuantity: 1, confirmSeparate: false), .merge(quantity: 1400, unit: "g"))
        XCTAssertTrue(PantryUnitPolicy.pickerUnits.allSatisfy(PantryUnitPolicy.isKnown))
        XCTAssertEqual(Set(PantryUnitPolicy.pickerUnits), PantryUnitPolicy.knownCodes)
    }

    func testGroceryAndPantryShareTheThousandthSnap() {
        XCTAssertEqual(GroceryMerger.roundedQuantity(1.125), 1.125)
        XCTAssertEqual(GroceryMerger.roundedQuantity(0.1 + 0.2), 0.3)
        XCTAssertEqual(PantryUnitPolicy.snap(1.125), GroceryMerger.roundedQuantity(1.125))
        XCTAssertEqual(PantryUnitPolicy.snap(0.1 + 0.2), GroceryMerger.roundedQuantity(0.1 + 0.2))
        let shown = QuantityFormat.quantityAndUnit(quantity: 1.125, unit: "kg")
        XCTAssertTrue(shown == "1,125 kg" || shown == "1.125 kg", shown)
        XCTAssertEqual(GroceryQuantityEdit.parse(QuantityFormat.string(1.125)), 1.125)
        let quarter = QuantityFormat.string(1.25)
        XCTAssertTrue(quarter == "1,25" || quarter == "1.25", quarter)
        let spice = QuantityFormat.string(2 * 2.squareRoot())
        XCTAssertTrue(spice == "2,83" || spice == "2.83", spice)
    }

    func testSwitchingGramsToKilogramsKeepsTheSameStock() {
        XCTAssertEqual(PantryUnitPolicy.editedQuantity(previousQuantity: 500, previousUnit: "g", typedQuantity: 500, newUnit: "kg"), 0.5)
        XCTAssertEqual(PantryUnitPolicy.editedQuantity(previousQuantity: 500, previousUnit: "g", typedQuantity: 2, newUnit: "kg"), 2)
        XCTAssertEqual(PantryUnitPolicy.editedQuantity(previousQuantity: 500, previousUnit: "g", typedQuantity: 500, newUnit: "piece"), 500)
    }

    func testBittiOnlyZeroesAfterAChoiceAndCancelKeepsStock() {
        XCTAssertEqual(PantryFinishedFlow.quantity(current: 500, choice: nil), 500)
        XCTAssertEqual(PantryFinishedFlow.quantity(current: 500, choice: .addToMarket), 0)
        XCTAssertEqual(PantryFinishedFlow.quantity(current: 500, choice: .missingAgainstMinimum), 0)
        XCTAssertEqual(PantryFinishedFlow.quantity(current: 500, choice: .deleteItem), 0)
        XCTAssertEqual(PantryFinishedMath.shortage(quantity: 0, minimum: 2), 2)
        XCTAssertNil(PantryFinishedMath.shortage(quantity: 0, minimum: nil))
    }

    func testEditDraftLoadsTheStoredRowAndNeverSavesAnUnknownUnit() {
        let draft = PantryFormDraft.loaded(
            ingredientId: "tomatoes", name: "Domates", quantity: 500, unit: "g", location: .refrigerator,
            minimumQuantity: 100, dateType: .useBy, dateValue: "2026-10-09", dictionary: dictionary, calendar: utc
        )
        XCTAssertEqual(draft.ingredientId, "tomato")
        XCTAssertEqual(draft.quantityToSave, 500)
        XCTAssertEqual(draft.minimumText, "100")
        XCTAssertEqual(draft.dateType, .useBy)
        XCTAssertTrue(draft.hasDate)
        XCTAssertEqual(draft.pickedDay(calendar: utc), "2026-10-09")
        XCTAssertEqual(draft.dateEdit(calendar: utc), .set(.useBy, "2026-10-09"))
        XCTAssertTrue(draft.canSave)

        var blank = draft
        blank.quantityText = " "
        XCTAssertNil(blank.quantityToSave)
        XCTAssertFalse(blank.canSave)

        let legacy = PantryFormDraft.loaded(ingredientId: "domates", name: "Domates", quantity: 2, unit: "kova", location: .pantry, minimumQuantity: nil, dictionary: dictionary)
        XCTAssertNil(legacy.ingredientId)
        XCTAssertEqual(legacy.legacyUnit, "kova")
        XCTAssertEqual(legacy.unit, "")
        XCTAssertFalse(legacy.canSave, "an unknown unit still blocks save")
        var typed = legacy
        typed.unit = "piece"
        XCTAssertTrue(typed.canSave, "a typed name does not have to be picked from the list first")
        guard case .linked(let linkedTomato) = typed.resolvedIngredient(dictionary: dictionary) else {
            return XCTFail("Domates links the dictionary row on save")
        }
        XCTAssertEqual(linkedTomato.id, "tomato")
        var fixed = legacy
        fixed.choose(dictionary.entry("tomato")!, isNewCustom: false)
        fixed.unit = "piece"
        XCTAssertTrue(fixed.canSave)
        fixed.hasMinimum = true
        fixed.minimumText = "abc"
        XCTAssertFalse(fixed.canSave)
    }

    func testFreeTextLinksOneExactNameAndOtherwiseCreatesACustomIngredient() {
        guard case .linked(let tomato) = PantryIngredientMatching.resolve(typed: "domates", dictionary: dictionary) else {
            return XCTFail("domates")
        }
        XCTAssertEqual(tomato.id, "tomato")
        XCTAssertEqual(tomato.name, "Domates")

        guard case .linked(let iri) = PantryIngredientMatching.resolve(typed: "İRI DOMATES", dictionary: dictionary) else {
            return XCTFail("synonym")
        }
        XCTAssertEqual(iri.id, "tomato")

        guard case .linked(let cherry) = PantryIngredientMatching.resolve(typed: "Cherry domates", dictionary: dictionary) else {
            return XCTFail("cherry")
        }
        XCTAssertEqual(cherry.id, "cherry-tomato")
        XCTAssertNotEqual(cherry.id, tomato.id)

        guard case .linked(let paste) = PantryIngredientMatching.resolve(typed: "Domates salçası", dictionary: dictionary) else {
            return XCTFail("paste")
        }
        XCTAssertEqual(paste.id, "tomatopaste")

        guard case .createCustom(let prefix) = PantryIngredientMatching.resolve(typed: "dom", dictionary: dictionary) else {
            return XCTFail("a prefix must not auto-link")
        }
        XCTAssertEqual(prefix, "dom")

        guard case .createCustom(let fresh) = PantryIngredientMatching.resolve(typed: "Kestane şekeri", dictionary: dictionary) else {
            return XCTFail("unknown name")
        }
        XCTAssertEqual(fresh, "Kestane şekeri")
        XCTAssertNil(PantryIngredientMatching.resolve(typed: "   ", dictionary: dictionary))

        XCTAssertTrue(PantryIngredientMatching.suggestions(matching: "  ", dictionary: dictionary).isEmpty)
        let suggested = PantryIngredientMatching.suggestions(matching: "domates", dictionary: dictionary)
        XCTAssertEqual(suggested.first?.id, "tomato")
        XCTAssertTrue(suggested.contains { $0.id == "cherry-tomato" })
        XCTAssertFalse(suggested.contains { $0.id == "chicken" })

        let custom = IngredientEntry(id: "custom:11111111-1111-4111-8111-111111111111", name: "Anne tarhanası")
        guard case .linked(let kept) = PantryIngredientMatching.resolve(typed: "anne tarhanası", dictionary: dictionary, customs: [custom]) else {
            return XCTFail("household custom")
        }
        XCTAssertEqual(kept.id, custom.id)

        let shadow = IngredientEntry(id: "custom:22222222-2222-4222-8222-222222222222", name: "Domates")
        guard case .createCustom(let apart) = PantryIngredientMatching.resolve(typed: "Domates", dictionary: dictionary, customs: [shadow]) else {
            return XCTFail("two exact Domates rows must not auto-merge")
        }
        XCTAssertEqual(apart, "Domates")
        let both = PantryIngredientMatching.suggestions(matching: "Domates", dictionary: dictionary, customs: [shadow])
        XCTAssertTrue(both.contains { $0.id == "tomato" })
        XCTAssertTrue(both.contains { $0.id == shadow.id })

        let ambiguous = IngredientDictionary(entries: [
            IngredientEntry(id: "mint-a", name: "Nane"),
            IngredientEntry(id: "mint-b", name: "Nane"),
        ])
        guard case .createCustom(let nane) = PantryIngredientMatching.resolve(typed: "Nane", dictionary: ambiguous) else {
            return XCTFail("ambiguous")
        }
        XCTAssertEqual(nane, "Nane")

        var pinned = PantryFormDraft.loaded(
            ingredientId: "tomato", name: "Salkım", quantity: 1, unit: "piece", location: .refrigerator,
            minimumQuantity: nil, dictionary: dictionary
        )
        guard case .linked(let keptDisplay) = pinned.resolvedIngredient(dictionary: dictionary) else {
            return XCTFail("pinned display name")
        }
        XCTAssertEqual(keptDisplay.id, "tomato")
        XCTAssertEqual(keptDisplay.name, "Salkım")

        pinned.name = "Cherry domates"
        guard case .linked(let moved) = pinned.resolvedIngredient(dictionary: dictionary) else {
            return XCTFail("renamed to another exact ingredient")
        }
        XCTAssertEqual(moved.id, "cherry-tomato")

        pinned.choose(dictionary.entry("tomato")!, isNewCustom: false)
        pinned.name = "İri domates"
        guard case .linked(let synonym) = pinned.resolvedIngredient(dictionary: dictionary) else {
            return XCTFail("synonym of the tapped row")
        }
        XCTAssertEqual(synonym.id, "tomato")
    }

    // MARK: Market

    func testMissingAmountUsesTheDictionaryIdAcrossCatalogSpellings() {
        let lines = [PantryMarketLine(ingredientId: "tomatoes", quantity: 1, unit: "kg", isChecked: false, preserve: false)]
        let stock = [PantryCoverageLine(ingredientId: "tomato", quantity: 400, unit: "g")]
        let adjusted = PantryMarketCoverage.adjust(lines, pantry: stock, dictionary: dictionary)
        XCTAssertEqual(adjusted.first?.quantity, 0.6)
        XCTAssertEqual(adjusted.first?.applied, true)
        XCTAssertEqual(PantryMarketCoverage.adjust(lines, pantry: stock, dictionary: dictionary), adjusted)
    }

    func testSimilarNamesWithoutASharedIdAreNeverSubtracted() {
        let lines = [
            PantryMarketLine(ingredientId: "tomato", quantity: 500, unit: "g", isChecked: false, preserve: false),
            PantryMarketLine(ingredientId: "manual:\(UUID().uuidString)", quantity: 2, unit: "piece", isChecked: false, preserve: false),
        ]
        let stock = [
            PantryCoverageLine(ingredientId: "cherry-tomato", quantity: 500, unit: "g"),
            PantryCoverageLine(ingredientId: "tomatopaste", quantity: 500, unit: "g"),
            PantryCoverageLine(ingredientId: IngredientDictionary.newCustomId(), quantity: 5, unit: "piece"),
        ]
        let adjusted = PantryMarketCoverage.adjust(lines, pantry: stock, dictionary: dictionary)
        XCTAssertEqual(adjusted.map(\.quantity), [500, 2])
        XCTAssertEqual(adjusted.map(\.applied), [false, false])
        XCTAssertEqual(adjusted.map(\.incompatible), [false, false])
    }

    func testIncompatibleUnitsAndCheckedRowsStayAsWritten() {
        let lines = [
            PantryMarketLine(ingredientId: "eggs", quantity: 6, unit: "piece", isChecked: false, preserve: false),
            PantryMarketLine(ingredientId: "flour", quantity: 1, unit: "kg", isChecked: true, preserve: true),
        ]
        let stock = [
            PantryCoverageLine(ingredientId: "egg", quantity: 500, unit: "g"),
            PantryCoverageLine(ingredientId: "flour", quantity: 2, unit: "kg"),
        ]
        let adjusted = PantryMarketCoverage.adjust(lines, pantry: stock, dictionary: dictionary)
        XCTAssertEqual(adjusted[0].quantity, 6)
        XCTAssertTrue(adjusted[0].incompatible)
        XCTAssertFalse(adjusted[0].applied)
        XCTAssertEqual(adjusted[1].quantity, 1)
        XCTAssertFalse(adjusted[1].applied)
    }

    func testStockIsSharedAcrossLinesInsteadOfCountedTwice() {
        let lines = [
            PantryMarketLine(ingredientId: "tomato", quantity: 300, unit: "g", isChecked: false, preserve: false),
            PantryMarketLine(ingredientId: "tomatoes", quantity: 300, unit: "g", isChecked: false, preserve: false),
        ]
        let stock = [PantryCoverageLine(ingredientId: "tomato", quantity: 400, unit: "g")]
        let adjusted = PantryMarketCoverage.adjust(lines, pantry: stock, dictionary: dictionary)
        XCTAssertEqual(adjusted.map(\.quantity), [0, 200])
        XCTAssertEqual(adjusted.first?.coveredByPantry, true)
    }

    func testCoverageKeyIsStableSoARetryReusesTheMutation() {
        let lines = [PantryReconcileLine(ingredientId: "tomato", displayName: "Domates", quantity: 1000, unit: "g", checked: false)]
        XCTAssertEqual(PantryMarketCoverage.idempotencyKey(for: lines), PantryMarketCoverage.idempotencyKey(for: lines))
        var changed = lines
        changed[0].quantity = 900
        XCTAssertNotEqual(PantryMarketCoverage.idempotencyKey(for: lines), PantryMarketCoverage.idempotencyKey(for: changed))
    }

    // MARK: Planner

    private func candidate(_ slug: String, score: Int = 60, ingredients: Set<String>, rating: MealRating? = nil) -> PickerCandidate {
        PickerCandidate(
            slug: slug, totalMinutes: 30, trDogfoodScore: score, ingredientIds: ingredients, rating: rating,
            cuisine: "TR", category: "main", tags: [], protein: ""
        )
    }

    func testPlannerSignalUsesIdsAndExplainsItself() {
        let now = day("2026-10-07")
        let menemen = candidate("menemen", ingredients: ["tomatoes", "eggs"])
        let stock = [PantryPlanningStock(ingredientId: "tomato", quantity: 2, unit: "piece")]
        XCTAssertEqual(PantryPlanningSignal.score(candidate: menemen, stock: stock, now: now, dictionary: dictionary), 8)
        XCTAssertEqual(PantryPlanningSignal.explanation(candidate: menemen, stock: stock, now: now, dictionary: dictionary), PantryCopy.usesStock)
        let cherry = [PantryPlanningStock(ingredientId: "cherry-tomato", quantity: 2, unit: "piece")]
        XCTAssertEqual(PantryPlanningSignal.score(candidate: menemen, stock: cherry, now: now, dictionary: dictionary), 0)
        XCTAssertNil(PantryPlanningSignal.explanation(candidate: menemen, stock: cherry, now: now, dictionary: dictionary))
    }

    func testApproachingDatesSignalButAPassedUseByNeverEarnsABonus() {
        let now = day("2026-10-07")
        let menemen = candidate("menemen", ingredients: ["tomatoes"])
        let soon = [PantryPlanningStock(ingredientId: "tomato", quantity: 2, unit: "piece", dateType: .useBy, dateValue: "2026-10-08")]
        XCTAssertEqual(PantryPlanningSignal.explanation(candidate: menemen, stock: soon, now: now, calendar: utc, dictionary: dictionary), PantryCopy.approachingExpiry)
        let expired = [PantryPlanningStock(ingredientId: "tomato", quantity: 2, unit: "piece", dateType: .useBy, dateValue: "2026-10-06")]
        XCTAssertEqual(PantryPlanningSignal.score(candidate: menemen, stock: expired, now: now, calendar: utc, dictionary: dictionary), 0)
        XCTAssertNil(PantryPlanningSignal.explanation(candidate: menemen, stock: expired, now: now, calendar: utc, dictionary: dictionary))
        let stale = [PantryPlanningStock(ingredientId: "tomato", quantity: 2, unit: "piece", dateType: .bestBefore, dateValue: "2026-10-06")]
        XCTAssertEqual(PantryPlanningSignal.explanation(candidate: menemen, stock: stale, now: now, calendar: utc, dictionary: dictionary), PantryCopy.usesStock)
        let empty = [PantryPlanningStock(ingredientId: "tomato", quantity: 0, unit: "piece")]
        XCTAssertEqual(PantryPlanningSignal.score(candidate: menemen, stock: empty, now: now, dictionary: dictionary), 0)
    }

    func testEmptyPantryKeepsTheV41PlanAndPantryNeverBeatsHardFilters() {
        let now = day("2026-10-07")
        let pool = [
            candidate("a", score: 80, ingredients: ["flour"]),
            candidate("b", score: 70, ingredients: ["tomatoes"]),
            candidate("c", score: 60, ingredients: ["eggs"]),
            candidate("never", score: 99, ingredients: ["tomatoes"], rating: .never),
        ]
        let baseline = MealRecommender.pick(candidates: pool, evenings: 3, maxCookMinutes: 90, dislikedIngredientIds: [], now: now)
        XCTAssertEqual(MealRecommender.pick(candidates: pool, evenings: 3, maxCookMinutes: 90, dislikedIngredientIds: [], pantryStock: [], now: now), baseline)
        XCTAssertFalse(baseline.contains("never"))

        let stock = [PantryPlanningStock(ingredientId: "tomato", quantity: 4, unit: "piece")]
        let withPantry = MealRecommender.pick(candidates: pool, evenings: 3, maxCookMinutes: 90, dislikedIngredientIds: [], pantryStock: stock, now: now)
        XCTAssertFalse(withPantry.contains("never"))
        let vetoed = MealRecommender.pick(candidates: pool, evenings: 3, maxCookMinutes: 90, dislikedIngredientIds: [], excludingSlugs: ["b"], pantryStock: stock, now: now)
        XCTAssertFalse(vetoed.contains("b"))
        let disliked = MealRecommender.pick(candidates: pool, evenings: 3, maxCookMinutes: 90, dislikedIngredientIds: ["tomatoes"], pantryStock: stock, now: now)
        XCTAssertFalse(disliked.contains("b"))
    }

    // MARK: Wire format

    func testServerRowsDecodeWithMillisecondTimestamps() throws {
        let json = """
        {"id":"0b9c7c5e-7f43-4c1e-9d55-0d2b8f2f6a11","householdId":"6f1d2c3b-1a2b-4c5d-8e9f-001122334455","ingredientId":"tomato",
         "displayName":"Domates","quantity":400,"unit":"g","location":"refrigerator","minimumQuantity":null,
         "dateType":"useBy","dateValue":"2026-10-09","version":3,"createdAt":"2026-10-07T10:00:00.123Z","updatedAt":"2026-10-07T10:00:00.123Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let item = try decoder.decode(PantryRemoteItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.version, 3)
        XCTAssertEqual(item.dateType, .useBy)
        XCTAssertEqual(item.dateValue, "2026-10-09")
        XCTAssertEqual(item.location, .refrigerator)
        XCTAssertEqual(item.updatedAt?.timeIntervalSince1970 ?? -1, 1_791_367_200.123, accuracy: 0.000_5)
        XCTAssertEqual(item.createdAt?.timeIntervalSince1970 ?? -1, item.updatedAt?.timeIntervalSince1970 ?? -2, accuracy: 0.000_5)
    }

    func testServerTimestampsAcceptFractionPlainAndEpochAndNeverInventNow() throws {
        let fractional = try pantryRow(updatedAt: "\"2026-10-08T07:12:03.123Z\"")
        let plain = try pantryRow(updatedAt: "\"2026-10-08T07:12:03Z\"")
        let zeroFraction = try pantryRow(updatedAt: "\"2026-10-08T07:12:03.000Z\"")
        let epoch = try pantryRow(updatedAt: "1791443523123")
        XCTAssertEqual(fractional.updatedAt?.timeIntervalSince1970 ?? -1, 1_791_443_523.123, accuracy: 0.000_5)
        XCTAssertEqual(plain.updatedAt?.timeIntervalSince1970 ?? -1, 1_791_443_523, accuracy: 0.000_5)
        XCTAssertEqual(zeroFraction.updatedAt?.timeIntervalSince1970 ?? -1, plain.updatedAt?.timeIntervalSince1970 ?? -2, accuracy: 0.000_5)
        XCTAssertEqual(epoch.updatedAt?.timeIntervalSince1970 ?? -1, fractional.updatedAt?.timeIntervalSince1970 ?? -2, accuracy: 0.000_5)
        XCTAssertEqual(PantryServerClock.parse("2026-10-08T07:12:03.123Z")?.timeIntervalSince1970 ?? -1, PantryServerClock.parseEpochMilliseconds(1_791_443_523_123)?.timeIntervalSince1970 ?? -2, accuracy: 0.000_5)

        let missing = try pantryRow(updatedAt: nil)
        XCTAssertNil(missing.updatedAt)
        let stored = Date(timeIntervalSince1970: 1_700_000_000)
        let server = try XCTUnwrap(fractional.updatedAt)
        XCTAssertEqual(PantryServerClock.applying(nil, keeping: stored), stored)
        XCTAssertEqual(PantryServerClock.applying(server, keeping: stored), server)
        XCTAssertEqual(PantryServerClock.inserting(nil, createdAt: nil), Date(timeIntervalSince1970: 0))
        XCTAssertEqual(PantryServerClock.inserting(server, createdAt: nil), server)

        XCTAssertThrowsError(try pantryRow(updatedAt: "\"not-a-date\""))
        let roundTrip = try JSONDecoder().decode(PantryRemoteItem.self, from: JSONEncoder().encode(fractional))
        XCTAssertEqual(roundTrip.updatedAt?.timeIntervalSince1970 ?? -1, fractional.updatedAt?.timeIntervalSince1970 ?? -2, accuracy: 0.000_5)
    }

    func testReapplyKeepsTheIdempotencyKeyAndBothChoicesKeepTheRow() {
        let id = UUID(uuidString: "0B9C7C5E-7F43-4C1E-9D55-0D2B8F2F6A11")!
        let household = UUID(uuidString: "6F1D2C3B-1A2B-4C5D-8E9F-001122334455")!
        let key = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!
        let laterKey = UUID(uuidString: "BBBBBBBB-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!
        let mine = pantryRemote(id: id, household: household, quantity: 300, version: 3)
        let later = pantryRemote(id: id, household: household, quantity: 250, version: 4)
        let server = pantryRemote(id: id, household: household, quantity: 700, version: 5)
        let conflict = PantryConflictMutation(
            idempotencyKey: key, action: "update", householdID: household, item: mine, baseVersion: 2,
            confirmSeparate: false, serverItem: server, serverDeleted: false, rejection: nil
        )
        let alone = PantryConflictResolution.reapply([conflict])
        XCTAssertEqual(alone?.idempotencyKey, key)
        XCTAssertEqual(alone?.action, "update")
        XCTAssertEqual(alone?.baseVersion, 5)
        XCTAssertEqual(alone?.item.quantity, 300)
        XCTAssertEqual(alone?.item.version, 6)
        XCTAssertEqual(alone?.displayQuantity, 300)
        XCTAssertEqual(alone?.displayRevision, 6)
        XCTAssertEqual(alone?.confirmSeparate, false)

        let followUp = PantryConflictMutation(
            idempotencyKey: laterKey, action: "update", householdID: household, item: later, baseVersion: 2,
            confirmSeparate: false, serverItem: nil, serverDeleted: false, rejection: nil
        )
        let resolved = PantryConflictResolution.reapply([conflict, followUp])
        XCTAssertEqual(resolved?.idempotencyKey, key)
        XCTAssertNotEqual(resolved?.idempotencyKey, laterKey)
        XCTAssertEqual(resolved?.baseVersion, 5)
        XCTAssertEqual(resolved?.item.quantity, 250)
        XCTAssertEqual(resolved?.displayRevision, 6)

        let adopted = PantryConflictResolution.adoptServer([conflict])
        XCTAssertEqual(adopted?.quantity, 700)
        XCTAssertEqual(adopted?.revision, 5)
        XCTAssertNil(PantryConflictResolution.reapply([followUp]))
    }

    private func pantryRemote(id: UUID, household: UUID, quantity: Double, version: Int) -> PantryRemoteItem {
        PantryRemoteItem(
            id: id, householdId: household, ingredientId: "tomato", displayName: "Domates",
            quantity: quantity, unit: "g", location: .pantry, minimumQuantity: nil,
            dateType: nil, dateValue: nil, version: version
        )
    }

    private func pantryRow(updatedAt: String?) throws -> PantryRemoteItem {
        let clock = updatedAt.map { ",\"updatedAt\":\($0)" } ?? ""
        let json = """
        {"id":"0b9c7c5e-7f43-4c1e-9d55-0d2b8f2f6a11","householdId":"6f1d2c3b-1a2b-4c5d-8e9f-001122334455","ingredientId":"tomato",
         "displayName":"Domates","quantity":400,"unit":"g","location":"pantry","version":1\(clock)}
        """
        return try JSONDecoder().decode(PantryRemoteItem.self, from: Data(json.utf8))
    }

    func testPreGatePayloadsStillDecodeSoQueuedEditsAreNotLost() throws {
        let item = """
        {"id":"0b9c7c5e-7f43-4c1e-9d55-0d2b8f2f6a11","householdId":"6f1d2c3b-1a2b-4c5d-8e9f-001122334455","ingredientId":"tomato",
         "displayName":"Domates","quantity":1,"unit":"kg","location":"pantry","bestBefore":"2026-10-09","revision":4}
        """
        let payload = "{\"action\":\"update\",\"householdID\":\"6F1D2C3B-1A2B-4C5D-8E9F-001122334455\",\"item\":\(item),\"confirmSeparate\":false}"
        let decoded = try JSONDecoder().decode(PantryQueuedPayload.self, from: Data(payload.utf8))
        XCTAssertEqual(decoded.item?.dateType, .bestBefore)
        XCTAssertEqual(decoded.item?.dateValue, "2026-10-09")
        XCTAssertEqual(decoded.baseVersion, 4)
        let roundTrip = try JSONDecoder().decode(PantryQueuedPayload.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(roundTrip, decoded)
    }

    func testBodiesMatchTheStrictServerSchema() throws {
        let item = PantryRemoteItem(
            id: UUID(uuidString: "0B9C7C5E-7F43-4C1E-9D55-0D2B8F2F6A11")!, householdId: UUID(), ingredientId: "tomato",
            displayName: "Domates", quantity: 400, unit: "g", location: .pantry, minimumQuantity: nil,
            dateType: nil, dateValue: nil, version: 2
        )
        let allowed: Set<String> = ["id", "ingredientId", "displayName", "quantity", "unit", "location", "minimumQuantity", "autoAddToGrocery", "dateType", "dateValue", "confirmSeparate"]
        let create = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(PantryItemBody.create(item, confirmSeparate: true))) as? [String: Any])
        XCTAssertTrue(Set(create.keys).isSubset(of: allowed))
        XCTAssertEqual(create["autoAddToGrocery"] as? Bool, false)
        XCTAssertEqual(create["id"] as? String, "0b9c7c5e-7f43-4c1e-9d55-0d2b8f2f6a11")
        XCTAssertEqual(create["confirmSeparate"] as? Bool, true)
        let patch = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(PantryItemBody.patch(item))) as? [String: Any])
        XCTAssertNil(patch["id"])
        XCTAssertNil(patch["confirmSeparate"])
        XCTAssertEqual(patch["autoAddToGrocery"] as? Bool, false)
        let legacy = try pantryRow(updatedAt: nil)
        XCTAssertFalse(legacy.autoAddToGrocery)
        XCTAssertTrue(patch["dateValue"] is NSNull, "clearing a date must send null, not omit it")
        XCTAssertTrue(patch["minimumQuantity"] is NSNull)
        XCTAssertNil(patch["householdId"])
        XCTAssertNil(patch["version"])
    }

    func testErrorBodiesDriveRecovery() {
        let current = PantryRemoteItem(
            id: UUID(), householdId: UUID(), ingredientId: "tomato", displayName: "Domates", quantity: 1, unit: "kg",
            location: .pantry, minimumQuantity: nil, dateType: nil, dateValue: nil, version: 5
        )
        XCTAssertEqual(PantrySyncError.classify(status: 409, body: PantryErrorBody(error: "conflict", recovery: "resolve", current: current)), .conflict(current: current))
        XCTAssertEqual(PantrySyncError.classify(status: 409, body: PantryErrorBody(error: "pantry_unit_choice", recovery: "choose-unit")), .unitChoice)
        XCTAssertEqual(PantrySyncError.classify(status: 400, body: PantryErrorBody(error: "unknown_ingredient", recovery: "fix-input")), .rejected(code: "unknown_ingredient"))
        XCTAssertEqual(PantrySyncError.classify(status: 403, body: PantryErrorBody(error: "forbidden", recovery: "refresh-household")), .rejected(code: "forbidden"))
        XCTAssertEqual(PantrySyncError.classify(status: 404, body: PantryErrorBody(error: "not_found", recovery: "refresh-household")), .notFound)
        XCTAssertNil(PantrySyncError.classify(status: 429, body: PantryErrorBody(error: "rate_limited", recovery: "retry-later")))
        XCTAssertNil(PantrySyncError.classify(status: 503, body: nil))
        XCTAssertNil(PantrySyncError.classify(status: 401, body: PantryErrorBody(error: "session_expired", recovery: "reauthenticate")))
    }

    func testTurkishCopyTheGuideFixes() {
        XCTAssertEqual(PantryCopy.empty, "Evdeki malzemelerini ekle. Planını ve marketini daha doğru hazırlayalım.")
        XCTAssertEqual(PantryCopy.conflict, "Bu malzeme başka bir cihazda güncellendi.")
        XCTAssertEqual(PantryCopy.usesStock, "Evdeki malzemeleri kullanıyor")
        XCTAssertEqual(PantryCopy.screenTitle, "Evdekiler")
        XCTAssertEqual(PantryCopy.consume, "Evdekilerden düş")
        XCTAssertEqual(PantryCopy.restock, "Evdekilere ekle")
        XCTAssertEqual(PantryCopy.missingPantry, "Evdekilerde bu malzeme yok.")
        XCTAssertEqual(PantryCopy.separateUnitMessage(existing: "400 g"), "Evdekilerde 400 g var. Birimler birbirine çevrilemiyor; ayrı satır olarak ekleyebilirsin.")
        for text in PantryCopy.userFacing {
            XCTAssertFalse(text.localizedCaseInsensitiveContains("pantry"), text)
        }
    }

    // MARK: V5.1 cook, threshold, reminders

    func testDeclineAndOtherPlanEventsDoNotChangeStock() {
        let stock = [cookStock(quantity: 400)]
        for event in [PantryStockEvent.openPlanItem, .checkPlanItem, .completeMarketRow, .regeneratePlan] {
            XCTAssertFalse(PantryStockEvent.deducts(event, confirmed: true))
            let outcome = cook(event: event, confirmed: true, needs: [need(quantity: 1, unit: "kg")], stock: stock)
            XCTAssertEqual(outcome.deductions, [])
            XCTAssertEqual(outcome.stock.map(\.quantity), [400])
        }
        XCTAssertFalse(PantryStockEvent.deducts(.markCooked, confirmed: false))
        let declined = cook(event: .markCooked, confirmed: false, needs: [need(quantity: 1, unit: "kg")], stock: stock)
        XCTAssertEqual(declined.deductions, [])
        XCTAssertEqual(declined.groceryMutations, [])
        XCTAssertEqual(declined.stock.map(\.quantity), [400])
        XCTAssertEqual(declined.appliedMeals, [])
    }

    func testConfirmDeductsOnlyConvertibleStockAndCapsAtWhatIsThere() {
        let outcome = cook(
            event: .markCooked,
            confirmed: true,
            needs: [need(ingredientId: "tomatoes", quantity: 1, unit: "kg")],
            stock: [cookStock(quantity: 400, unit: "g", minimum: 200)]
        )
        XCTAssertEqual(outcome.deductions.map(\.deducted), [400])
        XCTAssertEqual(outcome.deductions.map(\.newQuantity), [0])
        XCTAssertEqual(outcome.deductions.map(\.baseVersion), [3])
        XCTAssertEqual(outcome.stock.map(\.quantity), [0])
        XCTAssertEqual(outcome.stock.map(\.version), [4])
        XCTAssertEqual(outcome.shortages.map(\.missingQuantity), [0.6])
        XCTAssertEqual(outcome.shortages.map(\.unit), ["kg"])
        XCTAssertEqual(outcome.shortages.map(\.offerAddMissing), [true])
        XCTAssertEqual(outcome.groceryMutations, [])
        XCTAssertEqual(outcome.skipped, [])
    }

    func testUnitMismatchIsSkippedAndASecondNeedSeesTheReducedStock() {
        let mismatch = cook(
            event: .markCooked,
            confirmed: true,
            needs: [need(quantity: 2, unit: "piece")],
            stock: [cookStock(quantity: 400, unit: "g")]
        )
        XCTAssertEqual(mismatch.deductions, [])
        XCTAssertEqual(mismatch.stock.map(\.quantity), [400])
        XCTAssertEqual(mismatch.skipped.map(\.reason), [PantryCopy.unitMismatch])
        XCTAssertEqual(mismatch.shortages.map(\.offerAddMissing), [true])
        XCTAssertEqual(mismatch.groceryMutations, [])

        let twice = cook(
            event: .markCooked,
            confirmed: true,
            needs: [need(quantity: 300, unit: "g"), need(quantity: 300, unit: "g")],
            stock: [cookStock(quantity: 400, unit: "g")]
        )
        XCTAssertEqual(twice.deductions.map(\.deducted), [300, 100])
        XCTAssertEqual(twice.stock.map(\.quantity), [0])
        XCTAssertEqual(twice.shortages.map(\.missingQuantity), [200])
    }

    func testCookRetryDoesNotDeductAgain() {
        let first = cook(
            event: .markCooked,
            confirmed: true,
            needs: [need(quantity: 100, unit: "g")],
            stock: [cookStock(quantity: 400, unit: "g")]
        )
        XCTAssertEqual(first.stock.map(\.quantity), [300])
        let retry = PantryCookConsumption.apply(
            event: .markCooked,
            confirmed: true,
            mealId: "meal-1",
            needs: [need(quantity: 100, unit: "g")],
            stock: first.stock,
            rows: [],
            appliedMeals: first.appliedMeals,
            appliedCrossings: first.appliedCrossings,
            armedLow: first.armedLow,
            lowStockEnabled: false,
            dictionary: dictionary
        )
        XCTAssertEqual(retry.deductions, [])
        XCTAssertEqual(retry.stock.map(\.quantity), [300])
        XCTAssertEqual(PantryStableUUID.make("cook:meal-1:item-1"), PantryStableUUID.make("cook:meal-1:item-1"))
        XCTAssertNotEqual(PantryStableUUID.make("cook:meal-1:item-1"), PantryStableUUID.make("cook:meal-2:item-1"))
    }

    func testLowStockNotifiesOnceThenRearmsOnlyAfterARise() {
        let first = PantryLowStockNotifications.step(
            itemId: "item-1", name: "Domates", previousQuantity: 500, nextQuantity: 100,
            minimum: 200, enabled: true, armed: []
        )
        XCTAssertEqual(first.notice?.identifier, "pantry-low.item-1")
        XCTAssertEqual(first.notice?.title, PantryCopy.lowStockNoticeTitle)
        XCTAssertFalse(first.notice?.body.localizedCaseInsensitiveContains("pantry") ?? true)
        let still = PantryLowStockNotifications.step(
            itemId: "item-1", name: "Domates", previousQuantity: 100, nextQuantity: 80,
            minimum: 200, enabled: true, armed: first.armed
        )
        XCTAssertNil(still.notice)
        let quiet = PantryLowStockNotifications.step(
            itemId: "item-2", name: "Süt", previousQuantity: 500, nextQuantity: 100,
            minimum: 200, enabled: false, armed: []
        )
        XCTAssertNil(quiet.notice)
        XCTAssertTrue(quiet.armed.contains("item-2"))
        let enabledWhileLow = PantryLowStockNotifications.step(
            itemId: "item-2", name: "Süt", previousQuantity: 100, nextQuantity: 90,
            minimum: 200, enabled: true, armed: quiet.armed
        )
        XCTAssertNil(enabledWhileLow.notice)
        let risen = PantryLowStockNotifications.step(
            itemId: "item-1", name: "Domates", previousQuantity: 80, nextQuantity: 400,
            minimum: 200, enabled: true, armed: still.armed
        )
        XCTAssertNil(risen.notice)
        XCTAssertFalse(risen.armed.contains("item-1"))
        let again = PantryLowStockNotifications.step(
            itemId: "item-1", name: "Domates", previousQuantity: 400, nextQuantity: 200,
            minimum: 200, enabled: true, armed: risen.armed
        )
        XCTAssertNotNil(again.notice)
        let exact = PantryAutoGrocery.plan(
            itemId: "item-1", ingredientId: "tomato", displayName: "Domates",
            previousQuantity: 400, nextQuantity: 200, unit: "g", minimum: 200,
            autoAdd: true, version: 2, rows: [], applied: []
        )
        XCTAssertNil(exact.mutation, "landing on the minimum is low for the badge, and the shortfall is zero")
    }

    func testAutoAddIsOffByDefaultAndSetsTheShortfallOnce() throws {
        XCTAssertFalse(PantryNotificationPreferences.off.lowStockNotificationsEnabled)
        XCTAssertFalse(PantryNotificationPreferences.off.dateReminderEnabled)
        let off = PantryAutoGrocery.plan(
            itemId: "item-1", ingredientId: "tomato", displayName: "Domates",
            previousQuantity: 500, nextQuantity: 100, unit: "g", minimum: 200,
            autoAdd: false, version: 4, rows: [], applied: []
        )
        XCTAssertNil(off.mutation)
        let on = PantryAutoGrocery.plan(
            itemId: "item-1", ingredientId: "tomato", displayName: "Domates",
            previousQuantity: 500, nextQuantity: 100, unit: "kg", minimum: 200,
            autoAdd: true, version: 4, rows: [PantryMarketRow(itemKey: "tomato|kg", ingredientId: "tomato", displayName: "Domates", quantity: 1, unit: "kg", isChecked: false, revision: 2)],
            applied: []
        )
        let mutation = try XCTUnwrap(on.mutation)
        XCTAssertEqual(mutation.itemKey, "pantry-auto:tomato|kg")
        XCTAssertEqual(mutation.quantity, 100)
        XCTAssertNotEqual(mutation.itemKey, "tomato|kg")
        let once = PantryAutoGrocery.reduce([], mutation)
        let twice = PantryAutoGrocery.reduce(once, mutation)
        XCTAssertEqual(twice.map(\.quantity), [100])
        XCTAssertEqual(twice.map(\.itemKey), ["pantry-auto:tomato|kg"])
        let again = PantryAutoGrocery.plan(
            itemId: "item-1", ingredientId: "tomato", displayName: "Domates",
            previousQuantity: 500, nextQuantity: 100, unit: "kg", minimum: 200,
            autoAdd: true, version: 4, rows: twice, applied: on.applied
        )
        XCTAssertNil(again.mutation)
        var checked = twice
        checked[0].isChecked = true
        XCTAssertEqual(PantryAutoGrocery.reduce(checked, mutation), checked)
        let checkedPlan = PantryAutoGrocery.plan(
            itemId: "item-1", ingredientId: "tomato", displayName: "Domates",
            previousQuantity: 500, nextQuantity: 50, unit: "kg", minimum: 200,
            autoAdd: true, version: 5, rows: checked, applied: []
        )
        XCTAssertNil(checkedPlan.mutation)

        let both = cook(
            event: .markCooked,
            confirmed: true,
            needs: [need(quantity: 1, unit: "kg")],
            stock: [cookStock(quantity: 400, unit: "g", minimum: 200, autoAdd: true)]
        )
        XCTAssertEqual(both.groceryMutations.map(\.itemKey).sorted(), ["pantry-auto:tomato|g", "pantry-cook:meal-1:tomato|kg"])
        XCTAssertEqual(both.groceryMutations.first { $0.itemKey.hasPrefix("pantry-auto:") }?.quantity, 200)
        XCTAssertEqual(both.groceryMutations.first { $0.itemKey.hasPrefix("pantry-cook:") }?.quantity, 0.6)
        XCTAssertEqual(both.shortages.map(\.offerAddMissing), [false])
    }

    func testDateRemindersUseTheCalendarDayInEachDeviceZone() {
        let zones = ["Europe/Istanbul", "Pacific/Auckland", "America/Los_Angeles"]
        for identifier in zones {
            let zone = TimeZone(identifier: identifier)!
            let best = PantryDateReminders.plan(
                itemId: "milk", displayName: "Süt", dateType: .bestBefore, dateValue: "2026-03-01",
                quantity: 1, remindersEnabled: true, schedule: .standard, timeZone: zone
            )
            XCTAssertEqual(best.map { "\($0.year)-\($0.month)-\($0.day)" }, ["2026-2-27", "2026-3-1"], identifier)
            XCTAssertEqual(Set(best.map(\.hour)), [9])
            XCTAssertEqual(Set(best.map(\.timeZoneIdentifier)), [identifier])
            let useBy = PantryDateReminders.plan(
                itemId: "milk", displayName: "Süt", dateType: .useBy, dateValue: "2026-03-01",
                quantity: 1, remindersEnabled: true, schedule: .standard, timeZone: zone
            )
            XCTAssertEqual(useBy.map { "\($0.year)-\($0.month)-\($0.day)" }, ["2026-2-28", "2026-3-1"], identifier)
            for fire in best + useBy {
                for phrase in ["güvenli", "yenmez", "tazelik uyarısı"] {
                    XCTAssertFalse(fire.body.localizedCaseInsensitiveContains(phrase), fire.body)
                }
            }
        }
        let zone = TimeZone(identifier: "Europe/Istanbul")!
        XCTAssertEqual(PantryDateReminders.plan(itemId: "milk", displayName: "Süt", dateType: nil, dateValue: nil, quantity: 1, remindersEnabled: true, schedule: .standard, timeZone: zone), [])
        XCTAssertEqual(PantryDateReminders.plan(itemId: "milk", displayName: "Süt", dateType: .useBy, dateValue: "2026-03-01", quantity: 1, remindersEnabled: false, schedule: .standard, timeZone: zone), [])
        var schedule = PantryDateReminderSchedule.standard
        schedule.enabled = false
        XCTAssertEqual(PantryDateReminders.plan(itemId: "milk", displayName: "Süt", dateType: .useBy, dateValue: "2026-03-01", quantity: 1, remindersEnabled: true, schedule: schedule, timeZone: zone), [])
        XCTAssertEqual(PantryDateReminders.plan(itemId: "milk", displayName: "Süt", dateType: .useBy, dateValue: "2026-03-01", quantity: 0, remindersEnabled: true, schedule: .standard, timeZone: zone), [])
        let moved = PantryDateReminders.plan(itemId: "milk", displayName: "Süt", dateType: .bestBefore, dateValue: "2026-04-01", quantity: 1, remindersEnabled: true, schedule: .standard, timeZone: zone)
        XCTAssertEqual(moved.map(\.identifier), ["pantry-date.milk.bestBefore.2", "pantry-date.milk.bestBefore.0"])
        XCTAssertEqual(moved.map { "\($0.month)-\($0.day)" }, ["3-30", "4-1"])
        XCTAssertTrue(PantryDateReminders.allIdentifiers(itemId: "milk").contains("pantry-date.milk.bestBefore.2"))
        XCTAssertTrue(PantryDateReminders.allIdentifiers(itemId: "milk").contains("pantry-date.milk.useBy.1"))
    }

    private func need(ingredientId: String = "tomato", quantity: Double, unit: String) -> PantryCookNeed {
        PantryCookNeed(ingredientId: ingredientId, displayName: "Domates", quantity: quantity, unit: unit)
    }

    private func cookStock(quantity: Double, unit: String = "g", minimum: Double? = nil, autoAdd: Bool = false) -> PantryCookStock {
        PantryCookStock(
            id: "item-1", ingredientId: "tomato", displayName: "Domates", quantity: quantity, unit: unit,
            minimumQuantity: minimum, autoAddToGrocery: autoAdd, version: 3
        )
    }

    private func cook(
        event: PantryStockEvent,
        confirmed: Bool,
        needs: [PantryCookNeed],
        stock: [PantryCookStock]
    ) -> PantryCookOutcome {
        PantryCookConsumption.apply(
            event: event,
            confirmed: confirmed,
            mealId: "meal-1",
            needs: needs,
            stock: stock,
            rows: [],
            appliedMeals: [],
            appliedCrossings: [],
            armedLow: [],
            lowStockEnabled: true,
            dictionary: dictionary
        )
    }
}
