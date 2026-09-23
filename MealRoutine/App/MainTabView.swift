import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            ThisWeekView()
                .tabItem { Label("Bu Hafta", systemImage: "calendar") }
            RecipeListView()
                .tabItem { Label("Tarifler", systemImage: "book.closed") }
            GroceryView()
                .tabItem { Label("Market", systemImage: "cart") }
            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
        }
        .tint(Theme.accent)
    }
}
