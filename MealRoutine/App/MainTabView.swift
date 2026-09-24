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
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 28.0 / 255.0, green: 25.0 / 255.0, blue: 22.0 / 255.0, alpha: 0.88)
                : UIColor(red: 248.0 / 255.0, green: 244.0 / 255.0, blue: 237.0 / 255.0, alpha: 0.92)
        }
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
        .tint(Theme.accent)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(Theme.bgCream.opacity(0.92), for: .tabBar)
    }
}
