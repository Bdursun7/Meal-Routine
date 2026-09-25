import Foundation

/// Optional notes on the same screen as Loved / Okay / Never again.
/// The main rating stays required. These stay optional.
enum FeedbackReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case tooTimeConsuming
    case tooDifficult
    case wouldMakeAgain
    case portionSmall
    case portionLarge
    case missingIngredients
    case tooManyIngredients

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tooTimeConsuming: "Çok zaman aldı"
        case .tooDifficult: "Çok zordu"
        case .wouldMakeAgain: "Yine yaparım"
        case .portionSmall: "Porsiyon azdı"
        case .portionLarge: "Porsiyon fazlaydı"
        case .missingIngredients: "Malzeme eksikti"
        case .tooManyIngredients: "Çok fazla malzeme"
        }
    }
}
