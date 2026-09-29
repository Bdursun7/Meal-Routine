import UIKit
import UniformTypeIdentifiers

/// Accepts one public URL or one block of text. Extra items are ignored.
final class ShareViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await ingest() }
    }

    private func ingest() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        let url = await firstURL(in: providers)
        let text = await firstText(in: providers)
        let caption = text == url?.absoluteString ? nil : text
        guard url != nil || (caption?.isEmpty == false) else {
            finish()
            return
        }
        let payload = SharedImportPayload(
            urlString: url?.absoluteString,
            text: caption,
            sourceHint: nil
        )
        do {
            try ShareHandoff.write(payload)
        } catch {
            finish()
            return
        }
        guard let openURL = URL(string: "mealroutine://import") else {
            finish()
            return
        }
        extensionContext?.open(openURL) { _ in
            self.finish()
        }
    }

    private func firstURL(in providers: [NSItemProvider]) async -> URL? {
        for provider in providers {
            if let url = await loadURL(from: provider) {
                return url
            }
        }
        return nil
    }

    private func firstText(in providers: [NSItemProvider]) async -> String? {
        for provider in providers {
            if let text = await loadText(from: provider) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        let identifiers = [UTType.url.identifier, UTType.plainText.identifier]
        for identifier in identifiers {
            guard provider.hasItemConformingToTypeIdentifier(identifier) else { continue }
            if let item = await loadItem(provider, identifier: identifier) as? URL {
                guard item.scheme?.hasPrefix("http") == true else { continue }
                return item
            }
            if let text = await loadItem(provider, identifier: identifier) as? String,
               let url = ShareHandoff.publicHTTPURL(text) {
                return url
            }
        }
        return nil
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) else { return nil }
        return await loadItem(provider, identifier: UTType.plainText.identifier) as? String
    }

    private func loadItem(_ provider: NSItemProvider, identifier: String) async -> NSSecureCoding? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
                continuation.resume(returning: item as? NSSecureCoding)
            }
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
