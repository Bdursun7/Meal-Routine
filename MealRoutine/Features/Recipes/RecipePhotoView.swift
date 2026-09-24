import ImageIO
import SwiftUI
import UIKit

/// Catalog photo, or a local plate when the file is missing, offline, or still loading.
struct RecipePhotoView: View {
    enum Layout {
        case hero
        case thumbnail
        /// Square plate for a replacement card.
        case plate
        /// Full-bleed photo behind a magazine card. The parent clips and credits it.
        case backdrop
    }

    private enum Phase: Equatable {
        case loading
        case shown
        /// Catalog has no HTTPS photo URL.
        case missing
        /// A URL exists, but the file is not cached and could not be fetched or decoded.
        case failed
    }

    var urlString: String
    var author: String
    var license: String
    var layout: Layout
    @Binding var isPhotoShown: Bool

    @State private var image: UIImage?
    @State private var phase: Phase

    init(
        urlString: String,
        author: String,
        license: String,
        layout: Layout,
        isPhotoShown: Binding<Bool>
    ) {
        self.urlString = urlString
        self.author = author
        self.license = license
        self.layout = layout
        _isPhotoShown = isPhotoShown
        let hasRemotePhoto = RecipePhoto.remoteURL(from: urlString) != nil
        _phase = State(initialValue: hasRemotePhoto ? .loading : .missing)
    }

    var body: some View {
        Color.clear
            .frame(maxWidth: fillsWidth ? .infinity : side)
            .frame(width: fillsWidth ? nil : side, height: layout == .backdrop ? nil : side)
            .frame(minHeight: layout == .backdrop ? 180 : nil)
            .overlay {
                ZStack {
                    if layout == .hero || layout == .backdrop {
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.92), Theme.accent.opacity(0.55), Theme.sage.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        Theme.accent.opacity(0.16)
                    }
                    if let image, phase == .shown {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        placeholderMark
                    }
                    if phase == .loading, layout == .hero || layout == .backdrop {
                        ProgressView()
                            .tint(Theme.onAccent)
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(phase == .shown ? .isImage : [])
            .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
            .task(id: urlString) {
                await load()
            }
    }

    private var fillsWidth: Bool {
        layout == .hero || layout == .backdrop
    }

    private var cornerRadius: CGFloat {
        switch layout {
        case .hero, .backdrop: 0
        case .thumbnail: 12
        case .plate: 16
        }
    }

    private var side: CGFloat {
        switch layout {
        case .hero: 220
        case .thumbnail: 64
        case .plate: 72
        case .backdrop: 180
        }
    }

    /// Stacked plate mark used when the catalog photo is missing or still loading.
    private var placeholderMark: some View {
        let isLarge = layout == .hero || layout == .backdrop
        return ZStack {
            Circle()
                .fill(Color.white.opacity(isLarge ? 0.22 : 0.9))
                .frame(width: isLarge ? 132 : 28, height: isLarge ? 132 : 28)
                .offset(x: isLarge ? -36 : -8, y: isLarge ? 10 : 2)
            Circle()
                .fill(Theme.sage.opacity(isLarge ? 0.55 : 0.9))
                .frame(width: isLarge ? 72 : 18, height: isLarge ? 72 : 18)
                .offset(x: isLarge ? 48 : 8, y: isLarge ? -28 : -6)
            Image(systemName: "fork.knife")
                .font(.system(size: isLarge ? 42 : 16, weight: .semibold))
                .foregroundStyle(isLarge ? Color.white : Theme.accent)
            if isLarge {
                Image(systemName: "leaf.fill")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .offset(x: -58, y: -42)
            }
        }
        .accessibilityHidden(true)
    }

    private var accessibilityText: String {
        switch phase {
        case .loading:
            "Fotoğraf yükleniyor"
        case .missing:
            "Fotoğraf yok"
        case .failed:
            "Fotoğraf yüklenemedi"
        case .shown:
            "Tarif fotoğrafı"
        }
    }

    private func load() async {
        image = nil
        isPhotoShown = false
        guard let remoteURL = RecipePhoto.remoteURL(from: urlString) else {
            phase = .missing
            return
        }
        phase = .loading
        let data = await RecipePhotoLoader.load(remoteURL: remoteURL)
        guard !Task.isCancelled else { return }
        guard let data else {
            phase = .failed
            return
        }
        let maxPixel: CGFloat = layout == .hero ? 1200 : (layout == .backdrop ? 800 : 256)
        let decoded = await Task.detached(priority: .userInitiated) {
            RecipePhotoDecoder.image(from: data, maxPixel: maxPixel)
        }.value
        guard let decoded else {
            RecipePhotoDiskCache.remove(
                remoteURL: remoteURL,
                directory: RecipePhotoDiskCache.defaultDirectory()
            )
            phase = .failed
            return
        }
        image = decoded
        phase = .shown
        isPhotoShown = true
    }
}

/// Photo credit from the catalog fields only. Hidden when both author and license are empty.
struct RecipePhotoCreditText: View {
    enum Style {
        /// Full author and license, wrapping. Used under the detail hero.
        case full
        /// One line for the author and one for the license. Used next to a thumbnail.
        case compact
    }

    var author: String
    var license: String
    var style: Style

    var body: some View {
        if let credit = RecipePhoto.creditLine(author: author, license: license) {
            creditBody(credit)
        }
    }

    @ViewBuilder
    private func creditBody(_ credit: String) -> some View {
        switch style {
        case .full:
            Text("Fotoğraf: \(credit)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Fotoğraf: \(credit)")
        case .compact:
            VStack(alignment: .leading, spacing: 0) {
                if !trimmed(author).isEmpty {
                    Text("Fotoğraf: \(trimmed(author))")
                        .lineLimit(1)
                    if !trimmed(license).isEmpty {
                        Text(trimmed(license))
                            .lineLimit(1)
                    }
                } else {
                    Text("Fotoğraf: \(trimmed(license))")
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Fotoğraf: \(credit)")
        }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum RecipePhotoDecoder {
    static func image(from data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel.rounded()),
        ]
        if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) {
            return UIImage(cgImage: cgImage)
        }
        return UIImage(data: data)
    }
}
