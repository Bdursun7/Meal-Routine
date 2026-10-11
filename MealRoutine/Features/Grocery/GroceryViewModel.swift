import Foundation
import Observation
import SwiftData

struct GroceryRowPresentation: Identifiable, Equatable {
    var id: String
    var partIDs: [UUID]
    var name: String
    /// One part: its amount. Several parts: the labeled breakdown, not a sum.
    var detail: String
    var quantity: Double?
    var unitLabel: String
    var category: GroceryCategory
    var hasUnitConflict: Bool
    var isChecked: Bool
    var isMixed: Bool
    var isManual: Bool
    /// Spoken and shown when only part of the merged plan amount is still needed.
    var remainingDetail: String?
    var parts: [GroceryCardPart]
    var primaryPartID: UUID?
    /// Single-part cards keep the source under the amount. A breakdown already names each source.
    var sourceCaption: String?

    var canEditQuantity: Bool { parts.count == 1 && quantity != nil }
}

struct GrocerySectionPresentation: Identifiable, Equatable {
    var category: GroceryCategory
    var rows: [GroceryRowPresentation]

    var id: String { category.rawValue }
}

struct GroceryListPresentation: Equatable {
    var openSections: [GrocerySectionPresentation]
    var checked: [GroceryRowPresentation]
    var conflictCount: Int
    var checkedCount: Int
    var totalCount: Int

    var isEmpty: Bool { totalCount == 0 }
}

/// A question the user answers before a grocery row is added to the pantry.
struct PantryRestockPrompt: Identifiable, Equatable {
    enum Kind: Equatable {
        case pickIngredient
        case confirmSeparate(existing: String)
    }

    var groceryID: UUID
    var name: String
    var kind: Kind
    var ingredient: IngredientEntry?

    var id: UUID { groceryID }
}

@MainActor
@Observable
final class GroceryViewModel {
    var searchText = ""
    var isPresentingAdd = false
    var draftName = ""
    var draftQuantity = ""
    var draftUnit = "piece"
    var errorMessage: String?
    var editingID: UUID?
    var editingQuantity = ""
    var usesPantryCoverage = UserDefaults.standard.bool(forKey: coverageKey)
    var pantryNote: String?
    var pantryPrompt: PantryRestockPrompt?
    private static let coverageKey = "mealroutine.pantry.marketCoverage"

    static let manualUnits = ["piece", "g", "kg", "ml", "l", "tbsp", "tsp", "clove", "toTaste"]

    func presentation(weeks: [PlanWeek], now: Date = .now) -> GroceryListPresentation {
        let rows = sortedRows(weeks: weeks, now: now)
        let open = rows.filter { !$0.isChecked }
        let checked = rows.filter(\.isChecked)
        let sections = GroceryCategory.sectionOrder.compactMap { category -> GrocerySectionPresentation? in
            let inAisle = open.filter { $0.category == category }
            guard !inAisle.isEmpty else { return nil }
            return GrocerySectionPresentation(category: category, rows: inAisle)
        }
        return GroceryListPresentation(
            openSections: sections,
            checked: checked,
            conflictCount: Set(rows.filter(\.hasUnitConflict).map(\.name)).count,
            checkedCount: checked.count,
            totalCount: rows.count
        )
    }

