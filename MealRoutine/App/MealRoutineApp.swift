import SwiftData
import SwiftUI

@main
struct MealRoutineApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainerFactory.make()
        } catch {
            fatalError("MealRoutine SwiftData store could not be created: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
