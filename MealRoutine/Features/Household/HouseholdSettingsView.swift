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
    @State private var selectedCategories: Set<String> = []
    @State private var selectedProteins: Set<String> = []
    @State private var avoidedIds: Set<String> = []
    @State private var avoidedQuery = ""
    @State private var renameName = ""
    @State private var pendingAction: HouseholdDestructiveAction?
    @State private var migration = LocalMigrationCenter.shared

    var body: some View {
        Form {
            HouseholdTestModeSection(session: session, testMode: testMode)
            if migrationHoldsHousehold {
                migrationHoldSection
            } else {
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
        }
        .sheet(isPresented: Binding(get: { session.offersPantryTransfer }, set: { if !$0 { session.offersPantryTransfer = false } })) {
            PantryTransferSheet { choice in
                if let householdID = session.snapshot.household?.id, choice != .keepSeparate {
                    PantryTransferApply.apply(choice, householdID: householdID, in: modelContext)
                    Task { await PantryOutbox.flush(in: modelContext) }
                }
                session.resolvePantryTransfer()
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
        .onAppear {
            loadPreference()
            migration.refresh(accountId: session.account?.id, in: modelContext)
        }
        .onChange(of: session.snapshot.household?.name) { _, name in
            renameName = name ?? ""
        }
        .onChange(of: session.snapshot.preference?.revision) { _, _ in
            loadPreference()
        }
        .confirmationDialog(
            pendingAction?.title ?? "",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(pendingAction?.confirmTitle ?? "Onayla", role: .destructive) {
                let action = pendingAction
                pendingAction = nil
                guard let action else { return }
                perform(action)
            }
            Button("Vazgeç", role: .cancel) {
                pendingAction = nil
            }
        } message: {
            Text(pendingAction?.message ?? "")
        }
    }

    private func perform(_ action: HouseholdDestructiveAction) {
        switch action {
        case .remove(let userId, _):
            session.remove(memberId: userId, in: modelContext)
        case .cancelInvite(let inviteId):
            session.revoke(inviteId: inviteId, in: modelContext)
        case .reject(let code):
            session.rejectInvite(code: code, in: modelContext)
        case .leave:
            session.leave(in: modelContext)
        case .delete:
            session.deleteHousehold(in: modelContext)
        case .transfer(let userId, _):
            session.transferOwnership(to: userId, in: modelContext)
        }
    }

    private var migrationHoldsHousehold: Bool {
        LocalMigrationGate.blocksHousehold(
            testMode: testMode.isEnabled,
            apiConfigured: MealRoutineConfig.apiBaseURL != nil,
            signedIn: session.account != nil,
            phase: migration.record.phase,
            hasEligibleData: migration.hasEligibleData
        )
    }

    private var migrationHoldSection: some View {
        Section {
            Text("Ev halkı, kişisel veriler hesaba aktarıldıktan sonra açılır.")
            Text(migration.record.headline)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            NavigationLink("Aktarımı sürdür") {
                LocalMigrationView()
            }
            .accessibilityIdentifier("migration.open")
        } header: {
            Text("Aktarım")
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if session.syncState == .offline {
            Section {
                Label("Çevrimdışı. Değişiklik bu telefonda duruyor ve bağlantı gelince gider.", systemImage: "icloud.slash")
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
            } else {
                Text("Apple veya Google ile giriş. Ev halkı en fazla iki kişidir.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                AccountSignInButtons()
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
            Button("Daveti reddet", role: .destructive) {
                pendingAction = .reject(inviteCode)
            }
            .disabled(HouseholdInviteCode.normalize(inviteCode).count != HouseholdInviteCode.length)
            .accessibilityIdentifier("household.reject")
        } header: {
            Text("Davetlisin")
        }
    }

    private var membersSection: some View {
        let selfId = session.account?.id ?? ""
        let names = HouseholdWeekCopy.headline(members: session.snapshot.members, selfUserId: selfId)
        return Section {
            if let name = session.snapshot.household?.name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                Text(name)
                    .font(.headline)
            }
            if !names.isEmpty {
                Text(names)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            if session.snapshot.role(of: selfId) == .owner {
                TextField("Ev halkının yeni adı", text: $renameName)
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel("Ev halkının yeni adı")
                Button("Adı kaydet") {
                    session.renameHousehold(name: renameName, in: modelContext)
                }
                .disabled(renameName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("household.rename")
            }
            ForEach(session.snapshot.members) { member in
                let title = memberTitle(member)
                HStack {
                    Text(title)
                    Spacer()
                    Text(member.role == .owner ? "Ev sahibi" : "Üye")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityElement(children: .combine)
                if session.snapshot.role(of: selfId) == .owner, member.role == .member {
                    Button("Çıkar", role: .destructive) {
                        pendingAction = .remove(member.userId, title)
                    }
                    .accessibilityIdentifier("household.remove")
                    .accessibilityHint("\(title) ev halkından çıkar")
                    Button("Ev sahipliğini devret") {
                        pendingAction = .transfer(member.userId, title)
                    }
                    .accessibilityIdentifier("household.transfer")
                }
            }
        } header: {
            Text("Üyeler")
        }
    }

    private func memberTitle(_ member: HouseholdMember) -> String {
        let trimmed = member.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if member.userId.caseInsensitiveCompare(session.account?.id ?? "") == .orderedSame { return "Sen" }
        return "Üye"
    }

    @ViewBuilder
    private var inviteSection: some View {
        if session.snapshot.role(of: session.account?.id ?? "") == .owner,
           session.snapshot.members.count < HouseholdLimits.maxMembers {
            Section {
                if testMode.isEnabled, !session.showsPartnerControls {
                    Button("Test Partner katılsın") {
                        Task { await session.simulatePartnerJoin(in: modelContext) }
                    }
                    .accessibilityIdentifier("household.partnerJoin")
                    .accessibilityHint("Davet kodunu ikinci üye olarak kabul eder")
                }
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
                    Button("Daveti yeniden gönder") {
                        session.resendInvite(inviteId: invite.id, in: modelContext)
                    }
                    .accessibilityIdentifier("household.inviteResend")
                    Button("Daveti geri al", role: .destructive) {
                        pendingAction = .cancelInvite(invite.id)
                    }
                    .accessibilityIdentifier("household.inviteCancel")
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
            if testMode.isEnabled, session.showsPartnerControls {
                Text("Test Partner evde. Tepkiler ortak haftanın yemeklerinde ve Bu Hafta kartında. Market işareti Market’te.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                if session.snapshot.plan?.meals.isEmpty == false {
                    Button("Test Partner marketi işaretlesin") {
                        Task { await session.partnerCheckNextGrocery(in: modelContext) }
                    }
                    .accessibilityIdentifier("household.partner.grocery")
                }
            }
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
            categoryPicker
            proteinPicker
            avoidedPicker
            Button("Ev tercihlerini kaydet") {
                session.updatePreference(
                    cookingDays: cookingDays.sorted(),
                    maxWeekdayMinutes: maxMinutes,
                    preferredCategories: selectedCategories.sorted(),
                    preferredProteins: selectedProteins.sorted(),
                    avoidedIngredients: avoidedIds.sorted(),
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

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tercih edilen türler")
                .font(.subheadline)
            FlowLayout(spacing: 8) {
                ForEach(HouseholdPreferenceChoices.categories) { category in
                    FilterChip(
                        title: category.title,
                        isSelected: selectedCategories.contains(category.rawValue),
                        hint: "Bu türü ev tercihlerine ekler"
                    ) {
                        toggle(category.rawValue, in: &selectedCategories)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var proteinPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tercih edilen protein")
                .font(.subheadline)
            FlowLayout(spacing: 8) {
                ForEach(HouseholdPreferenceChoices.proteinKeys, id: \.self) { key in
                    FilterChip(
                        title: HouseholdPreferenceChoices.proteinTitle(key),
                        isSelected: selectedProteins.contains(key),
                        hint: "Bu proteini ev tercihlerine ekler"
                    ) {
                        toggle(key, in: &selectedProteins)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var avoidedPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Evde kaçınılan malzeme")
                .font(.subheadline)
            TextField("Malzeme ara", text: $avoidedQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("household.avoided.search")
            if !avoidedIds.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(avoidedIds.sorted(), id: \.self) { id in
                        FilterChip(
                            title: HouseholdPreferenceChoices.ingredientTitle(id),
                            isSelected: true,
                            hint: "Listeden çıkarır"
                        ) {
                            avoidedIds.remove(id)
                        }
                    }
                }
            }
            let query = avoidedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty {
                let matches = IngredientDictionary.shared.search(query, limit: 8)
                if matches.isEmpty {
                    Text("Eşleşen malzeme yok.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    ForEach(matches) { entry in
                        Button {
                            if avoidedIds.contains(entry.id) {
                                avoidedIds.remove(entry.id)
                            } else {
                                avoidedIds.insert(entry.id)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name)
                                    if !entry.synonyms.isEmpty {
                                        Text(entry.synonyms.prefix(3).joined(separator: ", "))
                                            .font(.caption)
                                            .foregroundStyle(Theme.secondaryText)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                if avoidedIds.contains(entry.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                        }
                        .accessibilityIdentifier("household.avoided.\(entry.id)")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func toggle(_ key: String, in selection: inout Set<String>) {
        if selection.contains(key) {
            selection.remove(key)
        } else {
            selection.insert(key)
        }
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
                if session.snapshot.members.count > 1 {
                    Button("Ayrıl ve ev sahipliğini devret", role: .destructive) {
                        pendingAction = .leave
                    }
                    .accessibilityIdentifier("household.leave")
                }
                Button("Ev halkını sil", role: .destructive) {
                    pendingAction = .delete
                }
                .accessibilityIdentifier("household.delete")
                .accessibilityHint("Evi kapatır. Kişisel hafıza ve tarifler kalır. Ortak plan evle kalır.")
            } else {
                Button("Ev halkından ayrıl", role: .destructive) {
                    pendingAction = .leave
                }
                .accessibilityIdentifier("household.leave")
            }
            Button(session.isTestMode ? "Test oturumunu kapat" : "Oturumu kapat") {
                session.signOut(in: modelContext)
            }
        }
    }

    private var pendingInvite: HouseholdInvite? {
        session.snapshot.invites.last { $0.status == .pending && $0.expiresAt > .now }
    }

    private func loadPreference() {
        renameName = session.snapshot.household?.name ?? ""
        guard let preference = session.snapshot.preference else {
            selectedCategories = []
            selectedProteins = []
            avoidedIds = []
            return
        }
        cookingDays = Set(preference.cookingDays)
        maxMinutes = preference.maxWeekdayMinutes
        selectedCategories = Set(HouseholdPreferenceChoices.categories(from: preference.preferredCategories))
        selectedProteins = Set(HouseholdPreferenceChoices.proteins(from: preference.preferredProteins))
        avoidedIds = Set(HouseholdPreferenceChoices.avoidedIds(from: preference.avoidedIngredients))
    }
}

private enum HouseholdDestructiveAction {
    case remove(String, String)
    case cancelInvite(UUID)
    case reject(String)
    case leave
    case delete
    case transfer(String, String)

    var title: String {
        switch self {
        case .remove(_, let name):
            "\(name) çıkarılsın mı?"
        case .cancelInvite:
            "Davet geri alınsın mı?"
        case .reject:
            "Davet reddedilsin mi?"
        case .leave:
            "Ev halkından ayrıl?"
        case .delete:
            "Ev halkı silinsin mi?"
        case .transfer(_, let name):
            "Ev sahipliği \(name) kişisine geçsin mi?"
        }
    }

    var confirmTitle: String {
        switch self {
        case .remove: "Çıkar"
        case .cancelInvite: "Geri al"
        case .reject: "Reddet"
        case .leave: "Ayrıl"
        case .delete: "Sil"
        case .transfer: "Devret"
        }
    }

    var message: String {
        switch self {
        case .remove:
            "Kişisel tarifleri ve hafızası silinmez. Ortak plan evde kalır."
        case .cancelInvite:
            "Kod artık kullanılamaz. İstersen yeni bir davet açabilirsin."
        case .reject:
            "Bu kodla katılmazsın. Kişisel verin durur."
        case .leave:
            "Kişisel verin durur. Ortak plan evde kalır. Ev sahibiysen sahiplik diğer üyeye geçer."
        case .delete:
            "Ev kapanır. Kişisel tariflerin ve hafızan silinmez. Ortak plan evle kalır."
        case .transfer:
            "Sen üye olursun. Ortak plan evde kalır. Kişisel verin durur."
        }
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
