import Foundation

/// Content gate for the bundled recipe catalog.
///
/// Seeding used to skip when the SwiftData recipe count matched the file. A same-sized
/// edit then never imported. The skip key is this fingerprint: `schemaVersion` plus a
/// stable digest of the catalog file bytes (the recipes payload as shipped).
///
/// A matching fingerprint still does not skip when the store holds fewer recipes than
/// the file. That count check is only a short-import guard. Equal counts with a new
/// fingerprint import again.
enum CatalogFingerprint {
    static func token(schemaVersion: Int, catalogFileBytes: Data) -> String {
        "\(schemaVersion):\(StableContentHash.fnv1a64Hex(catalogFileBytes))"
    }

    static func shouldSkipImport(
        storedFingerprint: String?,
        currentFingerprint: String,
        existingRecipeCount: Int,
        catalogRecipeCount: Int
    ) -> Bool {
        guard existingRecipeCount > 0, existingRecipeCount == catalogRecipeCount else {
            return false
        }
        guard let storedFingerprint, !storedFingerprint.isEmpty else {
            return false
        }
        return storedFingerprint == currentFingerprint
    }
}

/// Which planned-meal slugs no longer name a recipe, and how to repair that.
///
/// The current week is regenerated with the naive picker when it has an orphan and
/// preferences exist, so the week stays a full set of live dinners and grocery rebuild
/// has a coherent source. Deleting only the holes would leave a short week.
/// Orphans on any other week are removed and those weeks are not rewritten.
/// If the current week has orphans but onboarding is unfinished, those meals are
/// deleted in place instead of regenerated.
struct PlanRepairDecision: Equatable, Sendable {
    var regenerateCurrentWeek: Bool
    var slugsToDelete: [String]
}

enum PlanRepair {
    static func orphanedSlugs(plannedSlugs: [String], liveRecipeSlugs: Set<String>) -> [String] {
        var seen: Set<String> = []
        var orphans: [String] = []
        for slug in plannedSlugs where !liveRecipeSlugs.contains(slug) {
            if seen.insert(slug).inserted {
                orphans.append(slug)
            }
        }
        return orphans
    }

    static func decide(
        currentWeekSlugs: [String],
        otherWeekSlugs: [String],
        liveRecipeSlugs: Set<String>,
        canRegenerateCurrentWeek: Bool
    ) -> PlanRepairDecision {
        let currentOrphans = orphanedSlugs(
            plannedSlugs: currentWeekSlugs,
            liveRecipeSlugs: liveRecipeSlugs
        )
        let otherOrphans = orphanedSlugs(
            plannedSlugs: otherWeekSlugs,
            liveRecipeSlugs: liveRecipeSlugs
        )
        if !currentOrphans.isEmpty, canRegenerateCurrentWeek {
            return PlanRepairDecision(
                regenerateCurrentWeek: true,
                slugsToDelete: otherOrphans
            )
        }
        let leftovers = orphanedSlugs(
            plannedSlugs: currentWeekSlugs + otherWeekSlugs,
            liveRecipeSlugs: liveRecipeSlugs
        )
        return PlanRepairDecision(regenerateCurrentWeek: false, slugsToDelete: leftovers)
    }
}

/// 64-bit FNV-1a, lowercase hex. Same bytes hash the same on Apple and Linux.
///
/// Public test vectors: `""` → `cbf29ce484222325`, `"a"` → `af63dc4c8601ec8c`,
/// `"foobar"` → `85944171f73967e8`. `Tools/catalog_integrity_check.py` locks these
/// and the skip / orphan decisions to this file.
enum StableContentHash {
    static func fnv1a64Hex(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hex(hash)
    }

    private static func hex(_ value: UInt64) -> String {
        let digits = Array("0123456789abcdef")
        var remainder = value
        var characters = Array(repeating: Character("0"), count: 16)
        for index in stride(from: 15, through: 0, by: -1) {
            characters[index] = digits[Int(remainder & 0xf)]
            remainder >>= 4
        }
        return String(characters)
    }
}
