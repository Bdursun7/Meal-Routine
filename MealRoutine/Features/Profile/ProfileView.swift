import SwiftData
import SwiftUI

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var prefs: [UserPrefs]
    @Query private var recipes: [Recipe]
    @State private var viewModel = ProfileViewModel()

    var body: some View {
        @Bindable var viewModel = self.viewModel
        NavigationStack {
            Form {
                Section("Ev") {
                    Stepper(value: $viewModel.householdSize, in: HouseholdSizeLimits.range) {
                        Text("Ev halkı: \(viewModel.householdSize)")
                    }
                    Stepper(value: $viewModel.evenings, in: 1...MealRecommender.eveningCap) {
                        Text("Akşam sayısı: \(viewModel.evenings)")
                    }
                    Picker("En fazla pişirme", selection: $viewModel.maxCookMinutes) {
                        ForEach(CookTimeOptions.minutes, id: \.self) { minutes in
                            Text(CookTimeOptions.label(minutes)).tag(minutes)
                        }
                    }
                    Button("Porsiyonu kaydet") {
                        viewModel.savePortions(in: modelContext)
                    }
                    Text("Ev halkını kaydetmek bu haftanın her akşamını aynı porsiyona çeker. Tarif detayı ve market aynı sayıyı kullanır. İşaretli market satırları durur.")
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

                Section("Katalog") {
                    Text("\(recipes.count) akşam tarifi yerelde yüklü.")
                    Text("Öneri motoru süreye, sevmediğin malzemeye, son yemeklere ve haftanın çeşitliliğine bakar. Hesap, reklam ve yapay zeka yok.")
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
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Sürüm \(appVersion)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Profil")
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
        }
        .onAppear {
            viewModel.load(prefs.min { $0.createdAt < $1.createdAt })
        }
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
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
