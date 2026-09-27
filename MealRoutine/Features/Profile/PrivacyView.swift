import SwiftUI

/// Short local-only explanation. Not a legal policy.
struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Verilerin bu telefonda durur. Hesap yok, bulut yok.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Haftan, tercihlerin, puanların, yemek hafızan, market listen ve içe aktardığın tarifler cihazdan çıkmaz. Kaynak adresi de bu telefonda kalır. Konum istenmez. Temel kişiselleştirme internet olmadan çalışır.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Tarif kataloğu uygulamayla birlikte gelir. Bir tarif fotoğrafı yalnızca önbellekte yoksa indirilir ve telefonda kalır.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Kullanım olayları, örneğin planın oluşması, yalnızca bu cihazdaki günlüğe yazılır. İsim veya hesap tutulmaz ve bir sunucuya gitmez.")
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