    /// Narrows the current list by ingredient name or Turkish aisle title. An empty query returns the list unchanged.
    func applyingSearch(to list: GroceryListPresentation) -> GroceryListPresentation {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return list }
        let openSections = list.openSections.compactMap { section -> GrocerySectionPresentation? in
            let rows = section.rows.filter { matchesSearch($0, query) }
            guard !rows.isEmpty else { return nil }
            return GrocerySectionPresentation(category: section.category, rows: rows)
        }
        let checked = list.checked.filter { matchesSearch($0, query) }
        let visible = openSections.flatMap(\.rows) + checked
        return GroceryListPresentation(
            openSections: openSections,
            checked: checked,
            conflictCount: Set(visible.filter(\.hasUnitConflict).map(\.name)).count,
            checkedCount: checked.count,
            totalCount: visible.count
        )
    }

    private func matchesSearch(_ row: GroceryRowPresentation, _ query: String) -> Bool {
        row.name.localizedCaseInsensitiveContains(query)
            || row.detail.localizedCaseInsensitiveContains(query)
            || row.category.title.localizedCaseInsensitiveContains(query)
    }

    private func sortedRows(weeks: [PlanWeek], now: Date) -> [GroceryRowPresentation] {
        let start = WeekCalendar.weekStart(containing: now)
        guard let week = weeks.first(where: { WeekCalendar.isSameDay($0.weekStart, start) }) else {
            return []
        }
        let inputs = week.groceries.map { item in
            GroceryCardInput(
                id: item.uuid,
                ingredientId: item.ingredientId,
                name: item.displayName,
                quantity: item.quantity,
                unit: item.unit,
                hasUnitConflict: item.hasUnitConflict,
                isChecked: item.isChecked,
                isManual: item.isManual,
                sourceRaw: item.sourceRaw,
                remainingDetail: item.uncoveredQuantity.map { remaining in
                    PantryCopy.stillToBuy(QuantityFormat.quantityAndUnit(quantity: remaining, unit: item.unit))
                } ?? (usesPantryCoverage && !item.isManual && !item.isChecked && item.quantity == 0 ? PantryCopy.covered : nil)
            )
        }
        return GroceryCardGrouper.group(inputs).map { card in
            let single = card.singlePart
            return GroceryRowPresentation(
                id: card.id,
                partIDs: card.parts.flatMap { $0.memberIDs.isEmpty ? [$0.id] : $0.memberIDs },
                name: card.name,
                detail: single?.amountText ?? card.breakdown,
                quantity: single?.quantity,
                unitLabel: UnitLabels.turkish(single?.unit ?? card.parts.first?.unit ?? ""),
                category: card.category,
                hasUnitConflict: card.hasUnitConflict,
                isChecked: card.isFullyChecked,
                isMixed: card.isMixed,
                isManual: card.canDelete,
                remainingDetail: card.coverageNote,
                parts: card.parts,
                primaryPartID: card.primaryPartID,
                sourceCaption: single?.source.title
            )
        }
        .sorted { lhs, rhs in
            if lhs.hasUnitConflict != rhs.hasUnitConflict { return lhs.hasUnitConflict }
            let order = lhs.name.localizedStandardCompare(rhs.name)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.detail < rhs.detail
        }
    }

    func rebuild(in context: ModelContext) {
        do {
            _ = try WeekPlanService.ensureCurrentWeek(in: context)
            let stamp = try GroceryListService.rebuild(in: context, applyingPantry: usesPantryCoverage)
            pantryNote = stamp.incompatibleCount > 0 ? PantryCopy.incompatibleCount : nil
            if stamp.applying, !stamp.needs.isEmpty {
                let needs = stamp.needs
                Task { await pushCoverage(needs) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setPantryCoverage(_ enabled: Bool, in context: ModelContext) {
        usesPantryCoverage = enabled
        UserDefaults.standard.set(enabled, forKey: Self.coverageKey)
        GroceryListService.discardRebuildCache()
        rebuild(in: context)
    }

    func consumeFromPantry(_ id: UUID, in context: ModelContext) {
        mutatePantry(id, in: context, adding: false)
    }

    func addToPantry(_ id: UUID, confirmSeparate: Bool = false, ingredient: IngredientEntry? = nil, in context: ModelContext) {
        mutatePantry(id, in: context, adding: true, confirmSeparate: confirmSeparate, chosen: ingredient)
    }

    /// Grocery → pantry runs only from these explicit actions. Rows meet on the dictionary id;
    /// a row without one asks the user which ingredient it is instead of guessing from its name.
    private func mutatePantry(_ id: UUID, in context: ModelContext, adding: Bool, confirmSeparate: Bool = false, chosen: IngredientEntry? = nil) {
        let groceries = (try? context.fetch(FetchDescriptor<GroceryItem>())) ?? []
        guard let row = groceries.first(where: { $0.uuid == id }), let amount = row.quantity, amount > 0 else { return }
        let dictionary = IngredientDictionary.shared
        let householdID = HouseholdSession.shared.snapshot.household?.id
        guard let key = chosen.flatMap({ dictionary.canonicalId($0.id) }) ?? dictionary.canonicalId(row.ingredientId) else {
            if adding {
                pantryPrompt = PantryRestockPrompt(groceryID: row.uuid, name: row.displayName, kind: .pickIngredient, ingredient: nil)
            } else {
                errorMessage = PantryCopy.missingPantry
            }
            return
        }
        let pantry = ((try? context.fetch(FetchDescriptor<PantryItem>())) ?? []).filter { $0.householdID == householdID }
        let peers = pantry.filter { dictionary.canonicalId($0.ingredientID) == key }
        if let match = peers.first(where: { PantryUnitPolicy.compatible($0.unit, row.unit) }) {
            let next = adding
                ? PantryUnitPolicy.restock(stockQuantity: match.quantity, stockUnit: match.unit, amount: amount, amountUnit: row.unit)
                : PantryUnitPolicy.consume(stockQuantity: match.quantity, stockUnit: match.unit, amount: amount, amountUnit: row.unit)
            guard let next else {
                errorMessage = PantryCopy.unitMismatch
                return
            }
            let previous = match.quantity
            let base = match.revision
            match.quantity = next
            match.updatedAt = .now
            match.revision += 1
            try? context.save()
            PantryStockSideEffects.afterQuantityChange(item: match, previousQuantity: previous, in: context)
            if PantryOutbox.record(.update, match, baseVersion: base, in: context) {
                Task { await PantryOutbox.flush(in: context) }
            }
            return
        }
        if !adding {
            errorMessage = peers.isEmpty ? PantryCopy.missingPantry : PantryCopy.unitMismatch
            return
        }
        guard PantryUnitPolicy.isKnown(row.unit) else {
            errorMessage = PantryCopy.unknownUnit
            return
        }
        if let peer = peers.first, !confirmSeparate {
            pantryPrompt = PantryRestockPrompt(
                groceryID: row.uuid,
                name: row.displayName,
                kind: .confirmSeparate(existing: QuantityFormat.quantityAndUnit(quantity: peer.quantity, unit: peer.unit)),
                ingredient: chosen
            )
            return
        }
        let created = PantryItem(
            householdID: householdID,
            ingredientID: key,
            displayName: chosen?.name ?? dictionary.entry(key)?.name ?? row.displayName,
            quantity: amount,
            unit: UnitNormalization.parse(row.unit).code,
            location: .pantry
        )
        context.insert(created)
        try? context.save()
        if let chosen, IngredientDictionary.isCustom(chosen.id) {
            PantryIngredientStore.remember(chosen, householdID: householdID)
        }
        if PantryOutbox.record(.create, created, baseVersion: nil, confirmSeparate: confirmSeparate, in: context) {
            Task { await PantryOutbox.flush(in: context) }
        }
    }

    private func pushCoverage(_ needs: [PantryReconcileLine]) async {
        guard PantryOutbox.syncsHousehold,
              let householdID = HouseholdSession.shared.snapshot.household?.id,
              let api = PantrySync.repository() else { return }
        let key = PantryMarketCoverage.idempotencyKey(for: needs)
        _ = try? await api.reconcile(
            householdId: householdID,
            operation: "compute-missing",
            lines: needs,
            idempotencyKey: key
        )
    }

    func beginQuantityEdit(_ row: GroceryRowPresentation) {
        guard row.canEditQuantity, let partID = row.parts.first?.id else { return }
        editingID = partID
        editingQuantity = QuantityFormat.string(row.quantity)
    }

    func cancelQuantityEdit() {
        editingID = nil
        editingQuantity = ""
    }

    func commitQuantity(in context: ModelContext) {
        guard let editingID else { return }
        guard let quantity = GroceryQuantityEdit.parse(editingQuantity) else {
            errorMessage = "Miktar bir sayı olmalı."
            return
        }
        do {
            try GroceryListService.updateQuantity(editingID, quantity: quantity, in: context)
            cancelQuantityEdit()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggle(_ id: UUID, in context: ModelContext) {
        do {
            try GroceryListService.toggle(id, in: context)
            HouseholdSession.shared.noteGrocery(id: id, in: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Checks every part, or clears them when the card is already fully checked.
    /// A mixed card completes the remaining parts. Each part keeps its own sync key.
    func toggleCard(_ row: GroceryRowPresentation, in context: ModelContext) {
        let turnOn = !row.isChecked
        let items = (try? context.fetch(FetchDescriptor<GroceryItem>())) ?? []
        for id in row.partIDs {
            guard let item = items.first(where: { $0.uuid == id }), item.isChecked != turnOn else { continue }
            toggle(id, in: context)
        }
    }

    func delete(_ id: UUID, in context: ModelContext) {
        do {
            try GroceryListService.deleteManual(id, in: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteCard(_ row: GroceryRowPresentation, in context: ModelContext) {
        guard row.isManual else { return }
        for id in row.partIDs {
            delete(id, in: context)
        }
    }

    func addManual(in context: ModelContext) {
        let quantity = parseQuantity(draftQuantity)
        do {
            try GroceryListService.addManual(
                name: draftName,
                quantity: quantity,
                unit: draftUnit,
                in: context
            )
            draftName = ""
            draftQuantity = ""
            draftUnit = "piece"
            isPresentingAdd = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func parseQuantity(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }
}
