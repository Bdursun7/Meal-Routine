import SwiftUI

/// Single-evening replacement. Grocery rebuild stays in the sheet after the swap.
struct SmartReplacementView: View {
    var mealID: UUID

    var body: some View {
        MealReplacementSheet(mealID: mealID)
    }
}
