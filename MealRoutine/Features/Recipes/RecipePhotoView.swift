import ImageIO
import SwiftUI
import UIKit

/// Catalog photo, or a local plate when the file is missing, offline, or still loading.
struct RecipePhotoView: View {
    enum Layout {
        case hero
        case thumbnail
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
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .frame(maxWidth: layout == .hero ? .infinity : 64)
                .frame(width: layout == .thumbnail ? 64 : nil, height: layout == .hero ? 220 : 64)
                .overlay {
                    ZStack {
                        Theme.accent.opacity(0.16)
                        if let image, phase == .shown {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "fork.knife")
                                .font(.system(size: layout == .hero ? 36 : 18, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        if phase == .loading, layout == .hero {
                            ProgressView()
                                .tint(Theme.accent)
                                .padding(12)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        }
                    }
                }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: layout == .hero ? 14 : 10, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText)
                .accessibilityAddTraits(phase == .shown ? .isImage : [])

            if layout == .hero, phase == .shown {
                RecipePhotoCreditText(author: author, license: license, style: .full)
            }
            if layout == .hero, phase == .missing {
                Text("Fotoğraf yok")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: layout == .hero ? .infinity : nil, alignment: .leading)
        .task(id: urlString) {
            await load()
        }
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
        let maxPixel: CGFloat = layout == .hero ? 1600 : 256
        guard let decoded = RecipePhotoDecoder.image(from: data, maxPixel: maxPixel) else {
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
