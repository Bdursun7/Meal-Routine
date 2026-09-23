import Foundation
import SwiftData

/// A cook step. V1 text is English; `textTR` is reserved for a later translation pass.
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

    /// Steps stay English in V1. Turkish is used only when a translation exists.
    var displayText: String {
        if !textTR.isEmpty { return textTR }
        return textEN
    }
}
