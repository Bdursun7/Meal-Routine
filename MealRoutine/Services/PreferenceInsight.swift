import Foundation

struct LovedMealSample: Equatable, Sendable {
    var protein: String
    var createdAt: Date
}

struct PreferenceInsight: Equatable, Sendable {
    var title: String
    var message: String
}

/// Short line for Bu Hafta. Hidden until several loved ratings exist.
enum PreferenceInsightBuilder {
    static let minimumLovedCount = 3
    static let recentWindowDays = 21

    static func make(loved: [LovedMealSample], now: Date = .now) -> PreferenceInsight? {
        guard loved.count >= minimumLovedCount else { return nil }
        let cutoff = now.addingTimeInterval(-Double(recentWindowDays * 86_400))
        let recent = loved.filter { $0.createdAt >= cutoff }
        let pool = recent.count >= minimumLovedCount ? recent : loved
        let title = "Tercihlerin netleşiyor"
        if let top = dominant(in: pool), let label = proteinTitle(top.protein) {
            return PreferenceInsight(
                title: title,
                message: "Son zamanlarda \(top.count) \(label) tarifini sevdin."
            )
        }
        return PreferenceInsight(
            title: title,
            message: "Son zamanlarda \(pool.count) tarifi sevdin."
        )
    }

    static func dominant(in samples: [LovedMealSample]) -> (protein: String, count: Int)? {
        var counts: [String: Int] = [:]
        for sample in samples {
            let key = sample.protein.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            counts[key, default: 0] += 1
        }
        let ranked = counts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }
        guard let top = ranked.first, top.value >= 2 else { return nil }
        return (top.key, top.value)
    }

    static func proteinTitle(_ protein: String) -> String? {
        switch protein.lowercased() {
        case "poultry": "tavuk"
        case "red-meat": "kırmızı et"
        case "seafood": "balık"
        case "egg": "yumurta"
        case "legume": "bakliyat"
        case "tofu": "tofu"
        case "dairy": "süt ürünü"
        default: nil
        }
    }
}
