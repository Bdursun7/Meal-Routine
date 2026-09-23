import Foundation
import Observation
import SwiftData

struct GroceryRowPresentation: Identifiable, Equatable {
    var id: UUID
    var name: String
    var detail: String
    var hasUnitConflict: Bool
    var isChecked: Bool
    var isManual: Bool
}

@MainActor
@Observable
final class GroceryViewModel {
    var isPresentingAdd = false
    var draftName = ""
    var draftQuantity = ""
    var draftUnit = "piece"
    var errorMessage: String?

    static let manualUnits = ["piece", "g", "kg", "ml", "l", "tbsp", "tsp", "clove", "toTaste"]

    func rows(weeks: [PlanWeek], now: Date = .now) -> [GroceryRowPresentation] {
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
                    hasUnitConflict: item.hasUnitConflict,
                    isChecked: item.isChecked,
                    isManual: item.isManual
                )
            }
            .sorted { lhs, rhs in
                if lhs.isChecked != rhs.isChecked { return !lhs.isChecked }
                if lhs.hasUnitConflict != rhs.hasUnitConflict { return lhs.hasUnitConflict }
                let order = lhs.name.localizedStandardCompare(rhs.name)
                if order != .orderedSame { return order == .orderedAscending }
                return lhs.detail < rhs.detail
            }
    }

    func conflictCount(in rows: [GroceryRowPresentation]) -> Int {
        Set(rows.filter(\.hasUnitConflict).map(\.name)).count
    }

    func rebuild(in context: ModelContext) {
        do {
            _ = try WeekPlanService.ensureCurrentWeek(in: context)
            try GroceryListService.rebuild(in: context)
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
