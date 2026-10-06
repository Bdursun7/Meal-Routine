import SwiftData
import SwiftUI

struct LocalMigrationView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var migration = LocalMigrationCenter.shared

    var body: some View {
        Form {
            Section {
                if migration.record.phase == .uploading || migration.record.phase == .verifying {
                    HStack {
                        ProgressView()
                        Text(migration.record.headline)
                    }
                } else {
                    Text(migration.record.headline)
                }
                Text("Tarif: \(migration.record.recipes)")
                Text("Yemek hafızası: \(migration.record.memories)")
                Text("Geçmiş: \(migration.record.history)")
                    .accessibilityIdentifier("migration.counts")
                if migration.record.phase == .failed {
                    Button("Yeniden dene") {
                        Task { await migration.runIfNeeded(in: modelContext) }
                    }
                    .accessibilityIdentifier("migration.retry")
                }
                if migration.record.phase == .done {
                    Text("Telefondaki tarifler ve hafıza silinmedi.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .accessibilityIdentifier("migration.progress")
        }
        .navigationTitle("Aktarım")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await migration.runIfNeeded(in: modelContext)
        }
    }
}
