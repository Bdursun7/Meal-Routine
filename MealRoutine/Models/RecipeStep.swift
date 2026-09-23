import Foundation
import SwiftData

/// A cook step. V1 shows Turkish; English stays on `textEN` for attribution.
@Model
final class RecipeStep {
    var textEN: String
    var textTR: String
    var minutes: Int?
    var sortIndex: Int
    var recipe: Recipe? = nil

    init(
        textEN: String,
        textTR: String,
        minutes: Int?,
        sortIndex: Int
    ) {
        self.textEN = textEN
        self.textTR = textTR
        self.minutes = minutes
        self.sortIndex = sortIndex
    }

    /// Prefer the Turkish step. Fall back to English only when `textTR` is missing.
    var displayText: String {
        if !textTR.isEmpty { return textTR }
        return textEN
    }
}
