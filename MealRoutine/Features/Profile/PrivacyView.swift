import SwiftUI

/// Short local-only explanation. Not a legal policy.
struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Kişisel plan, puanlar ve yemek hafızan bu telefonda durur. Ev halkına katılmazsan buluta çıkmaz.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Tek başına kullanırken haftan, tercihlerin, puanların, yemek hafızan, market listen ve kaydettiğin tarifler cihazdan çıkmaz. Ev halkı kurarsan ortak plan, tepkiler, market işaretleri ve planlama için gereken kısa sinyaller iCloud üzerinden yalnızca o iki kişiye gider. Kişisel hafıza kopyalanmaz. Konum istenmez.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Tarif kataloğu uygulamayla birlikte gelir. Bir tarif fotoğrafı yalnızca önbellekte yoksa indirilir ve telefonda kalır.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Kullanım olayları, örneğin planın oluşması, yalnızca bu cihazdaki günlüğe yazılır. Apple kimliği yalnızca ev halkı açıldığında saklanır ve reklam için kullanılmaz.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Yerel veriyi sıfırla; tercihleri, haftalık planı, market listesini, pişirme geçmişini, puanları ve içe aktardığın tarifleri siler. Hazır katalog kalır.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(Theme.canvas)
        .navigationTitle("Gizlilik")
        .navigationBarTitleDisplayMode(.inline)
    }
}
