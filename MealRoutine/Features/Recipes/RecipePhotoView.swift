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
    /// False while a tab switch is in flight. The row stays a placeholder and
    /// does not start a fetch that would finish on the main actor mid-animation.
    var loadsPhoto: Bool
    /// Local collection photo. Empty for catalog rows.
    var localImagePath: String
    @Binding var isPhotoShown: Bool

    @State private var image: UIImage?
    @State private var phase: Phase
    /// Pixel budget the current bitmap was decoded for. A list thumbnail must not
    /// be scaled up into the hero while the 960 px file is still loading.
    @State private var decodedForMaxPixel = 0
    @State private var imageToken = 0
    @State private var plateSize: CGSize = .zero
    @State private var painted: UIImage?
    @State private var paintedSlot: CGSize = .zero
    @State private var paintedToken = 0
    /// Bumped once the push animation can no longer be holding the source row's width.
    @State private var plateEpoch = 0
    @State private var loadTask: Task<Void, Never>?
    @State private var settleTask: Task<Void, Never>?
    @State private var activeLoadKey = ""
    @Environment(\.displayScale) private var displayScale

    init(
        urlString: String,
        author: String,
        license: String,
        layout: Layout,
        loadsPhoto: Bool = true,
        localImagePath: String = "",
        isPhotoShown: Binding<Bool>
    ) {
        self.urlString = urlString
        self.author = author
        self.license = license
        self.layout = layout
        self.loadsPhoto = loadsPhoto
        self.localImagePath = localImagePath
        _isPhotoShown = isPhotoShown
        let hasRemotePhoto = RecipePhoto.remoteURL(from: urlString) != nil
        let hasLocalPhoto = !localImagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        _phase = State(initialValue: (hasRemotePhoto || hasLocalPhoto) ? .loading : .missing)
    }

    var body: some View {
        measuredPlate
            .overlay {
                bitmapOverlay
                    .allowsHitTesting(false)
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(bitmapIsVisible ? .isImage : [])
            .transaction { transaction in
                transaction.animation = nil
            }
            .onAppear(perform: startLoad)
            .onChange(of: loadKey) { _, _ in
                startLoad()
            }
            .onDisappear {
                // The detail hero is one image. A list-to-list push can send
                // onDisappear without a later onAppear; cancelling there left
                // the spinner on `.loading` forever. Rows still cancel.
                guard layout != .hero else { return }
                loadTask?.cancel()
                loadTask = nil
                settleTask?.cancel()
                settleTask = nil
            }
    }

    /// Identity of the bytes this view should show. Empty while list rows are
    /// still waiting out the tab animation.
    private var loadKey: String {
        guard loadsPhoto else { return "" }
        return "\(urlString)|\(localImagePath)|\(fetchMaxPixel)"
    }

    /// Starts a fetch that is not SwiftUI's `.task`.
    ///
    /// `.task` on a row inside the detail `List` is cancelled when the push,
    /// a sheet, or a parent state write reconfigures the cell, and a stable id
    /// does not start it again. The hero then stays on the spinner. `UIImage?`
    /// is not `Equatable`, so assigning `image = nil` at the start of that task
    /// also invalidates the row even when the image was already nil.
    private func startLoad() {
        let key = loadKey
        guard !key.isEmpty else {
            if layout != .hero {
                loadTask?.cancel()
                loadTask = nil
            }
            return
        }
        if key == activeLoadKey, painted != nil { return }
        if key == activeLoadKey, let loadTask, !loadTask.isCancelled { return }
        loadTask?.cancel()
        activeLoadKey = key
        resetDecodedImage()
        loadTask = Task { @MainActor in
            await load()
        }
        watchSettledPlate()
    }

    /// The push animation's first width is the Tarifler row, not this list.
    /// Reading the plate again after that animation is what used to happen
    /// only once the credit line appeared — and the credit waits on the paint.
    private func watchSettledPlate() {
        guard layout == .hero else { return }
        settleTask?.cancel()
        settleTask = Task { @MainActor in
            // Push is about a third of a second. Read twice in case the first
            // pass is still the source row's width.
            for _ in 0..<2 {
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                plateEpoch += 1
            }
        }
    }

    private func resetDecodedImage() {
        // A 320 px thumbnail must not sit in the hero until the detail rendition arrives.
        if image != nil { image = nil }
        if painted != nil { painted = nil }
        paintedSlot = .zero
        paintedToken = 0
        imageToken = 0
        decodedForMaxPixel = 0
        if isPhotoShown { isPhotoShown = false }
        let hasRemotePhoto = RecipePhoto.remoteURL(from: urlString) != nil
        let hasLocalPhoto = !localImagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let next: Phase = (hasRemotePhoto || hasLocalPhoto) ? .loading : .missing
        if phase != next { phase = next }
    }

    /// Hero measures the plate, not the bitmap. The image stays in the overlay.
    ///
    /// A preference key inside this list row does not deliver the plate on a
    /// Tarifler push (list onto list). `plateSize` stayed zero, `paint` never
    /// ran, and the spinner stayed up after the JPEG had loaded. The credit
    /// line used to force the second pass, and it stays hidden until paint.
    @ViewBuilder
    private var measuredPlate: some View {
        if layout == .hero {
            // The push proposes the Tarifler row's width first (~300 pt). That
            // fails the plate check, and the credit line can no longer force a
            // second pass. `plateEpoch` reads this plate again after the push.
            photoPlate
                .background {
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: geo.size, initial: true) { _, newSize in
                                reportPlate(newSize)
                            }
                            .onChange(of: plateEpoch) { _, _ in
                                reportPlate(geo.size)
                            }
                    }
                }
        } else {
            photoPlate
        }
    }

    /// State writes during the list's layout pass are dropped, which left
    /// `plateSize` at zero. Apply the measurement on the next turn.
    private func reportPlate(_ size: CGSize) {
        let reported = size
        Task { @MainActor in
            applyReportedPlate(reported)
        }
    }

    private func applyReportedPlate(_ size: CGSize) {
        guard layout == .hero else { return }
        guard size.width > 1, size.height > 1 else { return }
        if heroSlotIsReady(plateSize), !heroSlotIsReady(size) {
            paint(in: plateSize)
            return
        }
        if !sameSlot(size, plateSize) {
            plateSize = size
        }
        paint(in: size)
    }

    private func heroSlotIsReady(_ size: CGSize) -> Bool {
        RecipePhoto.heroDrawSize(measuredWidth: Double(size.width), measuredHeight: Double(size.height)) != nil
    }

    @ViewBuilder
    private var bitmapOverlay: some View {
        if layout == .hero {
            // Already cropped to the plate. `.resizable` keeps the JPEG's pixel
            // size out of the list measurement; the frame is the plate.
            if let painted, paintedSlot.width > 1, paintedSlot.height > 1 {
                Image(uiImage: painted)
                    .resizable()
                    .frame(width: paintedSlot.width, height: paintedSlot.height)
            }
        } else {
            GeometryReader { geo in
                if let image, phase == .shown, canDrawBitmap(image), slotIsReady(geo.size) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            }
        }
    }

    /// Fixed plate. The placeholder stays until the overlay has a settled slot,
    /// so a cut-off measurement never becomes a visible bitmap.
    private var photoPlate: some View {
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
            placeholderMark
            if showsProgress {
                ProgressView()
                    .tint(Theme.onAccent)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .frame(minWidth: fillsWidth ? nil : side, minHeight: fixedHeight)
        .frame(width: fillsWidth ? nil : side, height: layout == .backdrop ? nil : fixedHeight)
        .frame(maxWidth: fillsWidth ? .infinity : side, minHeight: fixedHeight)
    }

    private func slotIsReady(_ size: CGSize) -> Bool {
        RecipePhoto.isReadyPhotoSlot(
            width: Double(size.width),
            height: Double(size.height),
            minimumWidth: Double(fixedHeight),
            minimumHeight: Double(fixedHeight),
            widerThanTall: layout == .hero
        )
    }

    private func sameSlot(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
    }

    /// Composite the hero into the settled plate. Until this runs, the placeholder stays.
    private func paint(in slot: CGSize) {
        guard layout == .hero else { return }
        guard let draw = RecipePhoto.heroDrawSize(
            measuredWidth: Double(slot.width),
            measuredHeight: Double(slot.height)
        ) else { return }
        let target = CGSize(width: draw.width, height: draw.height)
        guard let image,
              phase == .shown,
              decodedForMaxPixel == fetchMaxPixel,
              canDrawBitmap(image),
              let composited = RecipePhotoCompositor.image(image, filling: target, scale: displayScale)
        else { return }
        if painted != nil, paintedToken == imageToken, sameSlot(paintedSlot, target) { return }
        painted = composited
        paintedSlot = target
        paintedToken = imageToken
        isPhotoShown = true
    }

    /// A list cell can be measured at the full row width and height 0.
    /// A bitmap with either edge at 0 is the slot Core Animation refuses to create.
    private func canDrawBitmap(_ image: UIImage) -> Bool {
        image.size.width > 0 && image.size.height > 0 && fixedHeight > 0
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
        case .hero, .backdrop: fixedHeight
        case .thumbnail: 64
        case .plate: 72
        }
    }

    /// Positive on every layout. Backdrop may grow taller; it never collapses to 0.
    private var fixedHeight: CGFloat {
        switch layout {
        case .hero: CGFloat(RecipePhoto.heroPointHeight)
        case .thumbnail: 64
        case .plate: 72
        case .backdrop: 180
        }
    }

    /// Commons width to download. List rows stay at 320 so Tarifler can scroll.
    /// Detail from Tarifler and from Bu Hafta both use the hero rendition.
    private var displayRole: RecipePhoto.Role {
        switch layout {
        case .hero: .detailHero
        case .backdrop: .cardBackdrop
        case .thumbnail, .plate: .listThumbnail
        }
    }

    private var fetchMaxPixel: Int {
        displayRole.maxPixel
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

    private var showsProgress: Bool {
        guard layout == .hero || layout == .backdrop else { return false }
        if phase == .loading { return true }
        return layout == .hero && phase == .shown && painted == nil
    }

    private var bitmapIsVisible: Bool {
        if layout == .hero { return painted != nil }
        return phase == .shown
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
            if layout == .hero, painted == nil {
                "Fotoğraf yükleniyor"
            } else {
                "Tarif fotoğrafı"
            }
        }
    }

    private func load() async {
        let pixelBudget = fetchMaxPixel
        if RecipePhoto.remoteURL(from: urlString) == nil, let local = localBitmap() {
            adopt(local, pixelBudget: pixelBudget)
            return
        }
        guard let remoteURL = RecipePhoto.remoteURL(from: urlString) else {
            image = nil
            painted = nil
            isPhotoShown = false
            phase = .missing
            return
        }
        if image == nil {
            phase = .loading
        }
        let data = await RecipePhotoLoader.load(remoteURL: remoteURL, maxPixel: pixelBudget)
        guard !Task.isCancelled else { return }
        guard let data else {
            phase = .failed
            return
        }
        let decoded = await RecipePhotoDecodeGate.shared.image(from: data, maxPixel: CGFloat(pixelBudget))
        guard !Task.isCancelled else { return }
        guard pixelBudget == fetchMaxPixel else { return }
        guard let decoded, decoded.size.width > 0, decoded.size.height > 0 else {
            RecipePhotoDiskCache.remove(
                remoteURL: RecipePhoto.renditionURL(for: remoteURL, role: displayRole),
                directory: RecipePhotoDiskCache.defaultDirectory()
            )
            phase = .failed
            return
        }
        adopt(decoded, pixelBudget: pixelBudget)
    }

    private func adopt(_ bitmap: UIImage, pixelBudget: Int) {
        imageToken += 1
        image = bitmap
        decodedForMaxPixel = pixelBudget
        phase = .shown
        if layout == .hero {
            paint(in: plateSize)
            // A list-to-list push often never reports the 220 pt plate (the
            // preference is dropped, or the width is still the source row).
            // The hero is full-bleed, so the screen width is that plate.
            if painted == nil, let fallback = screenHeroPlate(), !sameSlot(fallback, plateSize) {
                plateSize = fallback
                paint(in: fallback)
            }
        } else {
            isPhotoShown = true
        }
    }

    /// Full-bleed hero band. Nil when the screen is narrower than the plate rule.
    private func screenHeroPlate() -> CGSize? {
        let sceneWidth = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.bounds.width }
            .first
        let width = sceneWidth ?? UIScreen.main.bounds.width
        let size = CGSize(width: width, height: CGFloat(RecipePhoto.heroPointHeight))
        guard heroSlotIsReady(size) else { return nil }
        return size
    }

    private func localBitmap() -> UIImage? {
        guard let url = RecipeCaptureStore.resolve(localImagePath),
              let image = UIImage(contentsOfFile: url.path),
              image.size.width > 0,
              image.size.height > 0 else { return nil }
        return image
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

/// Two decodes at a time. A list of visible rows used to decode every thumbnail
/// at once and then assign each bitmap on the main actor during the transition.
private actor RecipePhotoDecodeGate {
    static let shared = RecipePhotoDecodeGate(limit: 2)

    private let limit: Int
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(limit, 1)
    }

    func image(from data: Data, maxPixel: CGFloat) async -> UIImage? {
        guard await acquire() else { return nil }
        let decoded = await Task.detached(priority: .utility) {
            RecipePhotoDecoder.image(from: data, maxPixel: maxPixel)
        }.value
        release()
        return decoded
    }

    private func acquire() async -> Bool {
        if Task.isCancelled { return false }
        if inFlight < limit {
            inFlight += 1
            return true
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        if Task.isCancelled {
            release()
            return false
        }
        return true
    }

    private func release() {
        if !waiters.isEmpty {
            waiters.removeFirst().resume()
        } else {
            inFlight -= 1
        }
    }
}

private enum RecipePhotoDecoder {
    static func image(from data: Data, maxPixel: CGFloat) -> UIImage? {
        guard maxPixel >= 1 else { return nil }
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

/// Draws the final hero crop into a bitmap the size of the plate.
/// SwiftUI's first pass otherwise shows the source image at its pixel size.
private enum RecipePhotoCompositor {
    static func image(_ image: UIImage, filling slot: CGSize, scale: CGFloat) -> UIImage? {
        guard let rect = RecipePhoto.aspectFillRect(
            imageWidth: Double(image.size.width),
            imageHeight: Double(image.size.height),
            slotWidth: Double(slot.width),
            slotHeight: Double(slot.height)
        ) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale > 0 ? scale : 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: slot, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height))
        }
    }
}
