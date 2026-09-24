import SwiftUI
import UIKit

enum AppTab: Hashable {
    case week
    case recipes
    case grocery
    case profile
}

struct MainTabView: View {
    @State private var selectedTab: AppTab = .week

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundEffect = nil
        appearance.backgroundColor = Theme.canvasUIColor
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ThisWeekView(selectedTab: $selectedTab)
                .tabItem { Label("Bu Hafta", systemImage: selectedTab == .week ? "calendar.circle.fill" : "calendar") }
                .tag(AppTab.week)
            RecipeListView()
                .tabItem { Label("Tarifler", systemImage: selectedTab == .recipes ? "book.closed.fill" : "book.closed") }
                .tag(AppTab.recipes)
            GroceryView()
                .tabItem { Label("Market", systemImage: selectedTab == .grocery ? "cart.fill" : "cart") }
                .tag(AppTab.grocery)
            ProfileView()
                .tabItem { Label("Profil", systemImage: selectedTab == .profile ? "person.crop.circle.fill" : "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .tint(Theme.sage)
    }
}
