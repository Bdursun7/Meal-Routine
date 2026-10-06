import SwiftData
import SwiftUI
import UIKit

enum AppTab: Hashable {
    case week
    case recipes
    case grocery
    case memory
    case profile
}

/// How long a tab switch is given before photo decodes and store maintenance.
/// The bar animation itself is about a third of a second.
enum TabSwitchTiming {
    static let settle: Duration = .milliseconds(250)
}

struct MainTabView: View {
    @Query private var recipes: [Recipe]
    @State private var selectedTab: AppTab = .week
    /// Bu Hafta is the landing tab. The others are installed on first selection,
    /// after one turn, so their `@Query`s are not live during unrelated switches.
    @State private var installedTabs: Set<AppTab> = [.week]
    @State private var router = CollectionRouter.shared
    @State private var notifications = NotificationRouter.shared

    private static let configureTabBar: Void = {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundEffect = nil
        appearance.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 28.0 / 255.0, green: 25.0 / 255.0, blue: 22.0 / 255.0, alpha: 1)
                : UIColor(red: 248.0 / 255.0, green: 244.0 / 255.0, blue: 237.0 / 255.0, alpha: 1)
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }()

    init() {
        _ = Self.configureTabBar
    }

    var body: some View {
        @Bindable var router = router
        TabView(selection: $selectedTab) {
            tabRoot(.week, title: "Bu Hafta", symbol: "calendar", selectedSymbol: "calendar.circle.fill") {
                ThisWeekView(
                    isTabSelected: selectedTab == .week,
                    onOpenGrocery: { selectedTab = .grocery }
                )
            }
            tabRoot(.recipes, title: "Tarifler", symbol: "book.closed", selectedSymbol: "book.closed.fill") {
                RecipeListView(isTabSelected: selectedTab == .recipes)
            }
            tabRoot(.grocery, title: "Market", symbol: "cart", selectedSymbol: "cart.fill") {
                GroceryView(isTabSelected: selectedTab == .grocery)
            }
            tabRoot(.memory, title: "Hafıza", symbol: "brain", selectedSymbol: "brain.fill") {
                NavigationStack {
                    MealMemoryView()
                }
            }
            tabRoot(.profile, title: "Profil", symbol: "person.crop.circle", selectedSymbol: "person.crop.circle.fill") {
                ProfileView(isTabSelected: selectedTab == .profile)
            }
        }
        .tint(Theme.accent)
        .sheet(item: $router.editor) { launch in
            RecipeEditorView(launch: launch)
        }
        .onChange(of: router.editor?.id) { _, id in
            guard id != nil else { return }
            installedTabs.insert(.recipes)
            selectedTab = .recipes
        }
        .onChange(of: router.openSlug) { _, slug in
            guard slug != nil else { return }
            installedTabs.insert(.recipes)
            selectedTab = .recipes
        }
        .onChange(of: notifications.revision) { _, _ in
            installedTabs.insert(notifications.tab)
            selectedTab = notifications.tab
        }
        .sheet(isPresented: Binding(
            get: { notifications.showJoin },
            set: { if !$0 { notifications.clearJoin() } }
        )) {
            NavigationStack {
                HouseholdSettingsView()
            }
        }
        .onAppear {
            if router.editor != nil || router.openSlug != nil {
                installedTabs.insert(.recipes)
                selectedTab = .recipes
            }
        }
        .onChange(of: selectedTab) { _, tab in
            guard !installedTabs.contains(tab) else { return }
            Task { @MainActor in
                await Task.yield()
                installedTabs.insert(tab)
            }
        }
    }

    @ViewBuilder
    private func tabRoot<Content: View>(
        _ tab: AppTab,
        title: String,
        symbol: String,
        selectedSymbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Group {
            if installedTabs.contains(tab) {
                content()
            } else {
                Theme.canvas
            }
        }
        .badge(tab == .recipes ? incompleteRecipeCount : 0)
        .tabItem {
            Label(title, systemImage: selectedTab == tab ? selectedSymbol : symbol)
        }
        .tag(tab)
    }

    private var incompleteRecipeCount: Int {
        IncompleteRecipeQueue.count(recipes.map {
            IncompleteRecipeSnapshot(originRaw: $0.originRaw, collectionStateRaw: $0.collectionStateRaw)
        })
    }
}
