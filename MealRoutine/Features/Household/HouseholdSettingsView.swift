import AuthenticationServices
import SwiftData
import SwiftUI
import UIKit

struct HouseholdSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var session = HouseholdSession.shared
    @State private var testMode = HouseholdTestMode.shared
    @State private var householdName = ""
    @State private var inviteCode = ""
    @State private var cookingDays: Set<Int> = []
    @State private var maxMinutes = 60
    @State private var categories = ""
    @State private var proteins = ""
    @State private var avoided = ""

    var body: some View {
        Form {
            HouseholdTestModeSection(session: session, testMode: testMode)
            statusSection
            if session.account == nil {
                signInSection
            } else if !session.hasHousehold {
                createSection
                joinSection
            } else {
                membersSection
                inviteSection
                planSection
                preferenceSection
                activitySection
                dangerSection
            }
        }
        .navigationTitle("Ev halkı")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if testMode.isEnabled {
                ToolbarItem(placement: .topBarTrailing) {
                    HouseholdTestBadge()
                }
            }
        }
        .onAppear(perform: loadPreference)
    }

    @ViewBuilder
    private var statusSection: some View {
        if session.syncState == .offline {
            Section {
                Label("Çevrimdışı. Değişiklik bu telefonda duruyor ve iCloud gelince gider.", systemImage: "icloud.slash")
                    .font(.footnote)
                    .accessibilityLabel("Çevrimdışı. Ev halkı bu telefonda duruyor.")
            }
        } else if session.syncState == .syncing {
            Section {
                HStack {
                    ProgressView()
                    Text("Eşitleniyor…")
                }
                .accessibilityLabel("Ev halkı eşitleniyor")
            }
        }
        if let message = session.statusMessage, !message.isEmpty {
            Section {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var signInSection: some View {
        Section {
            if session.isTestMode {
                Text("Test modunda Apple kimliği yok. Bu oturum yalnızca bu telefonda durur.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                Button("Test olarak gir") {
                    session.signInForTest()
                }
                .accessibilityIdentifier("household.testSignIn")
                .accessibilityLabel("Test olarak gir")
            } else if HouseholdTestLaunch.allowsAppleServices {
                Text("İki kişi aynı haftayı seçebilsin diye Apple ile giriş yeter. Google, e-posta veya telefon yok.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName]
                } onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
                        let name = credential.fullName.flatMap { PersonNameComponentsFormatter().string(from: $0) }
                        session.adoptAppleUser(id: credential.user, displayName: name)
                        Task {
                            await session.refresh(in: modelContext)
                            if let code = session.pendingInviteCode {
                                await session.acceptInvite(code: code, in: modelContext)
                            }
                        }
                    case .failure:
                        session.statusMessage = "Apple ile giriş tamamlanamadı."
                    }
                }
                .frame(height: 44)
                .accessibilityLabel("Apple ile giriş yap")
            } else {
                Text("Bu derleme Apple ile girişi, iCloud’u ve bildirimi imzalamaz. Ev halkını denemek için Test modunu aç.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        } header: {
            Text("Hesap")
        }
    }

    private var createSection: some View {
        Section {
            TextField("Ev halkının adı", text: $householdName)
                .textInputAutocapitalization(.words)
                .accessibilityLabel("Ev halkının adı")
            Button("Ev halkı kur") {
                session.createHousehold(name: householdName, in: modelContext)
            }
            .disabled(householdName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("household.create")
        } header: {
            Text("Ev halkı kur")
        } footer: {
            Text("En fazla iki kişi. Amaç birlikte akşam yemeğini seçmek.")
        }
    }

    private var joinSection: some View {
        Section {
            TextField("Davet kodu", text: $inviteCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .accessibilityLabel("Davet kodu")
            Button("Kodla katıl") {
                Task { await session.acceptInvite(code: inviteCode, in: modelContext) }
            }
            .disabled(HouseholdInviteCode.normalize(inviteCode).count != HouseholdInviteCode.length)
        } header: {
            Text("Davetlisin")
        }
    }

    private var membersSection: some View {
        Section {
            if let name = session.snapshot.household?.name {
                Text(name)
                    .font(.headline)
                Text(HouseholdWeekCopy.headline(members: session.snapshot.members))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(session.snapshot.members) { member in
                HStack {
                    Text(member.displayName)
                    Spacer()
                    Text(member.role == .owner ? "Ev sahibi" : "Üye")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityElement(children: .combine)
                if session.snapshot.role(of: session.account?.id ?? "") == .owner, member.role == .member {
                    Button("Çıkar", role: .destructive) {
                        session.remove(memberId: member.userId, in: modelContext)
                    }
                    .accessibilityHint("\(member.displayName) ev halkından çıkar")
                }
            }
        } header: {
            Text("Üyeler")
        }
    }

    @ViewBuilder
    private var inviteSection: some View {
        if session.snapshot.role(of: session.account?.id ?? "") == .owner,
           session.snapshot.members.count < HouseholdLimits.maxMembers {
            Section {
                if let invite = pendingInvite {
                    Text(invite.inviteCode)
                        .font(.system(.title2, design: .monospaced).weight(.semibold))
                        .accessibilityLabel("Davet kodu \(invite.inviteCode)")
                    Text(HouseholdInviteLink.url(for: invite.inviteCode).absoluteString)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .textSelection(.enabled)
                    Button("Kodu kopyala") {
                        UIPasteboard.general.string = invite.inviteCode
                        session.statusMessage = "Kod kopyalandı."
                    }
                    .accessibilityHint("Davet kodunu panoya alır")
                    ShareLink(item: HouseholdInviteLink.url(for: invite.inviteCode)) {
                        Text("Davet bağlantısını paylaş")
                    }
                    .accessibilityHint("Partnerin açacağı bağlantıyı paylaşır")
                    Button("Daveti geri al", role: .destructive) {
                        session.revoke(inviteId: invite.id, in: modelContext)
                    }
                } else {
                    Button("Partnerini davet et") {
                        session.createInvite(in: modelContext)
                    }
                    .accessibilityIdentifier("household.invite")
                    .accessibilityHint("Altı haneli kod ve bağlantı oluşturur")
                }
            } header: {
                Text("Davet")
            } footer: {
                Text("Partner kodu ya da bağlantıyı kendi Apple hesabıyla açar. İkinci kişiden sonra davet kapanır.")
            }
        }
    }

    private var planSection: some View {
        Section {
            if let plan = session.snapshot.plan {
                Text(plan.status.title)
                    .accessibilityIdentifier("household.planStatus")
                if plan.status == .needsDecisions {
                    Text("Bir akşam veto edildi. Başka yemek seçmeden plan kapanmaz.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            } else {
                Text("Henüz ortak plan yok. Bu Hafta kişisel planınla durur, ta ki birlikte bir hafta kurana kadar.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            Button("Ortak haftayı kur") {
                session.generateSharedWeek(in: modelContext)
            }
            .accessibilityIdentifier("household.generateWeek")
            .accessibilityHint("İki kişinin hafızasına ve bu haftanın vetolarına göre plan kurar")
            if let plan = session.snapshot.plan {
                ForEach(plan.meals.sorted { $0.dayOffset < $1.dayOffset }) { meal in
                    sharedMealRow(meal)
                }
            }
        } header: {
            Text("Bu hafta")
        }
    }

    private func sharedMealRow(_ meal: SharedMeal) -> some View {
        let label = HouseholdConflict.label(
            reactions: meal.reactions,
            memberIds: session.snapshot.members.map(\.userId)
        )
        return VStack(alignment: .leading, spacing: 6) {
            Text(WeekCalendar.dayTitle(offset: meal.dayOffset))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            Text(meal.title)
                .font(.subheadline.weight(.semibold))
            Text(label.title)
                .font(.footnote)
                .foregroundStyle(label == .needsDecision ? Theme.accent : Theme.secondaryText)
            if session.showsPartnerControls {
                HouseholdPartnerMealControls(mealID: meal.id, session: session)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var preferenceSection: some View {
        Section {
            weekdayPicker
            Picker("Hafta içi süre", selection: $maxMinutes) {
                ForEach(CookTimeOptions.minutes, id: \.self) { minutes in
                    Text(CookTimeOptions.label(minutes)).tag(minutes)
                }
            }
            TextField("Tercih edilen türler", text: $categories)
                .accessibilityHint("Virgülle ayır. Kişisel sevmediklerin buraya kopyalanmaz.")
            TextField("Tercih edilen protein", text: $proteins)
            TextField("Evde kaçınılan malzeme", text: $avoided)
            Button("Ev tercihlerini kaydet") {
                session.updatePreference(
                    cookingDays: cookingDays.sorted(),
                    maxWeekdayMinutes: maxMinutes,
                    preferredCategories: categories,
                    preferredProteins: proteins,
                    avoidedIngredients: avoided,
                    in: modelContext
                )
            }
        } header: {
            Text("Ev tercihleri")
        } footer: {
            Text("Bunlar evin ortak ayarı. Kişisel yemek hafızan burada durmaz.")
        }
    }

    private var weekdayPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pişirme günleri")
                .font(.subheadline)
            FlowLayout(spacing: 8) {
                ForEach(0..<7, id: \.self) { offset in
                    FilterChip(
                        title: WeekCalendar.dayTitle(offset: offset),
                        isSelected: cookingDays.contains(offset),
                        hint: "Bu günü ortak plana alır"
                    ) {
                        if cookingDays.contains(offset) {
                            cookingDays.remove(offset)
                        } else {
                            cookingDays.insert(offset)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var activitySection: some View {
        Section {
            if session.snapshot.activities.isEmpty {
                Text("Henüz ortak bir karar yok.")
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(session.snapshot.activities) { activity in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activity.actorName)
                            .font(.subheadline.weight(.semibold))
                        Text("\(activity.mealTitle) · \(activity.detail)")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(activity.actorName), \(activity.mealTitle), \(activity.detail)")
                }
            }
        } header: {
            Text("Kararlar")
        } footer: {
            Text("Bu bir akış değil. Planın nasıl bu hale geldiğini gösterir.")
        }
    }

    @ViewBuilder
    private var dangerSection: some View {
        Section {
            if session.snapshot.role(of: session.account?.id ?? "") == .owner {
                Button("Ev halkını sil", role: .destructive) {
                    session.deleteHousehold(in: modelContext)
                }
                .accessibilityHint("Ortak planı siler. Kişisel hafıza ve tarifler kalır.")
            } else {
                Button("Ev halkından ayrıl", role: .destructive) {
                    session.leave(in: modelContext)
                }
            }
            Button(session.isTestMode ? "Test oturumunu kapat" : "Apple oturumunu kapat") {
                session.signOut(in: modelContext)
            }
        }
    }

    private var pendingInvite: HouseholdInvite? {
        session.snapshot.invites.last { $0.status == .pending && $0.expiresAt > .now }
    }

    private func loadPreference() {
        guard let preference = session.snapshot.preference else { return }
        cookingDays = Set(preference.cookingDays)
        maxMinutes = preference.maxWeekdayMinutes
        categories = preference.preferredCategories.joined(separator: ", ")
        proteins = preference.preferredProteins.joined(separator: ", ")
        avoided = preference.avoidedIngredients.joined(separator: ", ")
    }
}

struct HouseholdReactionBar: View {
    var chrome: HouseholdMealChrome
    var isWorking: Bool
    var onReact: (MealReactionKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(chrome.rows) { row in
                HStack {
                    Text(row.name)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textCharcoal)
                    Spacer()
                    Text(row.symbol)
                        .accessibilityHidden(true)
                }
            }
            Label(chrome.label.title, systemImage: chrome.needsDecision ? "exclamationmark.triangle" : "checkmark.circle")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(chrome.needsDecision ? Theme.accent : Theme.sage)
            HStack(spacing: 8) {
                ForEach(MealReactionKind.allCases) { kind in
                    Button {
                        onReact(kind)
                    } label: {
                        Text("\(kind.symbol) \(kind.title)")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(chrome.myReaction == kind ? Theme.accent : Theme.secondaryText)
                    .disabled(isWorking)
                    .accessibilityLabel(kind.title)
                    .accessibilityAddTraits(chrome.myReaction == kind ? .isSelected : [])
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct HouseholdSyncBanner: View {
    var state: HouseholdSyncState

    var body: some View {
        switch state {
        case .offline:
            Label("Çevrimdışı taslak", systemImage: "icloud.slash")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textCharcoal)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .mealCardSurface()
                .accessibilityLabel("Çevrimdışı. Ortak plan bu telefonda duruyor.")
        case .syncing:
            HStack {
                ProgressView()
                Text("Ev halkı eşitleniyor…")
                    .font(.footnote)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .mealCardSurface()
        case .failed:
            Label("Eşitleme tamamlanamadı. Son sunucu hali açılınca gelir.", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.footnote)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .mealCardSurface()
        case .idle:
            EmptyView()
        }
    }
}
