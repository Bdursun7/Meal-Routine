import SwiftData
import SwiftUI

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    @Query private var prefs: [UserPrefs]
    @Query private var recipes: [Recipe]
    @Query private var feedback: [RecipeFeedback]
    @State private var viewModel = ProfileViewModel()

    var body: some View {
        @Bindable var viewModel = self.viewModel
        NavigationStack {
            Form {
                Section("Ev") {
                    Stepper(value: $viewModel.householdSize, in: HouseholdSizeLimits.range) {
                        Text("Ev halkı: \(viewModel.householdSize)")
                    }
                    Picker("Akşam sayısı", selection: $viewModel.evenings) {
                        ForEach(EveningCountOptions.values, id: \.self) { count in
                            Text(EveningCountOptions.label(count)).tag(count)
                        }
                    }
                    Picker("En fazla pişirme", selection: $viewModel.maxCookMinutes) {
                        ForEach(CookTimeOptions.minutes, id: \.self) { minutes in
                            Text(CookTimeOptions.label(minutes)).tag(minutes)
                        }
                    }
                    Button("Porsiyonu kaydet") {
                        viewModel.savePortions(in: modelContext)
                    }
                    Text("Ev halkını kaydetmek bu haftanın her akşamını aynı porsiyona çeker. Tarif detayı ve market aynı sayıyı kullanır. Miktarı değişen satırın işareti kalkar; aynı miktar işaretli kalır.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Bu haftayı yeniden kur") {
                        viewModel.rebuildWeek(in: modelContext)
                    }
                    Text("Yeniden kurmak bu haftanın yemeklerini ve market listesini baştan yazar. Az önce planlanan tarifler bir sonraki kurulumda geride kalır.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Sevmediğin malzemeler") {
                    let names = viewModel.dislikedNames(in: recipes)
                    if names.isEmpty {
                        Text("Yok")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(names.joined(separator: ", "))
                    }
                    Button("Kurulumu tekrar aç") {
                        viewModel.reopenOnboarding(in: modelContext)
                    }
                }

                Section("Yemek hafızan") {
                    NavigationLink {
                        MealMemoryView()
                    } label: {
                        Text("Yemek hafızan")
                    }
                    .accessibilityHint("Favorileri, örüntüleri ve kaçınılanları açar")
                    Text("Pişirdiklerin ve puanların bir sonraki planı etkiler. Açık hafta kendiliğinden silinmez.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Sonraki plan") {
                    Picker("Keşif", selection: $viewModel.discovery) {
                        ForEach(DiscoveryLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    Text(viewModel.discovery.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Picker("Tekrar", selection: $viewModel.repetition) {
                        ForEach(RepeatPreference.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    Text(viewModel.repetition.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Picker("Zorluk", selection: $viewModel.difficultyPreference) {
                        ForEach(DifficultyPreference.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    Text(viewModel.difficultyPreference.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Picker("Hafta içi", selection: $viewModel.weekdayStyle) {
                        ForEach(WeekdayStyle.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    Text(viewModel.weekdayStyle.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Bu ayarlar bir sonraki plan kurulumunda kullanılır. Bu haftanın yemekleri kendiliğinden silinmez.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .onChange(of: viewModel.discovery) { _, _ in
                    viewModel.savePlanning(in: modelContext)
                }
                .onChange(of: viewModel.repetition) { _, _ in
                    viewModel.savePlanning(in: modelContext)
                }
                .onChange(of: viewModel.difficultyPreference) { _, _ in
                    viewModel.savePlanning(in: modelContext)
                }
                .onChange(of: viewModel.weekdayStyle) { _, _ in
                    viewModel.savePlanning(in: modelContext)
                }

                Section("Pişirme ve puanlar") {
                    NavigationLink {
                        CookingHistoryView()
                    } label: {
                        profileLink("Pişirme geçmişi", detail: "\(cookedCount)")
                    }
                    NavigationLink {
                        RatedRecipesView(kind: .loved)
                    } label: {
                        profileLink("Sevdiklerim", detail: "\(lovedCount)")
                    }
                    NavigationLink {
                        RatedRecipesView(kind: .neverAgain)
                    } label: {
                        profileLink("Bir daha asla", detail: "\(neverCount)")
                    }
                }

                Section("Katalog") {
                    Text("\(recipes.count) akşam tarifi yerelde yüklü.")
                    Text("Öneri motoru süreye, sevmediğin malzemeye, yemek hafızana ve haftanın çeşitliliğine bakar. Hesap, reklam ve yapay zeka yok.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Uygulama") {
                    Picker("Görünüm", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.inline)
                    .accessibilityHint("Açık, koyu veya sistem görünümünü seçer")
                    Text("Sistem, telefonun açık veya koyu ayarını kullanır.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        Text("Gizlilik")
                    }
                    .accessibilityHint("Verinin cihazda kaldığını açıklar")
                    Button("Yerel veriyi sıfırla", role: .destructive) {
                        viewModel.isConfirmingReset = true
                    }
                    Text("Tercihler, haftalık plan, market listesi, yemek hafızası ve puanlar silinir. Tarif kataloğu kalır.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Hakkında") {
                    Text(Attribution.uniTools)
                        .font(.footnote.weight(.semibold))
                        .textSelection(.enabled)
                    Text("Veri seti türevleri CC BY-SA 4.0 kapsamındadır. Uygulama kodu ayrı lisanslanabilir.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link("theunitools.com/en/data", destination: Attribution.landingURL)
                    Link("CC BY-SA 4.0", destination: Attribution.licenseURL)
                    Text("Özet ve adımlar, UniTools metninin Türkçe yerelleştirmesidir. İngilizce kaynak metin katalogda durur.")
                    Text("Özgün MealRoutine tarifleri ayrıca yazılmıştır. Bu satırlar UniTools lisansı taşımaz. Varsa fotoğrafları ayrı bir Commons kredisidir; yazar ve lisans tarif metninin lisansı değildir.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Tarif fotoğrafları katalogdaki yazar ve lisansla gösterilir. Açılmış bir fotoğraf cihazda kalır. Fotoğraf yoksa veya henüz indirilmediyse çatal-bıçak görseli durur. Hafta, market ve pişirme fotoğrafsız da çalışır.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Sürüm \(appVersion)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Profil")
            .mealCanvas()
            .alert("Güncellendi", isPresented: statusIsPresented) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(viewModel.statusMessage ?? "")
            }
            .alert("Kaydedilemedi", isPresented: errorIsPresented) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            // Centered system alert. confirmationDialog anchors under the nav bar on this tab.
            .alert(
                "Yerel veriyi sıfırla?",
                isPresented: $viewModel.isConfirmingReset
            ) {
                Button("Sıfırla", role: .destructive) {
                    viewModel.resetLocalData(in: modelContext)
                }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("Bu işlem geri alınamaz. Kurulum yeniden açılır.")
            }
        }
        .onAppear {
            viewModel.load(prefs.min { $0.createdAt < $1.createdAt })
        }
    }

    private var cookedCount: Int {
        feedback.filter(\.cooked).count
    }

    private var lovedCount: Int {
        FeedbackIndex.latestRatings(in: feedback).values.filter { $0 == .loved }.count
    }

    private var neverCount: Int {
        FeedbackIndex.latestRatings(in: feedback).values.filter { $0 == .never }.count
    }

    private func profileLink(_ title: String, detail: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(detail)
                .foregroundStyle(.secondary)
        }
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "2"
        return "\(short) (\(build))"
    }

    private var statusIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.statusMessage != nil },
            set: { isPresented in
                if !isPresented { viewModel.statusMessage = nil }
            }
        )
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented { viewModel.errorMessage = nil }
            }
        )
    }
}

private enum RecipeLibraryKind {
    case loved
    case neverAgain

    var rating: MealRating {
        switch self {
        case .loved: .loved
        case .neverAgain: .never
        }
    }

    var title: String {
        switch self {
        case .loved: "Sevdiklerim"
        case .neverAgain: "Bir daha asla"
        }
    }

    var emptyTitle: String {
        switch self {
        case .loved: "Sevdiğin tarif yok"
        case .neverAgain: "Bir daha asla listen boş"
        }
    }

    var emptyDetail: String {
        switch self {
        case .loved: "Bir tarife Sevdim dersen burada durur."
        case .neverAgain: "Bir tarife Bir daha asla dersen sonraki planlarda çıkmaz ve burada durur."
        }
    }

    var systemImage: String {
        rating.systemImage
    }
}

private struct CookingHistoryView: View {
    @Query private var feedback: [RecipeFeedback]
    @Query private var recipes: [Recipe]

    private var rows: [RecipeFeedback] {
        feedback
            .filter(\.cooked)
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Group {
            if rows.isEmpty {
                ContentUnavailableView {
                    Label("Henüz pişirme yok", systemImage: "fork.knife")
                } description: {
                    Text("Bir tarifi pişirdiğinde tarih ve puan burada durur.")
                }
            } else {
                List(rows, id: \.uuid) { item in
                    NavigationLink {
                        RecipeDetailView(route: RecipeRoute(slug: item.recipeSlug), allowsCookBar: false)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recipeName(item.recipeSlug))
                                .font(.headline)
                            Text("\(cookedDate(item.createdAt)) · \(item.rating.title)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Pişirme geçmişi")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func recipeName(_ slug: String) -> String {
        recipes.first { $0.slug == slug }?.displayName ?? slug
    }

    private func cookedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

private struct RatedRecipesView: View {
    var kind: RecipeLibraryKind
    @Query private var feedback: [RecipeFeedback]
    @Query private var recipes: [Recipe]

    private var slugs: [String] {
        let latest = FeedbackIndex.latestRatings(in: feedback)
        return latest.compactMap { slug, rating in
            rating == kind.rating ? slug : nil
        }
        .sorted { lhs, rhs in
            recipeName(lhs).localizedStandardCompare(recipeName(rhs)) == .orderedAscending
        }
    }

    var body: some View {
        Group {
            if slugs.isEmpty {
                ContentUnavailableView {
                    Label(kind.emptyTitle, systemImage: kind.systemImage)
                } description: {
                    Text(kind.emptyDetail)
                }
            } else {
                List(slugs, id: \.self) { slug in
                    NavigationLink {
                        RecipeDetailView(route: RecipeRoute(slug: slug), allowsCookBar: false)
                    } label: {
                        Label(recipeName(slug), systemImage: kind.systemImage)
                    }
                }
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func recipeName(_ slug: String) -> String {
        recipes.first { $0.slug == slug }?.displayName ?? slug
    }
}
