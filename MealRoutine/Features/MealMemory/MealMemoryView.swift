import SwiftData
import SwiftUI

struct MealMemoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var recipes: [Recipe]
    @Query private var feedback: [RecipeFeedback]
    @Query private var memories: [MealMemory]
    @Query private var prefs: [UserPrefs]
    @State private var viewModel = MealMemoryViewModel()

    var body: some View {
        let stored = prefs.min { $0.createdAt < $1.createdAt }
        let summary = viewModel.summary(
            recipes: recipes,
            feedback: feedback,
            memories: memories,
            prefs: stored
        )
        List {
            if !summary.hasHistory {
                Section {
                    Text("Henüz yemek hafızan yok. Birkaç akşam pişirince favoriler, kaçındıkların ve temkinli örüntüler burada belirir.")
                        .font(.body)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    NavigationLink("Hafıza günlüğü") {
                        MealHistoryView()
                    }
                }
            } else {
                nameSection("Favorilerin", rows: summary.favoriteNames)
                nameSection("En çok pişirilenler", rows: summary.mostCooked)
                nameSection("Son sevilenler", rows: summary.recentLoved)
                if summary.patterns.isEmpty {
                    Section("Örüntüler") {
                        Text("En az üç kayıt olmadan kesin bir örüntü göstermiyoruz.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Section("Örüntüler") {
                        ForEach(summary.patterns) { pattern in
                            MealPatternCard(pattern: pattern) {
                                viewModel.dismiss(pattern.id, in: modelContext)
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                nameSection("Bir daha asla", rows: summary.neverAgain)
                nameSection("Kaçındığın malzemeler", rows: summary.avoidedIngredients)
                nameSection("Süresi ağır gelenler", rows: summary.timeConcerns)
                nameSection("Denediğin yeni tarifler", rows: summary.explored)
                nameSection("İlk kez giren kategoriler", rows: summary.firstCategories)
            }
            Section {
                if summary.hasHistory {
                    NavigationLink("Hafıza günlüğü") {
                        MealHistoryView()
                    }
                }
                Button("Yemek hafızasını sıfırla", role: .destructive) {
                    viewModel.isConfirmingReset = true
                }
                Text("Pişirme geçmişi, puanlar ve öğrenilen sinyaller silinir. Ev halkı, süre ve sevmediğin malzemeler kalır. Bu haftanın planı durur.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .navigationTitle("Yemek hafızan")
        .navigationBarTitleDisplayMode(.inline)
        .mealCanvas()
        .alert("Yemek hafızasını sıfırla?", isPresented: $viewModel.isConfirmingReset) {
            Button("Sıfırla", role: .destructive) {
                viewModel.reset(in: modelContext)
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Öğrenilen kayıtlar silinir. Kurulum tercihlerin kalır.")
        }
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
        .onAppear {
            if !summary.patterns.isEmpty {
                Analytics.trackOnce(.mealPatternViewed)
            }
        }
    }

    @ViewBuilder
    private func nameSection(_ title: String, rows: [String]) -> some View {
        if !rows.isEmpty {
            Section(title) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Text(row)
                        .foregroundStyle(Theme.textCharcoal)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
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
