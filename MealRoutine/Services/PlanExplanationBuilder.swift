import Foundation

/// Deterministic week copy. Templates only. No model call.
/// The sentence names a count only when the picks actually contain it.
enum PlanExplanationBuilder {
    static let noMemory = "Bu hafta süre sınırına ve sevmediğin malzemelere göre kuruldu."
    static let lovedLean = "Bu hafta daha önce sevdiğin yemeklere yaslanıyor, biraz çeşitlilikle."
    static let familiarRhythm = "Bu hafta alışık olduğun sürelere yakın yemeklerden kuruldu."

    static func explain(picks: [PlannedPick], hasBehavior: Bool) -> String {
        guard hasBehavior, !picks.isEmpty else { return noMemory }
        let newCount = picks.filter(\.isNew).count
        let lovedCount = picks.filter(\.wasLoved).count
        let quickWeekdays = picks.filter { $0.dayOffset < 5 && $0.minutes <= 30 }.count
        if lovedCount >= 2 && newCount <= 1 {
            return lovedLean
        }
        if newCount >= 2 && quickWeekdays >= 2 {
            return "Dengeli bir hafta: hafta içi hızlı yemekler ve keşfedilecek \(newCount) yeni tarif."
        }
        if newCount >= 1 {
            return "Bu hafta sevdiğin tarzlardan \(newCount) yeni tarif deniyor."
        }
        return familiarRhythm
    }
}
