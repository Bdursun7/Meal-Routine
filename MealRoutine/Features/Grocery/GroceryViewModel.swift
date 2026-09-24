import Foundation
import Observation
import SwiftData

struct GroceryRowPresentation: Identifiable, Equatable {
    var id: UUID
    var name: String
    var detail: String
    var quantity: Double?
    var unitLabel: String
    var category: GroceryCategory
    var hasUnitConflict: Bool
    var isChecked: Bool
    var isManual: Bool
    /// Spoken and shown when only part of the merged amount is still needed.
    var remainingDetail: String?

    var canEditQuantity: Bool { quantity != nil }
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
            || row.category.title.localizedCaseInsensitiveContains(query)
    }

    private func sortedRows(weeks: [PlanWeek], now: Date) -> [GroceryRowPresentation] {
        let start = WeekCalendar.weekStart(containing: now)
        guard let week = weeks.first(where: { WeekCalendar.isSameDay($0.weekStart, start) }) else {
            return []
        }
        return week.groceries
            .map { item in
                GroceryRowPresentation(
                    id: item.uuid,
                    name: item.displayName,
                    detail: QuantityFormat.quantityAndUnit(quantity: item.quantity, unit: item.unit),
                    quantity: item.quantity,
                    unitLabel: UnitLabels.turkish(item.unit),
                    category: GroceryCategory.classify(ingredientId: item.ingredientId, name: item.displayName),
                    hasUnitConflict: item.hasUnitConflict,
                    isChecked: item.isChecked,
                    isManual: item.isManual,
                    remainingDetail: item.uncoveredQuantity.map { remaining in
                        "\(QuantityFormat.quantityAndUnit(quantity: remaining, unit: item.unit)) kaldı"
                    }
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
            try GroceryListService.rebuild(in: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginQuantityEdit(_ row: GroceryRowPresentation) {
        guard row.canEditQuantity else { return }
        editingID = row.id
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ id: UUID, in context: ModelContext) {
        do {
            try GroceryListService.deleteManual(id, in: context)
        } catch {
            errorMessage = error.localizedDescription
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
