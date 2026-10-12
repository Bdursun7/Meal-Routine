import Foundation
import SwiftUI

struct ServerAddressSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var note = ""
    @State private var probing = false

    var body: some View {
        NavigationStack {
            Form {
                let resolution = MealRoutineConfig.currentResolution()
                Section {
                    Text(resolution.url?.absoluteString ?? APIBaseURLResolver.missingServerMessage)
                        .font(.footnote)
                        .textSelection(.enabled)
                    Text("Kaynak: \(resolution.source.title)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let remote = MealRoutineConfig.remoteConfigURL {
                        Text("Uzak yapılandırma: \(remote.absoluteString)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else {
                        Text("Uzak yapılandırma yok. Elle adres çalışır.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Etkin adres")
                }
                Section {
                    TextField("https://….trycloudflare.com", text: $draft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("serverAddress.field")
                    Button("Kaydet") { save() }
                        .accessibilityIdentifier("serverAddress.save")
                    Button("Elle adresi sil") { clearManual() }
                    Button("Son iyi adresi sil") { clearCache() }
                    Button(probing ? "Deneniyor…" : "Bağlantıyı dene") { Task { await probe() } }
                        .disabled(probing)
                    Button("Uzak adresi yenile") { Task { await refreshRemote() } }
                } header: {
                    Text("Elle adres")
                } footer: {
                    Text("Elle adres uzak JSON’dan önce gelir. Tünel yeniden başlayınca yeni https adresini yapıştır veya Gist güncellendikten sonra uzak adresi yenile. Oturum jetonu adrese bağlı değildir.")
                }
                if !note.isEmpty {
                    Section {
                        Text(note)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Sunucu adresi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .onAppear {
                draft = UserDefaults.standard.string(forKey: APIBaseURLResolver.manualKey) ?? ""
            }
        }
    }

    private func save() {
        guard let url = APIBaseURLResolver.normalize(draft) else {
            note = "Adres https olmalı. Yol ve kullanıcı bilgisi yazma. http yalnız localhost içindir."
            return
        }
        UserDefaults.standard.set(url.absoluteString, forKey: APIBaseURLResolver.manualKey)
        draft = url.absoluteString
        note = "Elle adres kaydedildi."
    }

    private func clearManual() {
        UserDefaults.standard.removeObject(forKey: APIBaseURLResolver.manualKey)
        draft = ""
        note = "Elle adres silindi."
    }

    private func clearCache() {
        UserDefaults.standard.removeObject(forKey: APIBaseURLResolver.cacheKey)
        note = "Son iyi adres silindi."
    }

    private func refreshRemote() async {
        await RemoteAPIConfigRefresher.refresh(force: true)
        let resolution = MealRoutineConfig.currentResolution()
        note = resolution.url.map { "Etkin adres \($0.absoluteString)" } ?? APIBaseURLResolver.missingServerMessage
    }

    private func probe() async {
        guard let base = MealRoutineConfig.currentResolution().url else {
            note = APIBaseURLResolver.missingServerMessage
            return
        }
        guard let url = APIClient.url(baseURL: base, path: "/health") else {
            note = APIBaseURLResolver.missingServerMessage
            return
        }
        probing = true
        defer { probing = false }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            if (200..<300).contains(status), body.contains("\"ok\":true") || body.contains("\"ok\": true") {
                note = "Sunucu yanıt verdi."
            } else {
                note = "Sunucu \(status) döndü."
            }
        } catch {
            note = "Sunucuya ulaşılamadı."
        }
    }
}
