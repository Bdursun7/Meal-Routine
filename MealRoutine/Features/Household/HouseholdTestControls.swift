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
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.badge")
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(notice.audience == .partner ? "Test bildirimi" : notice.title)
                    .font(.subheadline.weight(.semibold))
                Text(notice.bannerText)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Kapat", action: onDismiss)
                .font(.caption.weight(.semibold))
                .accessibilityLabel("Bildirimi kapat")
        }
        .padding(12)
        .mealCardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("household.testBanner")
        .accessibilityLabel(notice.bannerText)
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
                Text("Tek telefon. Test Partner senin yerine tepki verir. Gerçek CloudKit eşitlemesi ve push burada çalışmaz.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                if session.showsPartnerControls {
                    Text("Test Partner evde. Tepkiler Bu Hafta kartında, market işareti Market’te.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                } else if session.hasHousehold, session.snapshot.members.count < HouseholdLimits.maxMembers {
                    Button("Test Partner katılsın") {
                        Task { await session.simulatePartnerJoin(in: modelContext) }
                    }
                    .accessibilityIdentifier("household.partnerJoin")
                    .accessibilityHint("Davet kodunu ikinci üye olarak kabul eder")
                }
                if session.showsPartnerControls, let plan = session.snapshot.plan, !plan.meals.isEmpty {
                    ForEach(plan.meals.sorted { $0.dayOffset < $1.dayOffset }) { meal in
                        partnerMeal(meal)
                    }
                    Button("Test Partner marketi işaretlesin") {
                        Task { await session.partnerCheckNextGrocery(in: modelContext) }
                    }
                    .accessibilityIdentifier("household.partner.grocery")
                }
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
            } else {
                Text("Ücretli Apple hesabı yoksa bunu aç. Ev kur, kodu gör, Test Partner katılsın.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        } header: {
            Text("Test modu")
        }
    }

    private func partnerMeal(_ meal: SharedMeal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(meal.title)
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                ForEach(MealReactionKind.allCases) { kind in
                    Button(kind.title) {
                        Task { await session.partnerSetReaction(kind, mealID: meal.id, in: modelContext) }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(kind == .veto ? "household.partner.veto" : "household.partner.\(kind.rawValue)")
                    .accessibilityLabel("Test Partner, \(kind.title)")
                }
            }
            if HouseholdConflict.needsDecision(meal.reactions) {
                Button("Partner yerine koysun") {
                    Task { await session.partnerSuggestReplacement(mealID: meal.id, in: modelContext) }
                }
                .accessibilityIdentifier("household.partner.replace")
            }
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
            HStack(spacing: 8) {
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
                .accessibilityIdentifier("household.partner.replace")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mealCardSurface()
    }
}
