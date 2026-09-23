import Foundation
import SwiftData

/// Fingerprint of the bundled catalog that was last written into SwiftData.
/// Lives in the same store as `Recipe`, so wiping the store also clears the gate.
@Model
final class CatalogImportState {
    var fingerprint: String
    var importedAt: Date

    init(fingerprint: String, importedAt: Date = .now) {
        self.fingerprint = fingerprint
        self.importedAt = importedAt
    }
}
