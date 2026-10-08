import Foundation

/// Why a week looks the way it does, as a language-independent code. `PlanWeek` stores `code`;
/// `text` renders it in the display language at read time.
struct PlanExplanation: Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case noMemory
        case lovedLean
        case familiarRhythm
        case emptyPool
        case lockedMeals
        case shortPool
        case balancedNew
        case triesNew
        case householdInstalled
    }

    var kind: Kind
    /// Counts the template needs: `shortPool` = [filled, requested]; `balancedNew` / `triesNew` = [new].
    var counts: [Int]
    /// User-provided names only (household member display names). Never a translatable phrase.
    var subject: String?
    var pantryNote: PantryPlanningNote?

    init(_ kind: Kind, counts: [Int] = [], subject: String? = nil, pantryNote: PantryPlanningNote? = nil) {
        self.kind = kind
        self.counts = counts
        self.subject = subject
        self.pantryNote = pantryNote
    }

    init?(code: String) {
        guard !code.isEmpty, let data = code.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(PlanExplanation.self, from: data) else { return nil }
        self = decoded
    }

    var code: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    func with(pantryNote note: PantryPlanningNote?) -> PlanExplanation {
        var copy = self
        copy.pantryNote = note
        return copy
    }

    var text: String {
        let base = baseText
        guard let pantryNote else { return base }
        return base.isEmpty ? pantryNote.text : "\(base) \(pantryNote.text)"
    }

    private func count(_ index: Int) -> Int {
        counts.indices.contains(index) ? counts[index] : 0
    }

    private var baseText: String {
        switch kind {
        case .noMemory:
            return L10n.text("plan.explanation.noMemory", "Bu hafta süre sınırına ve sevmediğin malzemelere göre kuruldu.")
        case .lovedLean:
            return L10n.text("plan.explanation.lovedLean", "Bu hafta daha önce sevdiğin yemeklere yaslanıyor, biraz çeşitlilikle.")
        case .familiarRhythm:
            return L10n.text("plan.explanation.familiarRhythm", "Bu hafta alışık olduğun sürelere yakın yemeklerden kuruldu.")
        case .emptyPool:
            return L10n.text("plan.explanation.emptyPool", "Bu filtrelere uyan tarif kalmadı. Süre sınırını yükselt veya sevmediğin malzemeleri azalt.")
        case .lockedMeals:
            return L10n.text("plan.explanation.lockedMeals", "Pişirilen akşamlar kilitli. Onların üzerine yazılmaz.")
        case .shortPool:
            return L10n.format("plan.explanation.shortPool", "Yeterli tarif yok. %ld akşam kurulabildi, %ld istendi.", count(0), count(1))
        case .balancedNew:
            return L10n.format("plan.explanation.balancedNew", "Dengeli bir hafta: hafta içi hızlı yemekler ve keşfedilecek %ld yeni tarif.", count(0))
        case .triesNew:
            return L10n.format("plan.explanation.triesNew", "Bu hafta sevdiğin tarzlardan %ld yeni tarif deniyor.", count(0))
        case .householdInstalled:
            return L10n.format("plan.explanation.householdInstalled", "Bu hafta %@ için kuruldu.", subject ?? "")
        }
    }
}

/// Deterministic week copy. Templates only. No model call.
/// The sentence names a count only when the picks actually contain it.
enum PlanExplanationBuilder {
    static var noMemory: String { PlanExplanation(.noMemory).text }
    static var lovedLean: String { PlanExplanation(.lovedLean).text }
    static var familiarRhythm: String { PlanExplanation(.familiarRhythm).text }
    static var emptyPool: String { PlanExplanation(.emptyPool).text }
    static var lockedMeals: String { PlanExplanation(.lockedMeals).text }

    static func shortPool(filled: Int, requested: Int) -> String {
        PlanExplanation(.shortPool, counts: [filled, requested]).text
    }

    static func explain(picks: [PlannedPick], hasBehavior: Bool) -> String {
        summary(picks: picks, hasBehavior: hasBehavior).text
    }

    static func summary(picks: [PlannedPick], hasBehavior: Bool) -> PlanExplanation {
        guard hasBehavior, !picks.isEmpty else { return PlanExplanation(.noMemory) }
        let newCount = picks.filter(\.isNew).count
        let lovedCount = picks.filter(\.wasLoved).count
        let quickWeekdays = picks.filter { $0.dayOffset < 5 && $0.minutes <= 30 }.count
        if lovedCount >= 2 && newCount <= 1 {
            return PlanExplanation(.lovedLean)
        }
        if newCount >= 2 && quickWeekdays >= 2 {
            return PlanExplanation(.balancedNew, counts: [newCount])
        }
        if newCount >= 1 {
            return PlanExplanation(.triesNew, counts: [newCount])
        }
        return PlanExplanation(.familiarRhythm)
    }
}
