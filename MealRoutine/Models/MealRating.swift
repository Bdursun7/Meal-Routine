import Foundation

/// Household reaction stored on `RecipeFeedback`.
enum MealRating: String, Codable, CaseIterable, Identifiable, Sendable {
    case loved
    case okay
    case never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .loved: "Sevdim"
        case .okay: "İdare eder"
        case .never: "Bir daha asla"
        }
    }

    var systemImage: String {
        switch self {
        case .loved: "heart.fill"
        case .okay: "hand.thumbsup"
        case .never: "hand.thumbsdown"
        }
    }
}
