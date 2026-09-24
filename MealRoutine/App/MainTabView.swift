import SwiftUI

enum AppTab: Hashable {
    case week
    case recipes
    case grocery
    case profile
}

struct MainTabView: View {
    @State private var selectedTab: AppTab = .week

    var body: some View {
        TabView(selection: $selectedTab) {
            ThisWeekView(selectedTab: $selectedTab)
                .tabItem { Label("Bu Hafta", systemImage: "calendar") }
                .tag(AppTab.week)
            RecipeListView()
                .tabItem { Label("Tarifler", systemImage: "book.closed") }
                .tag(AppTab.recipes)
            GroceryView()
                .tabItem { Label("Market", systemImage: "cart") }
                .tag(AppTab.grocery)
            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .tint(Theme.accent)
    }
}
