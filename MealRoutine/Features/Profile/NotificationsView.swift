import SwiftUI

struct NotificationsView: View {
    @State private var sync = NotificationSync.shared

    var body: some View {
        Form {
            Section {
                Toggle("Bildirimler", isOn: toggle(\.masterEnabled, requestPermission: true))
                    .accessibilityIdentifier("notifications.master")
                if sync.permissionDenied {
                    Text("İzin kapalı. Telefon ayarlarından açabilirsin.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            } header: {
                Text("Genel")
            }
            Section {
                Toggle("Davet", isOn: toggle(\.invitesEnabled))
                Toggle("Haftalık plan", isOn: toggle(\.weeklyPlanEnabled))
                Toggle("Veto", isOn: toggle(\.mealVetoEnabled))
                Toggle("Yemek değişikliği", isOn: toggle(\.mealReplacementEnabled))
                Toggle("Plan kesinleşti", isOn: toggle(\.planFinalizedEnabled))
            } header: {
                Text("Olaylar")
            }
            if !sync.message.isEmpty {
                Section {
                    Text(sync.message)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .navigationTitle("Bildirimler")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await sync.load()
        }
    }

    private func toggle(
        _ keyPath: WritableKeyPath<NotificationPreferences, Bool>,
        requestPermission: Bool = false
    ) -> Binding<Bool> {
        Binding(
            get: { sync.preferences[keyPath: keyPath] },
            set: { value in
                var next = sync.preferences
                next[keyPath: keyPath] = value
                Task { await sync.save(next, requestPermission: requestPermission && value) }
            }
        )
    }
}
