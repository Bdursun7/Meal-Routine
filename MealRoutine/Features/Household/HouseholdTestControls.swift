import SwiftData
import SwiftUI

struct HouseholdTestBadge: View {
    var body: some View {
        Text("Test modu")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(Theme.textCharcoal)
            .background(Theme.accent.opacity(0.18), in: Capsule())
            .accessibilityIdentifier("household.testBadge")
            .accessibilityLabel("Test modu açık")
    }
}

struct HouseholdTestBanner: View {
    var notice: HouseholdTestNotice
    var onOpen: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.badge")
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Button {
                onOpen()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(notice.audience == .partner ? "Test bildirimi" : notice.title)
                        .font(.subheadline.weight(.semibold))
                    Text(notice.bannerText)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("notification.banner.open")
            Button("Kapat", action: onDismiss)
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier("household.testBanner.dismiss")
                .accessibilityLabel("Bildirimi kapat")
        }
        .padding(12)
        .mealCardSurface()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("household.testBanner")
    }
}

struct HouseholdTestModeSection: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var session: HouseholdSession
    var testMode: HouseholdTestMode

    var body: some View {
        Section {
            Toggle("Test modu", isOn: Binding(
                get: { testMode.isEnabled },
                set: { enabled in
                    Task { await session.setTestMode(enabled, in: modelContext) }
                }
            ))
            .accessibilityIdentifier("household.testMode.toggle")
            .accessibilityHint("Apple hesabı, iCloud ve bildirim olmadan ev halkını bu telefonda dener")
            if testMode.isEnabled {
                HouseholdTestBadge()
                Toggle("Çevrimdışı simüle et", isOn: Binding(
                    get: { testMode.simulateOffline },
                    set: { offline in
                        session.setSimulateOffline(offline, in: modelContext)
                    }
                ))
                .accessibilityIdentifier("household.simulateOffline")
                Toggle("Partner aynı yemeği değiştirsin", isOn: Binding(
                    get: { testMode.simulatePartnerEdit },
                    set: { testMode.simulatePartnerEdit = $0 }
                ))
                .accessibilityIdentifier("household.simulatePartnerEdit")
                Text("Tek telefon. Test Partner senin yerine tepki verir. Ortak veri sunucuda durur; test modu ağa çıkmaz, çevrimdışı ve çakışmayı buradan deneyebilirsin.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                if !testMode.notices.isEmpty {
                    ForEach(testMode.notices.prefix(8)) { notice in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(notice.audience == .partner ? "Test Partner görür" : "Sana")
                                .font(.caption.weight(.semibold))
                            Text(notice.body)
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Button("Test verisini sıfırla", role: .destructive) {
                    session.resetTestData(in: modelContext)
                }
                .accessibilityIdentifier("household.resetTest")
                .accessibilityHint("Test evini, partneri ve bildirim günlüğünü siler")
                Button("Bildirim deep link'ini dene") {
                    if let url = URL(string: "mealroutine://week/meal?id=test-meal") {
                        NotificationRouter.shared.apply(NotificationDeepLink.parse(url))
                    }
                }
                .accessibilityIdentifier("notification.testDeepLink")
            } else {
                Text("Ücretli Apple hesabı yoksa bunu aç. Ev kur, kodu gör, Test Partner katılsın.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        } header: {
            Text("Test modu")
        }
    }
}

struct HouseholdPartnerMealControls: View {
    @Environment(\.modelContext) private var modelContext
    var mealID: UUID
    @Bindable var session: HouseholdSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Test Partner")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            FlowLayout(spacing: 8) {
                ForEach(MealReactionKind.allCases) { kind in
                    Button(kind.title) {
                        Task { await session.partnerSetReaction(kind, mealID: mealID, in: modelContext) }
                    }
                    .buttonStyle(.bordered)
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier(kind == .veto ? "household.partner.veto" : "household.partner.\(kind.rawValue)")
                    .accessibilityLabel("Test Partner, \(kind.title)")
                }
            }
            if session.snapshot.plan?.meals.first(where: { $0.id == mealID }).map({ HouseholdConflict.needsDecision($0.reactions) }) == true {
                Button("Partner yerine koysun") {
                    Task { await session.partnerSuggestReplacement(mealID: mealID, in: modelContext) }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("household.partner.replace")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mealCardSurface()
    }
}
