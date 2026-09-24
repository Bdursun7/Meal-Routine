import SwiftUI

/// Short local-only explanation. Not a legal policy.
struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Verilerin bu telefonda durur. Hesap yok, bulut yok.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Haftan, tercihlerin, puanların ve market listen cihazdan çıkmaz. Konum istenmez.")
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
                Text("Yerel veriyi sıfırla; tercihleri, haftalık planı, market listesini, pişirme geçmişini ve puanları siler. Tarif kataloğu kalır.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(Theme.cream.opacity(0.35))
        .navigationTitle("Gizlilik")
        .navigationBarTitleDisplayMode(.inline)
    }
}
