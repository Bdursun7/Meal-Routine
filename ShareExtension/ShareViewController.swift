import UIKit
import UniformTypeIdentifiers

/// Capture only. Persists a Quick Save, confirms, and closes. It does not download or parse a page.
final class ShareViewController: UIViewController {
    private let stack = UIStackView()
    private var capture: RecipeCapture?
    private var duplicateSlug: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        showMessage("Bakılıyor…")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await loadPayload() }
    }

    private func loadPayload() async {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        let url = await firstURL(in: providers)
        let texts = await allText(in: providers)
        let title = items.compactMap { $0.attributedTitle?.string }.first
            ?? items.compactMap { $0.attributedContentText?.string }.first
        let imagePath = await firstImagePath(in: providers)
        let hint = items.compactMap { $0.attributedTitle?.string }.first
        let assembled = SharePayloadAssembly.makeCapture(
            urls: url.map { [$0.absoluteString] } ?? [],
            titles: [title].compactMap { $0 },
            texts: texts,
            imagePath: imagePath,
            sourceHint: hint
        )
        guard let assembled else {
            showEmpty()
            return
        }
        capture = assembled
        duplicateSlug = RecipeCaptureStore.existingSlug(for: assembled)
        if duplicateSlug != nil {
            showDuplicate()
        } else {
            showPreview(assembled)
        }
    }

    private func showPreview(_ capture: RecipeCapture) {
        let title = capture.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (title?.isEmpty == false) ? title! : "Kaydedilen tarif"
        let source = RecipeSourceService.displayName(
            platform: capture.sourcePlatform,
            sourceTitle: capture.sourceTitleFallback,
            url: capture.urlString ?? ""
        )
        replaceContent(title: name, message: source, actions: [
            button("Deneyeceğim", primary: true) { [weak self] in self?.save(allowDuplicate: false) },
            button("Kapat", primary: false) { [weak self] in self?.finish() },
        ])
    }

    private func showDuplicate() {
        var actions = [
            button("Yine de kaydet", primary: true) { [weak self] in self?.save(allowDuplicate: true) },
        ]
        if let slug = duplicateSlug, slug != "pending" {
            actions.insert(button("Tarifi aç", primary: false) { [weak self] in
                self?.openApp("mealroutine://recipe?slug=\(slug.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? slug)")
            }, at: 0)
        }
        actions.append(button("Kapat", primary: false) { [weak self] in self?.finish() })
        replaceContent(
            title: "Bu kaynak zaten kayıtlı",
            message: "Aynı adres veya çok benzer bir ad sessizce üzerine yazılmaz.",
            actions: actions
        )
    }

    private func showSaved(id: UUID) {
        replaceContent(
            title: "Kaydedildi",
            message: "Denenecek tariflerin arasında. Malzeme şimdi gerekmez.",
            actions: [
                button("Bitti", primary: true) { [weak self] in self?.finish() },
                button("Şimdi tamamla", primary: false) { [weak self] in
                    self?.openApp("mealroutine://complete?capture=\(id.uuidString)")
                },
            ]
        )
    }

    private func showEmpty() {
        replaceContent(
            title: "Kaydedilecek bir şey yok",
            message: "Paylaşılan bağlantı, metin veya görsel bulunamadı.",
            actions: [button("Kapat", primary: true) { [weak self] in self?.finish() }]
        )
    }

    private func showMessage(_ text: String) {
        replaceContent(title: text, message: nil, actions: [])
    }

    private func save(allowDuplicate: Bool) {
        guard var capture else {
            showEmpty()
            return
        }
        capture.allowDuplicate = allowDuplicate
        do {
            try RecipeCaptureStore.enqueue(capture)
            showSaved(id: capture.id)
        } catch {
            replaceContent(
                title: "Kaydedilemedi",
                message: "Paylaşım klasörü yazılamadı. Simülatörde uygulama grubu imzası gerekir.",
                actions: [button("Kapat", primary: true) { [weak self] in self?.finish() }]
            )
        }
    }

    private func openApp(_ raw: String) {
        guard let url = URL(string: raw) else {
            finish()
            return
        }
        extensionContext?.open(url) { _ in
            self.finish()
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func replaceContent(title: String, message: String?, actions: [UIButton]) {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let heading = UILabel()
        heading.text = title
        heading.font = .preferredFont(forTextStyle: .title2)
        heading.numberOfLines = 0
        heading.textAlignment = .center
        stack.addArrangedSubview(heading)
        if let message, !message.isEmpty {
            let body = UILabel()
            body.text = message
            body.font = .preferredFont(forTextStyle: .body)
            body.textColor = .secondaryLabel
            body.numberOfLines = 0
            body.textAlignment = .center
            stack.addArrangedSubview(body)
        }
        for action in actions {
            stack.addArrangedSubview(action)
        }
    }

    private func button(_ title: String, primary: Bool, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        if primary {
            button.backgroundColor = UIColor(red: 0.72, green: 0.35, blue: 0.18, alpha: 1)
            button.setTitleColor(.white, for: .normal)
            button.layer.cornerRadius = 12
        }
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func firstURL(in providers: [NSItemProvider]) async -> URL? {
        for provider in providers {
            if let url = await loadURL(from: provider) { return url }
        }
        return nil
    }

    private func allText(in providers: [NSItemProvider]) async -> [String] {
        var texts: [String] = []
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                  let text = await loadItem(provider, identifier: UTType.plainText.identifier) as? String else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { texts.append(trimmed) }
        }
        return texts
    }

    private func firstImagePath(in providers: [NSItemProvider]) async -> String? {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if let url = await loadItem(provider, identifier: UTType.image.identifier) as? URL,
               let data = try? Data(contentsOf: url),
               let path = try? RecipeCaptureStore.saveImage(data, id: UUID()) {
                return path
            }
            if let image = await loadItem(provider, identifier: UTType.image.identifier) as? UIImage,
               let data = image.jpegData(compressionQuality: 0.85),
               let path = try? RecipeCaptureStore.saveImage(data, id: UUID()) {
                return path
            }
            if let data = await loadItem(provider, identifier: UTType.image.identifier) as? Data,
               let path = try? RecipeCaptureStore.saveImage(data, id: UUID()) {
                return path
            }
        }
        return nil
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        for identifier in [UTType.url.identifier, UTType.plainText.identifier] {
            guard provider.hasItemConformingToTypeIdentifier(identifier) else { continue }
            if let item = await loadItem(provider, identifier: identifier) as? URL,
               RecipeSourceService.publicURL(item.absoluteString) != nil {
                return item
            }
            if let text = await loadItem(provider, identifier: identifier) as? String,
               let url = RecipeSourceService.publicURL(text) {
                return url
            }
        }
        return nil
    }

    private func loadItem(_ provider: NSItemProvider, identifier: String) async -> NSSecureCoding? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }
}

private extension RecipeCapture {
    var sourceTitleFallback: String {
        title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
