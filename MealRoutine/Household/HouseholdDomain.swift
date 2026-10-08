import Foundation

/// V4 household planning. Personal meal memory stays on the device.
/// These types are the shared plan, not a copy of anyone's private history.
enum HouseholdLimits {
    static let maxMembers = 2
    static let inviteLifetime: TimeInterval = 7 * 24 * 60 * 60
    static let activityCap = 40
}

enum HouseholdRole: String, Codable, Sendable {
    case owner
    case member
}

enum HouseholdInviteStatus: String, Codable, Sendable {
    case pending
    case accepted
    case revoked
    case expired
    case rejected
}

enum MealReactionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case want
    case okay
    case veto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .want: L10n.text("household.reaction.want", "İstiyorum")
        case .okay: L10n.text("household.reaction.okay", "Olur")
        case .veto: L10n.text("household.reaction.veto", "Bu hafta olmaz")
        }
    }

    var symbol: String {
        switch self {
        case .want: "❤️"
        case .okay: "👍"
        case .veto: "❌"
        }
    }
}

enum SharedMealStatus: String, Codable, Sendable {
    case proposed
    case accepted
    case vetoed
    case replaced
    case cooked

    var title: String {
        switch self {
        case .proposed: L10n.text("household.mealStatus.proposed", "Öneri")
        case .accepted: L10n.text("household.mealStatus.accepted", "Kabul")
        case .vetoed: L10n.text("household.mealStatus.vetoed", "Veto")
        case .replaced: L10n.text("household.mealStatus.replaced", "Değişti")
        case .cooked: L10n.text("household.mealStatus.cooked", "Pişti")
        }
    }
}

enum SharedPlanStatus: String, Codable, Sendable {
    case draft
    case needsDecisions
    case ready
    case inProgress
    case completed

    var title: String {
        switch self {
        case .draft: L10n.text("household.planStatus.draft", "Taslak")
        case .needsDecisions: L10n.text("household.planStatus.needsDecisions", "Karar gerekiyor")
        case .ready: L10n.text("household.planStatus.ready", "Hazır")
        case .inProgress: L10n.text("household.planStatus.inProgress", "Devam ediyor")
        case .completed: L10n.text("household.planStatus.completed", "Tamamlandı")
        }
    }
}

enum HouseholdActivityKind: String, Codable, Sendable {
    case householdCreated
    case memberJoined
    case memberRemoved
    case planGenerated
    case want
    case okay
    case veto
    case replacement
    case planFinalized
    case mealCooked
    case groceryChecked
}

enum HouseholdNotificationKind: String, Codable, Sendable {
    case planReview
    case veto
    case replacement
    case planFinalized
}

enum HouseholdExclusion: String, Equatable, Sendable {
    case neverAgain
    case currentHouseholdVeto
    case strongPersonalDislike
    case cookTime
    case householdAvoided
}

enum HouseholdError: Error, Equatable, LocalizedError, Sendable {
    case nameEmpty
    case alreadyInHousehold
    case notOwner
    case notMember
    case householdFull
    case inviteNotFound
    case inviteExpired
    case inviteRevoked
    case inviteClosed
    case alreadyMember
    case duplicateInvite
    case mealNotFound
    case noAlternative
    case planNotReady
    case notSignedIn
    case sessionExpired
    case offline
    case syncFailed(String)
    case regional(RegionalErrorCode)

    var errorDescription: String? {
        switch self {
        case .nameEmpty:
            L10n.text("household.error.nameEmpty", "Ev halkına bir ad ver.")
        case .alreadyInHousehold:
            L10n.text("household.error.alreadyInHousehold", "Zaten bir ev halkındasın. V4'te tek ev vardır.")
        case .notOwner:
            L10n.text("household.error.notOwner", "Bunu yalnızca ev sahibi yapabilir.")
        case .notMember:
            L10n.text("household.error.notMember", "Bu ev halkının üyesi değilsin.")
        case .householdFull:
            L10n.text("household.error.householdFull", "Bu ev iki kişiyle dolu.")
        case .inviteNotFound:
            L10n.text("household.error.inviteNotFound", "Davet kodu bulunamadı.")
        case .inviteExpired:
            L10n.text("household.error.inviteExpired", "Bu davetin süresi dolmuş.")
        case .inviteRevoked:
            L10n.text("household.error.inviteRevoked", "Bu davet geri alınmış.")
        case .inviteClosed:
            L10n.text("household.error.inviteClosed", "Bu davet kullanılmış.")
        case .alreadyMember:
            L10n.text("household.error.alreadyMember", "Zaten bu ev halkındasın.")
        case .duplicateInvite:
            L10n.text("household.error.duplicateInvite", "Zaten açık bir davet var. Yeniden gönderebilir veya geri alabilirsin.")
        case .mealNotFound:
            L10n.text("household.error.mealNotFound", "Bu akşam planda yok.")
        case .noAlternative:
            L10n.text("household.error.noAlternative", "Bu filtrelere uyan başka tarif kalmadı.")
        case .planNotReady:
            L10n.text("household.error.planNotReady", "Plan henüz netleşmedi. Önce veto edilen akşamları çözün.")
        case .notSignedIn:
            L10n.text("household.error.notSignedIn", "Ev halkı için Apple ile giriş gerekir.")
        case .sessionExpired:
            L10n.text("household.error.sessionExpired", "Oturumun sona erdi. Tekrar giriş yap.")
        case .offline:
            L10n.text("household.error.offline", "iCloud şu an yok. Değişiklik bu telefonda duruyor.")
        case .syncFailed(let detail):
            L10n.format("household.error.syncFailed", "Eşitleme tamamlanamadı. %@", detail)
        case .regional(let code):
            code.message
        }
    }
}

struct HouseholdUser: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var displayName: String
    var createdAt: Date
}

struct Household: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var ownerId: String
    var createdAt: Date
    var revision: Int
    var baseRevision: Int
}

struct HouseholdMember: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var householdId: UUID
    var userId: String
    var displayName: String
    var role: HouseholdRole
    var joinedAt: Date
    var revision: Int
    var baseRevision: Int
}

struct HouseholdInvite: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var householdId: UUID
    var createdBy: String
    var inviteCode: String
    var expiresAt: Date
    var status: HouseholdInviteStatus
    /// CloudKit share URL, when the owner has published the household zone.
    var shareURL: String?
    var revision: Int
    var baseRevision: Int
}

struct HouseholdPreference: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var householdId: UUID
    var cookingDays: [Int]
    var maxWeekdayMinutes: Int
    var preferredCategories: [String]
    var preferredProteins: [String]
    var avoidedIngredients: [String]
    var revision: Int
    var baseRevision: Int
}

struct MealReaction: Equatable, Sendable, Identifiable {
    var id: UUID
    var sharedMealId: UUID
    var userId: String
    var reaction: MealReactionKind
    var createdAt: Date
    /// Server reaction revision. Missing on snapshots saved before sync, so decoding defaults to 0.
    var revision: Int

    init(
        id: UUID,
        sharedMealId: UUID,
        userId: String,
        reaction: MealReactionKind,
        createdAt: Date,
        revision: Int = 0
    ) {
        self.id = id
        self.sharedMealId = sharedMealId
        self.userId = userId
        self.reaction = reaction
        self.createdAt = createdAt
        self.revision = revision
    }
}

extension MealReaction: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, sharedMealId, userId, reaction, createdAt, revision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sharedMealId = try container.decode(UUID.self, forKey: .sharedMealId)
        userId = try container.decode(String.self, forKey: .userId)
        reaction = try container.decode(MealReactionKind.self, forKey: .reaction)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sharedMealId, forKey: .sharedMealId)
        try container.encode(userId, forKey: .userId)
        try container.encode(reaction, forKey: .reaction)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(revision, forKey: .revision)
    }
}

enum MealReactionRevisions {
    /// The fake server assigns a revision when an older snapshot still has 0.
    /// A revision the client already bumped is left alone.
    static func bumpForServerPush(_ incoming: inout HouseholdSnapshot, server: HouseholdSnapshot?) {
        guard var plan = incoming.plan else { return }
        var serverMeals: [UUID: SharedMeal] = [:]
        for meal in server?.plan?.meals ?? [] {
            serverMeals[meal.id] = meal
        }
        for mealIndex in plan.meals.indices {
            var previous: [String: MealReaction] = [:]
            for reaction in serverMeals[plan.meals[mealIndex].id]?.reactions ?? [] {
                previous[reaction.userId] = reaction
            }
            for reactionIndex in plan.meals[mealIndex].reactions.indices {
                var reaction = plan.meals[mealIndex].reactions[reactionIndex]
                if let prior = previous[reaction.userId] {
                    if reaction.revision <= prior.revision {
                        reaction.revision = reaction.reaction == prior.reaction ? prior.revision : prior.revision + 1
                    }
                } else if reaction.revision < 1 {
                    reaction.revision = 1
                }
                plan.meals[mealIndex].reactions[reactionIndex] = reaction
            }
        }
        incoming.plan = plan
    }
}

struct SharedMeal: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var planId: UUID
    var dayOffset: Int
    var recipeSlug: String
    var title: String
    /// Personal recipe owner. Planning can show the recipe without copying it.
    var recipeOwnerUserId: String?
    var status: SharedMealStatus
    var reactions: [MealReaction]
    var revision: Int
    var baseRevision: Int
    var updatedAt: Date
    var cookedAt: Date?
    var replacedAt: Date?
}

struct SharedMealPlan: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var householdId: UUID
    var weekStart: Date
    var status: SharedPlanStatus
    var isFinalized: Bool
    var meals: [SharedMeal]
    var revision: Int
    var baseRevision: Int
    var updatedAt: Date
}

/// What an activity row says, as a code. Rendered per display language by `HouseholdActivity`.
enum HouseholdActivityDetail: String, Codable, CaseIterable, Sendable {
    case householdCreated
    case memberJoined
    case memberRemoved
    case memberLeft
    case planCreated
    case want
    case okay
    case veto
    case replaced
    case cooked
    case planFinalized

    init(reaction: MealReactionKind) {
        switch reaction {
        case .want: self = .want
        case .okay: self = .okay
        case .veto: self = .veto
        }
    }

    /// Whole-week rows have no meal; their title is rendered, not stored.
    var isPlanLevel: Bool { self == .planCreated || self == .planFinalized }

    /// Text V5.0 and older clients read from `detail` / `mealTitle` in a synced snapshot. Fixed
    /// Turkish on purpose (it is wire data for those builds, like the server's legacy map); this
    /// build renders `text(subject:)` instead.
    func legacyText(subject: String) -> String {
        switch self {
        case .householdCreated: "Ev halkı kuruldu"
        case .memberJoined: "\(subject) katıldı"
        case .memberRemoved: "\(subject) çıkarıldı"
        case .memberLeft: "\(subject) ayrıldı"
        case .planCreated: "Ortak plan kuruldu"
        case .want: "İstiyorum"
        case .okay: "Olur"
        case .veto: "Bu hafta olmaz"
        case .replaced: "Yerine \(subject) geldi"
        case .cooked: "Pişti"
        case .planFinalized: "Plan netleşti"
        }
    }

    static let legacyPlanTitle = "Bu hafta"

    func text(subject: String) -> String {
        switch self {
        case .householdCreated: L10n.text("household.activity.created", "Ev halkı kuruldu")
        case .memberJoined: L10n.format("household.activity.memberJoined", "%@ katıldı", subject)
        case .memberRemoved: L10n.format("household.activity.memberRemoved", "%@ çıkarıldı", subject)
        case .memberLeft: L10n.format("household.activity.memberLeft", "%@ ayrıldı", subject)
        case .planCreated: L10n.text("household.activity.planCreated", "Ortak plan kuruldu")
        case .want: MealReactionKind.want.title
        case .okay: MealReactionKind.okay.title
        case .veto: MealReactionKind.veto.title
        case .replaced: L10n.format("household.activity.replaced", "Yerine %@ geldi", subject)
        case .cooked: L10n.text("household.activity.cooked", "Pişti")
        case .planFinalized: L10n.text("household.activity.planFinalized", "Plan netleşti")
        }
    }
}

struct HouseholdActivity: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var householdId: UUID
    var actorId: String
    var actorName: String
    var kind: HouseholdActivityKind
    /// Recipe or household name (user data). Plan-level rows carry the legacy "Bu hafta" text.
    var mealTitle: String
    /// Legacy Turkish sentence for V5.0 and older clients. Read only when `detailCode` is absent.
    var detail: String
    var createdAt: Date
    /// `HouseholdActivityDetail` raw value. A string so a code from a newer build still decodes.
    var detailCode: String? = nil
    /// Name the detail sentence refers to (member or recipe), user data only.
    var subject: String? = nil

    var detailKind: HouseholdActivityDetail? { detailCode.flatMap { HouseholdActivityDetail(rawValue: $0) } }

    var displayTitle: String {
        if detailKind?.isPlanLevel == true { return L10n.text("household.activity.planTitle", "Bu hafta") }
        return mealTitle
    }

    var displayDetail: String {
        guard let kind = detailKind else { return detail }
        return kind.text(subject: subject ?? "")
    }
}

struct HouseholdPush: Equatable, Sendable, Identifiable {
    var id: UUID
    var kind: HouseholdNotificationKind
    var title: String
    var body: String
}

struct HouseholdGroceryCompletion: Codable, Equatable, Sendable, Identifiable {
    var itemKey: String
    var isChecked: Bool
    var updatedAt: Date
    var updatedBy: String
    var revision: Int
    var baseRevision: Int

    var id: String { itemKey }
}

struct HouseholdMemorySignal: Codable, Equatable, Sendable, Identifiable {
    var recipeSlug: String
    var togetherCooked: Int
    var bothLiked: Int
    var splitReaction: Int
    var vetoCount: Int
    var selectedCount: Int
    var replacedCount: Int
    var skippedCount: Int
    var revision: Int
    var baseRevision: Int

    var id: String { recipeSlug }

    static func empty(slug: String) -> HouseholdMemorySignal {
        HouseholdMemorySignal(
            recipeSlug: slug,
            togetherCooked: 0,
            bothLiked: 0,
            splitReaction: 0,
            vetoCount: 0,
            selectedCount: 0,
            replacedCount: 0,
            skippedCount: 0,
            revision: 1,
            baseRevision: 0
        )
    }
}

/// Enough of a personal recipe for the other person to plan it.
/// Ownership stays `ownerUserId`. It is not inserted into their collection.
struct HouseholdRecipeProjection: Codable, Equatable, Sendable, Identifiable {
    var slug: String
    var ownerUserId: String
    var title: String
    var totalMinutes: Int
    var ingredientIds: [String]
    var protein: String
    var category: String
    var cuisine: String
    var diets: [String]
    var isReadyToCook: Bool
    var revision: Int
    var baseRevision: Int

    var id: String { slug }
}

struct MemberRecipeSignal: Codable, Equatable, Sendable {
    var lovedCount: Int
    var okayCount: Int
    var neverAgain: Bool
    var isFavorite: Bool
    var timesCooked: Int
    var timesReplaced: Int
    var latestRatingRaw: String
}

/// Compact scoring signals. This is not the personal meal-memory store.
struct MemberTasteProjection: Codable, Equatable, Sendable, Identifiable {
    var userId: String
    var displayName: String
    var dislikedIngredientIds: [String]
    var recipes: [String: MemberRecipeSignal]
    var updatedAt: Date
    var revision: Int
    var baseRevision: Int

    var id: String { userId }
}

struct MemberTaste: Equatable, Sendable {
    var userId: String
    var displayName: String
    var memories: [String: MealMemorySnapshot]
    var dislikedIngredientIds: Set<String>
}

struct HouseholdSnapshot: Codable, Equatable, Sendable {
    var household: Household?
    var members: [HouseholdMember]
    var invites: [HouseholdInvite]
    var preference: HouseholdPreference?
    var plan: SharedMealPlan?
    var activities: [HouseholdActivity]
    var groceryCompletions: [HouseholdGroceryCompletion]
    var memory: [HouseholdMemorySignal]
    var recipeProjections: [HouseholdRecipeProjection]
    var tasteProjections: [MemberTasteProjection]
    var revision: Int
    var baseRevision: Int
    var updatedAt: Date

    static func empty(now: Date = .now) -> HouseholdSnapshot {
        HouseholdSnapshot(
            household: nil,
            members: [],
            invites: [],
            preference: nil,
            plan: nil,
            activities: [],
            groceryCompletions: [],
            memory: [],
            recipeProjections: [],
            tasteProjections: [],
            revision: 0,
            baseRevision: 0,
            updatedAt: now
        )
    }

    var hasHousehold: Bool { household != nil }

    func member(_ userId: String) -> HouseholdMember? {
        members.first { $0.userId == userId }
    }

    func role(of userId: String) -> HouseholdRole? {
        member(userId)?.role
    }
}

enum HouseholdCodec {
    static func encode(_ snapshot: HouseholdSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    static func decode(_ data: Data) throws -> HouseholdSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(HouseholdSnapshot.self, from: data)
    }
}

enum HouseholdInviteCode {
    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static let length = 6

    static func make(seed: UInt64) -> String {
        var value = seed == 0 ? 1 : seed
        var chars: [Character] = []
        chars.reserveCapacity(length)
        for _ in 0..<length {
            chars.append(alphabet[Int(value % UInt64(alphabet.count))])
            value /= UInt64(alphabet.count)
            if value == 0 {
                value = seed &+ 0x9E37_79B9
            }
        }
        return String(chars)
    }

    static func normalize(_ raw: String) -> String {
        let upper = raw.uppercased()
        return String(upper.filter { alphabet.contains($0) })
    }
}

enum HouseholdInviteLink {
    static func url(for code: String) -> URL {
        URL(string: "mealroutine://household/join?code=\(HouseholdInviteCode.normalize(code))")!
    }

    static func code(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "mealroutine" else { return nil }
        let host = url.host?.lowercased()
        let path = url.path.lowercased()
        let isJoin = host == "household" && (path == "/join" || path.isEmpty || path == "/")
            || path.hasPrefix("/household/join")
        guard isJoin else { return nil }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let raw = items?.first { $0.name == "code" }?.value ?? ""
        let code = HouseholdInviteCode.normalize(raw)
        return code.count == HouseholdInviteCode.length ? code : nil
    }
}

enum HouseholdRecipeAccess {
    /// Ready projections are visible to every member. Ownership is unchanged.
    static func visibleForPlanning(
        _ projections: [HouseholdRecipeProjection]
    ) -> [HouseholdRecipeProjection] {
        projections.filter(\.isReadyToCook)
    }

    /// A partner recipe is never copied into the viewer's personal collection.
    static func copiesIntoPersonalCollection(
        _ projection: HouseholdRecipeProjection,
        viewerId: String
    ) -> Bool {
        _ = viewerId
        return false
    }

    static func isOwnedByViewer(
        _ projection: HouseholdRecipeProjection,
        viewerId: String
    ) -> Bool {
        projection.ownerUserId == viewerId
    }
}

enum HouseholdGroceryKey {
    static func make(ingredientId: String, unit: String, isManual: Bool, uuid: UUID) -> String {
        if isManual { return "manual:\(uuid.uuidString)" }
        return "\(ingredientId)|\(unit)"
    }
}

enum GroceryCompletionSync {
    /// Higher revision wins. The same revision uses the later timestamp.
    /// An exact tie adopts the server row.
    static func merge(
        local: HouseholdGroceryCompletion,
        server: HouseholdGroceryCompletion
    ) -> HouseholdGroceryCompletion {
        if server.revision != local.revision {
            return server.revision > local.revision ? adopting(server) : local
        }
        if server.updatedAt != local.updatedAt {
            return server.updatedAt > local.updatedAt ? adopting(server) : local
        }
        return adopting(server)
    }

    static func mergeLists(
        local: [HouseholdGroceryCompletion],
        server: [HouseholdGroceryCompletion]
    ) -> [HouseholdGroceryCompletion] {
        var byKey = Dictionary(uniqueKeysWithValues: server.map { ($0.itemKey, adopting($0)) })
        for item in local {
            if let existing = byKey[item.itemKey] {
                byKey[item.itemKey] = merge(local: item, server: existing)
            } else if item.revision != item.baseRevision {
                byKey[item.itemKey] = item
            }
        }
        return byKey.values.sorted { $0.itemKey < $1.itemKey }
    }

    private static func adopting(_ item: HouseholdGroceryCompletion) -> HouseholdGroceryCompletion {
        var copy = item
        copy.baseRevision = item.revision
        return copy
    }
}

enum HouseholdConflict {
    static func needsDecision(_ reactions: [MealReaction]) -> Bool {
        reactions.contains { $0.reaction == .veto }
    }

    static func label(
        reactions: [MealReaction],
        memberIds: [String]
    ) -> HouseholdCompatibilityLabel {
        if needsDecision(reactions) { return .needsDecision }
        let byUser = Dictionary(reactions.map { ($0.userId, $0.reaction) }, uniquingKeysWith: { _, latest in latest })
        let answered = memberIds.compactMap { byUser[$0] }
        if !memberIds.isEmpty, answered.count < memberIds.count { return .unsure }
        if answered.isEmpty { return .unsure }
        if answered.allSatisfy({ $0 == .want }) { return .greatMatch }
        return .goodMatch
    }
}

enum HouseholdCompatibilityLabel: String, Codable, Sendable {
    case greatMatch
    case goodMatch
    case unsure
    case needsDecision

    var title: String {
        switch self {
        case .greatMatch: L10n.text("household.match.greatMatch", "İkiniz için de uyumlu")
        case .goodMatch: L10n.text("household.match.goodMatch", "İyi uyum")
        case .unsure: L10n.text("household.match.unsure", "Biri henüz emin değil")
        case .needsDecision: L10n.text("household.match.needsDecision", "Karar gerekiyor")
        }
    }
}

enum HouseholdPlanRules {
    static func mealStatus(
        cookedAt: Date?,
        replacedAt: Date?,
        reactions: [MealReaction],
        memberIds: [String]
    ) -> SharedMealStatus {
        if cookedAt != nil { return .cooked }
        if HouseholdConflict.needsDecision(reactions) { return .vetoed }
        let answered = Set(reactions.map(\.userId))
        if !memberIds.isEmpty, memberIds.allSatisfy({ answered.contains($0) }) {
            return .accepted
        }
        if replacedAt != nil, reactions.isEmpty { return .replaced }
        return .proposed
    }

    static func planStatus(meals: [SharedMeal], isFinalized: Bool) -> SharedPlanStatus {
        if meals.isEmpty { return .draft }
        if meals.allSatisfy({ $0.status == .cooked }) { return .completed }
        if meals.contains(where: { $0.status == .vetoed || HouseholdConflict.needsDecision($0.reactions) }) {
            return .needsDecisions
        }
        if meals.contains(where: { $0.status == .cooked }) { return .inProgress }
        let settled = meals.allSatisfy { $0.status == .accepted || $0.status == .cooked }
        if settled { return isFinalized ? .ready : .ready }
        return .draft
    }

    static func refresh(_ plan: inout SharedMealPlan, memberIds: [String]) {
        for index in plan.meals.indices {
            plan.meals[index].status = mealStatus(
                cookedAt: plan.meals[index].cookedAt,
                replacedAt: plan.meals[index].replacedAt,
                reactions: plan.meals[index].reactions,
                memberIds: memberIds
            )
        }
        plan.status = planStatus(meals: plan.meals, isFinalized: plan.isFinalized)
        if plan.status == .needsDecisions {
            plan.isFinalized = false
        }
    }
}

struct HouseholdMealDraft: Equatable, Sendable {
    var dayOffset: Int
    var recipeSlug: String
    var title: String
    var recipeOwnerUserId: String?
    /// Set when a cooked evening is carried into the next shared plan.
    var cookedAt: Date? = nil
    /// Keeps the shared meal id so reactions and checks stay on that evening.
    var preservedID: UUID? = nil
}

enum HouseholdReducer {
    static func createHousehold(
        user: HouseholdUser,
        name: String,
        now: Date,
        householdId: UUID = UUID(),
        memberId: UUID = UUID(),
        preferenceId: UUID = UUID()
    ) throws -> HouseholdSnapshot {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HouseholdError.nameEmpty }
        var snapshot = HouseholdSnapshot.empty(now: now)
        snapshot.household = Household(
            id: householdId,
            name: trimmed,
            ownerId: user.id,
            createdAt: now,
            revision: 1,
            baseRevision: 0
        )
        snapshot.members = [
            HouseholdMember(
                id: memberId,
                householdId: householdId,
                userId: user.id,
                displayName: displayName(user),
                role: .owner,
                joinedAt: now,
                revision: 1,
                baseRevision: 0
            ),
        ]
        snapshot.preference = HouseholdPreference(
            id: preferenceId,
            householdId: householdId,
            cookingDays: [],
            maxWeekdayMinutes: 60,
            preferredCategories: [],
            preferredProteins: [],
            avoidedIngredients: [],
            revision: 1,
            baseRevision: 0
        )
        snapshot.revision = 1
        snapshot.baseRevision = 0
        snapshot.updatedAt = now
        append(
            &snapshot,
            kind: .householdCreated,
            actor: user,
            title: trimmed,
            code: .householdCreated,
            now: now
        )
        return snapshot
    }

    static func createInvite(
        snapshot: inout HouseholdSnapshot,
        user: HouseholdUser,
        now: Date,
        inviteId: UUID = UUID(),
        seed: UInt64
    ) throws -> HouseholdInvite {
        guard let household = snapshot.household else { throw HouseholdError.notMember }
        guard snapshot.role(of: user.id) == .owner else { throw HouseholdError.notOwner }
        guard snapshot.members.count < HouseholdLimits.maxMembers else { throw HouseholdError.householdFull }
        expireStaleInvites(&snapshot, now: now)
        if snapshot.invites.contains(where: { $0.status == .pending && $0.expiresAt > now }) {
            throw HouseholdError.duplicateInvite
        }
        let code = HouseholdInviteCode.make(seed: seed)
        let invite = HouseholdInvite(
            id: inviteId,
            householdId: household.id,
            createdBy: user.id,
            inviteCode: code,
            expiresAt: now.addingTimeInterval(HouseholdLimits.inviteLifetime),
            status: .pending,
            shareURL: nil,
            revision: 1,
            baseRevision: 0
        )
        snapshot.invites.append(invite)
        touch(&snapshot, now: now)
        return invite
    }

    static func revokeInvite(
        snapshot: inout HouseholdSnapshot,
        userId: String,
        inviteId: UUID,
        now: Date
    ) throws {
        guard snapshot.role(of: userId) == .owner else { throw HouseholdError.notOwner }
        guard let index = snapshot.invites.firstIndex(where: { $0.id == inviteId }) else {
            throw HouseholdError.inviteNotFound
        }
        snapshot.invites[index].status = .revoked
        snapshot.invites[index].revision += 1
        touch(&snapshot, now: now)
    }

    static func resendInvite(
        snapshot: inout HouseholdSnapshot,
        userId: String,
        inviteId: UUID,
        now: Date
    ) throws -> HouseholdInvite {
        guard snapshot.role(of: userId) == .owner else { throw HouseholdError.notOwner }
        guard let index = snapshot.invites.firstIndex(where: { $0.id == inviteId }) else {
            throw HouseholdError.inviteNotFound
        }
        switch snapshot.invites[index].status {
        case .pending, .expired:
            if snapshot.invites[index].status == .expired,
               snapshot.invites.contains(where: { $0.id != inviteId && $0.status == .pending && $0.expiresAt > now }) {
                throw HouseholdError.duplicateInvite
            }
            snapshot.invites[index].status = .pending
            snapshot.invites[index].expiresAt = now.addingTimeInterval(HouseholdLimits.inviteLifetime)
            snapshot.invites[index].revision += 1
        case .revoked, .accepted, .rejected:
            throw HouseholdError.inviteClosed
        }
        touch(&snapshot, now: now)
        return snapshot.invites[index]
    }

    static func rejectInvite(
        snapshot: inout HouseholdSnapshot,
        code: String,
        now: Date
    ) throws {
        guard snapshot.household != nil else { throw HouseholdError.inviteNotFound }
        let normalized = HouseholdInviteCode.normalize(code)
        guard let index = snapshot.invites.firstIndex(where: {
            HouseholdInviteCode.normalize($0.inviteCode) == normalized
        }) else {
            throw HouseholdError.inviteNotFound
        }
        var invite = snapshot.invites[index]
        switch invite.status {
        case .revoked:
            throw HouseholdError.inviteRevoked
        case .accepted, .rejected:
            throw HouseholdError.inviteClosed
        case .expired:
            throw HouseholdError.inviteExpired
        case .pending:
            break
        }
        if invite.expiresAt <= now {
            snapshot.invites[index].status = .expired
            snapshot.invites[index].revision += 1
            touch(&snapshot, now: now)
            throw HouseholdError.inviteExpired
        }
        invite.status = .rejected
        invite.revision += 1
        snapshot.invites[index] = invite
        touch(&snapshot, now: now)
    }

    static func rename(
        snapshot: inout HouseholdSnapshot,
        userId: String,
        name: String,
        now: Date
    ) throws {
        guard snapshot.role(of: userId) == .owner else { throw HouseholdError.notOwner }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HouseholdError.nameEmpty }
        guard snapshot.household != nil else { throw HouseholdError.notMember }
        snapshot.household?.name = trimmed
        snapshot.household?.revision += 1
        touch(&snapshot, now: now)
    }

    static func transferOwnership(
        snapshot: inout HouseholdSnapshot,
        actorId: String,
        memberUserId: String,
        now: Date
    ) throws {
        guard snapshot.role(of: actorId) == .owner else { throw HouseholdError.notOwner }
        guard memberUserId != actorId else { throw HouseholdError.notOwner }
        guard snapshot.member(memberUserId)?.role == .member else { throw HouseholdError.notMember }
        guard let ownerIndex = snapshot.members.firstIndex(where: { $0.userId == actorId }),
              let memberIndex = snapshot.members.firstIndex(where: { $0.userId == memberUserId }) else {
            throw HouseholdError.notMember
        }
        snapshot.members[ownerIndex].role = .member
        snapshot.members[ownerIndex].revision += 1
        snapshot.members[memberIndex].role = .owner
        snapshot.members[memberIndex].revision += 1
        snapshot.household?.ownerId = memberUserId
        snapshot.household?.revision += 1
        touch(&snapshot, now: now)
    }

    static func acceptInvite(
        snapshot: inout HouseholdSnapshot,
        user: HouseholdUser,
        code: String,
        now: Date,
        memberId: UUID = UUID()
    ) throws {
        guard let household = snapshot.household else { throw HouseholdError.inviteNotFound }
        if snapshot.member(user.id) != nil { throw HouseholdError.alreadyMember }
        guard snapshot.members.count < HouseholdLimits.maxMembers else { throw HouseholdError.householdFull }
        let normalized = HouseholdInviteCode.normalize(code)
        guard let index = snapshot.invites.firstIndex(where: {
            HouseholdInviteCode.normalize($0.inviteCode) == normalized
        }) else {
            throw HouseholdError.inviteNotFound
        }
        var invite = snapshot.invites[index]
        switch invite.status {
        case .revoked:
            throw HouseholdError.inviteRevoked
        case .accepted, .rejected:
            throw HouseholdError.inviteClosed
        case .expired:
            throw HouseholdError.inviteExpired
        case .pending:
            break
        }
        if invite.expiresAt <= now {
            snapshot.invites[index].status = .expired
            snapshot.invites[index].revision += 1
            touch(&snapshot, now: now)
            throw HouseholdError.inviteExpired
        }
        invite.status = .accepted
        invite.revision += 1
        snapshot.invites[index] = invite
        snapshot.members.append(
            HouseholdMember(
                id: memberId,
                householdId: household.id,
                userId: user.id,
                displayName: displayName(user),
                role: .member,
                joinedAt: now,
                revision: 1,
                baseRevision: 0
            )
        )
        append(
            &snapshot,
            kind: .memberJoined,
            actor: user,
            title: household.name,
            code: .memberJoined,
            subject: displayName(user),
            now: now
        )
        refreshPlan(&snapshot)
        touch(&snapshot, now: now)
    }

    static func removeMember(
        snapshot: inout HouseholdSnapshot,
        actorId: String,
        memberUserId: String,
        now: Date
    ) throws {
        guard snapshot.role(of: actorId) == .owner else { throw HouseholdError.notOwner }
        guard memberUserId != actorId else { throw HouseholdError.notOwner }
        guard let member = snapshot.member(memberUserId) else { throw HouseholdError.notMember }
        snapshot.members.removeAll { $0.userId == memberUserId }
        append(
            &snapshot,
            kind: .memberRemoved,
            actorId: actorId,
            actorName: snapshot.member(actorId)?.displayName ?? L10n.text("household.role.owner", "Ev sahibi"),
            householdId: snapshot.household?.id ?? UUID(),
            title: member.displayName,
            code: .memberRemoved,
            subject: member.displayName,
            now: now
        )
        refreshPlan(&snapshot)
        touch(&snapshot, now: now)
    }

    static func leave(
        snapshot: inout HouseholdSnapshot,
        userId: String,
        now: Date
    ) throws {
        guard let member = snapshot.member(userId) else { throw HouseholdError.notMember }
        if member.role == .owner {
            let others = snapshot.members.filter { $0.userId != userId }
            if others.isEmpty {
                snapshot = HouseholdSnapshot.empty(now: now)
                return
            }
            let next = others[0]
            snapshot.household?.ownerId = next.userId
            snapshot.household?.revision += 1
            if let index = snapshot.members.firstIndex(where: { $0.userId == next.userId }) {
                snapshot.members[index].role = .owner
                snapshot.members[index].revision += 1
            }
        }
        snapshot.members.removeAll { $0.userId == userId }
        append(
            &snapshot,
            kind: .memberRemoved,
            actorId: userId,
            actorName: member.displayName,
            householdId: snapshot.household?.id ?? UUID(),
            title: member.displayName,
            code: .memberLeft,
            subject: member.displayName,
            now: now
        )
        refreshPlan(&snapshot)
        touch(&snapshot, now: now)
    }

    static func deleteHousehold(
        snapshot: inout HouseholdSnapshot,
        userId: String
    ) throws -> HouseholdSnapshot {
        guard snapshot.role(of: userId) == .owner else { throw HouseholdError.notOwner }
        return HouseholdSnapshot.empty(now: snapshot.updatedAt)
    }

    static func updatePreference(
        snapshot: inout HouseholdSnapshot,
        userId: String,
        cookingDays: [Int],
        maxWeekdayMinutes: Int,
        preferredCategories: [String],
        preferredProteins: [String],
        avoidedIngredients: [String],
        now: Date
    ) throws {
        guard snapshot.member(userId) != nil else { throw HouseholdError.notMember }
        guard var preference = snapshot.preference, let household = snapshot.household else {
            throw HouseholdError.notMember
        }
        preference.householdId = household.id
        preference.cookingDays = Array(Set(cookingDays.filter { (0...6).contains($0) })).sorted()
        preference.maxWeekdayMinutes = max(15, maxWeekdayMinutes)
        preference.preferredCategories = preferredCategories
        preference.preferredProteins = preferredProteins
        preference.avoidedIngredients = avoidedIngredients
        preference.revision += 1
        snapshot.preference = preference
        touch(&snapshot, now: now)
    }

    static func installPlan(
        snapshot: inout HouseholdSnapshot,
        drafts: [HouseholdMealDraft],
        weekStart: Date,
        actor: HouseholdUser,
        now: Date,
        planId: UUID = UUID(),
        mealIds: [UUID] = []
    ) throws {
        guard let household = snapshot.household else { throw HouseholdError.notMember }
        guard snapshot.member(actor.id) != nil else { throw HouseholdError.notMember }
        let ids = mealIds.count == drafts.count ? mealIds : drafts.map { $0.preservedID ?? UUID() }
        let meals = drafts.enumerated().map { index, draft in
            SharedMeal(
                id: ids[index],
                planId: planId,
                dayOffset: draft.dayOffset,
                recipeSlug: draft.recipeSlug,
                title: draft.title,
                recipeOwnerUserId: draft.recipeOwnerUserId,
                status: draft.cookedAt == nil ? .proposed : .cooked,
                reactions: [],
                revision: 1,
                baseRevision: 0,
                updatedAt: now,
                cookedAt: draft.cookedAt,
                replacedAt: nil
            )
        }
        var plan = SharedMealPlan(
            id: planId,
            householdId: household.id,
            weekStart: weekStart,
            status: .draft,
            isFinalized: false,
            meals: meals,
            revision: 1,
            baseRevision: 0,
            updatedAt: now
        )
        HouseholdPlanRules.refresh(&plan, memberIds: snapshot.members.map(\.userId))
        snapshot.plan = plan
        for draft in drafts where draft.cookedAt == nil {
            var signal = snapshot.memory.first { $0.recipeSlug == draft.recipeSlug } ?? .empty(slug: draft.recipeSlug)
            signal.selectedCount += 1
            signal.revision += 1
            upsertMemory(signal, in: &snapshot)
        }
        append(
            &snapshot,
            kind: .planGenerated,
            actor: actor,
            title: "",
            code: .planCreated,
            now: now
        )
        touch(&snapshot, now: now)
    }

    @discardableResult
    static func setReaction(
        snapshot: inout HouseholdSnapshot,
        mealId: UUID,
        user: HouseholdUser,
        reaction: MealReactionKind,
        now: Date,
        reactionId: UUID = UUID()
    ) throws -> MealReaction {
        guard snapshot.member(user.id) != nil else { throw HouseholdError.notMember }
        guard var plan = snapshot.plan, let index = plan.meals.firstIndex(where: { $0.id == mealId }) else {
            throw HouseholdError.mealNotFound
        }
        var meal = plan.meals[index]
        let previousRevision = meal.reactions.first { $0.userId == user.id }?.revision ?? 0
        meal.reactions.removeAll { $0.userId == user.id }
        let stored = MealReaction(
            id: reactionId,
            sharedMealId: mealId,
            userId: user.id,
            reaction: reaction,
            createdAt: now,
            revision: previousRevision + 1
        )
        meal.reactions.append(stored)
        meal.revision += 1
        meal.updatedAt = now
        plan.meals[index] = meal
        plan.revision += 1
        plan.updatedAt = now
        snapshot.plan = plan
        if reaction == .veto {
            var signal = snapshot.memory.first { $0.recipeSlug == meal.recipeSlug } ?? .empty(slug: meal.recipeSlug)
            signal.vetoCount += 1
            signal.revision += 1
            upsertMemory(signal, in: &snapshot)
        }
        let kind: HouseholdActivityKind = switch reaction {
        case .want: .want
        case .okay: .okay
        case .veto: .veto
        }
        append(&snapshot, kind: kind, actor: user, title: meal.title, code: HouseholdActivityDetail(reaction: reaction), now: now)
        refreshPlan(&snapshot)
        touch(&snapshot, now: now)
        return stored
    }

    static func replaceMeal(
        snapshot: inout HouseholdSnapshot,
        mealId: UUID,
        slug: String,
        title: String,
        recipeOwnerUserId: String?,
        actor: HouseholdUser,
        now: Date
    ) throws {
        guard snapshot.member(actor.id) != nil else { throw HouseholdError.notMember }
        guard var plan = snapshot.plan, let index = plan.meals.firstIndex(where: { $0.id == mealId }) else {
            throw HouseholdError.mealNotFound
        }
        let previous = plan.meals[index].recipeSlug
        var signal = snapshot.memory.first { $0.recipeSlug == previous } ?? .empty(slug: previous)
        signal.replacedCount += 1
        signal.revision += 1
        upsertMemory(signal, in: &snapshot)
        plan.meals[index].recipeSlug = slug
        plan.meals[index].title = title
        plan.meals[index].recipeOwnerUserId = recipeOwnerUserId
        plan.meals[index].reactions = []
        plan.meals[index].replacedAt = now
        plan.meals[index].cookedAt = nil
        plan.meals[index].status = .replaced
        plan.meals[index].revision += 1
        plan.meals[index].updatedAt = now
        plan.revision += 1
        plan.updatedAt = now
        plan.isFinalized = false
        snapshot.plan = plan
        var selected = snapshot.memory.first { $0.recipeSlug == slug } ?? .empty(slug: slug)
        selected.selectedCount += 1
        selected.revision += 1
        upsertMemory(selected, in: &snapshot)
        append(&snapshot, kind: .replacement, actor: actor, title: title, code: .replaced, subject: title, now: now)
        refreshPlan(&snapshot)
        touch(&snapshot, now: now)
    }

    static func markCooked(
        snapshot: inout HouseholdSnapshot,
        mealId: UUID,
        actor: HouseholdUser,
        now: Date,
        cooked: Bool
    ) throws {
        guard snapshot.member(actor.id) != nil else { throw HouseholdError.notMember }
        guard var plan = snapshot.plan, let index = plan.meals.firstIndex(where: { $0.id == mealId }) else {
            throw HouseholdError.mealNotFound
        }
        plan.meals[index].cookedAt = cooked ? now : nil
        plan.meals[index].revision += 1
        plan.meals[index].updatedAt = now
        plan.revision += 1
        let meal = plan.meals[index]
        snapshot.plan = plan
        if cooked {
            var signal = snapshot.memory.first { $0.recipeSlug == meal.recipeSlug } ?? .empty(slug: meal.recipeSlug)
            signal.togetherCooked += 1
            let kinds = Set(meal.reactions.map(\.reaction))
            if kinds.contains(.want) || kinds.contains(.okay), !kinds.contains(.veto), meal.reactions.count >= 2 {
                signal.bothLiked += 1
            } else if kinds.contains(.veto) {
                signal.splitReaction += 1
            }
            signal.revision += 1
            upsertMemory(signal, in: &snapshot)
            append(&snapshot, kind: .mealCooked, actor: actor, title: meal.title, code: .cooked, now: now)
        }
        refreshPlan(&snapshot)
        touch(&snapshot, now: now)
    }

    static func finalize(
        snapshot: inout HouseholdSnapshot,
        actor: HouseholdUser,
        now: Date
    ) throws {
        guard snapshot.member(actor.id) != nil else { throw HouseholdError.notMember }
        guard var plan = snapshot.plan else { throw HouseholdError.mealNotFound }
        HouseholdPlanRules.refresh(&plan, memberIds: snapshot.members.map(\.userId))
        guard plan.status == .ready || plan.status == .inProgress else {
            throw HouseholdError.planNotReady
        }
        plan.isFinalized = true
        plan.revision += 1
        plan.updatedAt = now
        snapshot.plan = plan
        append(&snapshot, kind: .planFinalized, actor: actor, title: "", code: .planFinalized, now: now)
        refreshPlan(&snapshot)
        touch(&snapshot, now: now)
    }

    static func setGrocery(
        snapshot: inout HouseholdSnapshot,
        itemKey: String,
        isChecked: Bool,
        user: HouseholdUser,
        now: Date
    ) throws {
        guard snapshot.member(user.id) != nil else { throw HouseholdError.notMember }
        if let index = snapshot.groceryCompletions.firstIndex(where: { $0.itemKey == itemKey }) {
            snapshot.groceryCompletions[index].isChecked = isChecked
            snapshot.groceryCompletions[index].updatedAt = now
            snapshot.groceryCompletions[index].updatedBy = user.id
            snapshot.groceryCompletions[index].revision += 1
        } else {
            snapshot.groceryCompletions.append(
                HouseholdGroceryCompletion(
                    itemKey: itemKey,
                    isChecked: isChecked,
                    updatedAt: now,
                    updatedBy: user.id,
                    revision: 1,
                    baseRevision: 0
                )
            )
        }
        touch(&snapshot, now: now)
    }

    static func publishRecipes(
        snapshot: inout HouseholdSnapshot,
        projections: [HouseholdRecipeProjection],
        ownerId: String
    ) {
        var bySlug = Dictionary(uniqueKeysWithValues: snapshot.recipeProjections.map { ($0.slug, $0) })
        let owned = Set(snapshot.recipeProjections.filter { $0.ownerUserId == ownerId }.map(\.slug))
        let incoming = Set(projections.map(\.slug))
        for slug in owned.subtracting(incoming) {
            bySlug.removeValue(forKey: slug)
        }
        for var projection in projections where projection.ownerUserId == ownerId {
            if let existing = bySlug[projection.slug] {
                projection.baseRevision = existing.baseRevision
                projection.revision = existing.revision + 1
            }
            bySlug[projection.slug] = projection
        }
        snapshot.recipeProjections = bySlug.values.sorted { $0.slug < $1.slug }
    }

    static func publishTaste(
        snapshot: inout HouseholdSnapshot,
        projection: MemberTasteProjection
    ) {
        if let index = snapshot.tasteProjections.firstIndex(where: { $0.userId == projection.userId }) {
            var next = projection
            next.baseRevision = snapshot.tasteProjections[index].baseRevision
            next.revision = snapshot.tasteProjections[index].revision + 1
            snapshot.tasteProjections[index] = next
        } else {
            snapshot.tasteProjections.append(projection)
        }
    }

    static func attachShareURL(
        snapshot: inout HouseholdSnapshot,
        inviteId: UUID,
        shareURL: String
    ) {
        guard let index = snapshot.invites.firstIndex(where: { $0.id == inviteId }) else { return }
        snapshot.invites[index].shareURL = shareURL
        snapshot.invites[index].revision += 1
    }

    static func markSynced(_ snapshot: inout HouseholdSnapshot) {
        snapshot.baseRevision = snapshot.revision
        if var household = snapshot.household {
            household.baseRevision = household.revision
            snapshot.household = household
        }
        for index in snapshot.members.indices {
            snapshot.members[index].baseRevision = snapshot.members[index].revision
        }
        for index in snapshot.invites.indices {
            snapshot.invites[index].baseRevision = snapshot.invites[index].revision
        }
        if var preference = snapshot.preference {
            preference.baseRevision = preference.revision
            snapshot.preference = preference
        }
        if var plan = snapshot.plan {
            plan.baseRevision = plan.revision
            for index in plan.meals.indices {
                plan.meals[index].baseRevision = plan.meals[index].revision
            }
            snapshot.plan = plan
        }
        for index in snapshot.groceryCompletions.indices {
            snapshot.groceryCompletions[index].baseRevision = snapshot.groceryCompletions[index].revision
        }
        for index in snapshot.memory.indices {
            snapshot.memory[index].baseRevision = snapshot.memory[index].revision
        }
        for index in snapshot.recipeProjections.indices {
            snapshot.recipeProjections[index].baseRevision = snapshot.recipeProjections[index].revision
        }
        for index in snapshot.tasteProjections.indices {
            snapshot.tasteProjections[index].baseRevision = snapshot.tasteProjections[index].revision
        }
    }

    static func displayName(_ user: HouseholdUser) -> String {
        let trimmed = user.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? L10n.text("household.member.fallbackName", "Partner") : trimmed
    }

    private static func expireStaleInvites(_ snapshot: inout HouseholdSnapshot, now: Date) {
        for index in snapshot.invites.indices where snapshot.invites[index].status == .pending && snapshot.invites[index].expiresAt <= now {
            snapshot.invites[index].status = .expired
            snapshot.invites[index].revision += 1
        }
    }

    private static func touch(_ snapshot: inout HouseholdSnapshot, now: Date) {
        snapshot.revision += 1
        snapshot.updatedAt = now
    }

    private static func refreshPlan(_ snapshot: inout HouseholdSnapshot) {
        guard var plan = snapshot.plan else { return }
        HouseholdPlanRules.refresh(&plan, memberIds: snapshot.members.map(\.userId))
        snapshot.plan = plan
    }

    private static func upsertMemory(_ signal: HouseholdMemorySignal, in snapshot: inout HouseholdSnapshot) {
        if let index = snapshot.memory.firstIndex(where: { $0.recipeSlug == signal.recipeSlug }) {
            snapshot.memory[index] = signal
        } else {
            snapshot.memory.append(signal)
        }
    }

    private static func append(
        _ snapshot: inout HouseholdSnapshot,
        kind: HouseholdActivityKind,
        actor: HouseholdUser,
        title: String,
        code: HouseholdActivityDetail,
        subject: String = "",
        now: Date
    ) {
        append(
            &snapshot,
            kind: kind,
            actorId: actor.id,
            actorName: displayName(actor),
            householdId: snapshot.household?.id ?? UUID(),
            title: title,
            code: code,
            subject: subject,
            now: now
        )
    }

    private static func append(
        _ snapshot: inout HouseholdSnapshot,
        kind: HouseholdActivityKind,
        actorId: String,
        actorName: String,
        householdId: UUID,
        title: String,
        code: HouseholdActivityDetail,
        subject: String = "",
        now: Date
    ) {
        snapshot.activities.insert(
            HouseholdActivity(
                id: UUID(),
                householdId: householdId,
                actorId: actorId,
                actorName: actorName,
                kind: kind,
                mealTitle: code.isPlanLevel ? HouseholdActivityDetail.legacyPlanTitle : title,
                detail: code.legacyText(subject: subject),
                createdAt: now,
                detailCode: code.rawValue,
                subject: subject.isEmpty ? nil : subject
            ),
            at: 0
        )
        if snapshot.activities.count > HouseholdLimits.activityCap {
            snapshot.activities = Array(snapshot.activities.prefix(HouseholdLimits.activityCap))
        }
    }
}

enum HouseholdConflictResolver {
    /// Pending local edits survive only when the server row is still the base they edited.
    /// If the server moved, the server row replaces the local one.
    static func merge(local: HouseholdSnapshot, server: HouseholdSnapshot) -> HouseholdSnapshot {
        var result = server
        result.household = mergeHousehold(local: local.household, server: server.household)
        result.members = mergeMembers(local: local.members, server: server.members)
        result.invites = mergeInvites(local: local.invites, server: server.invites)
        result.preference = mergePreference(local: local.preference, server: server.preference)
        result.plan = mergePlan(local: local.plan, server: server.plan, memberIds: result.members.map(\.userId))
        result.groceryCompletions = mergeGrocery(local: local.groceryCompletions, server: server.groceryCompletions)
        result.memory = mergeMemory(local: local.memory, server: server.memory)
        result.recipeProjections = mergeRecipes(local: local.recipeProjections, server: server.recipeProjections)
        result.tasteProjections = mergeTastes(local: local.tasteProjections, server: server.tasteProjections)
        result.activities = mergeActivities(local: local.activities, server: server.activities)
        let pending = hasPending(result)
        result.revision = max(local.revision, server.revision)
        result.baseRevision = server.revision
        result.updatedAt = max(local.updatedAt, server.updatedAt)
        if pending {
            result.revision = max(result.revision, server.revision + 1)
        }
        return result
    }

    static func hasPending(_ snapshot: HouseholdSnapshot) -> Bool {
        if let household = snapshot.household, household.revision != household.baseRevision { return true }
        if snapshot.members.contains(where: { $0.revision != $0.baseRevision }) { return true }
        if snapshot.invites.contains(where: { $0.revision != $0.baseRevision }) { return true }
        if let preference = snapshot.preference, preference.revision != preference.baseRevision { return true }
        if let plan = snapshot.plan {
            if plan.revision != plan.baseRevision { return true }
            if plan.meals.contains(where: { $0.revision != $0.baseRevision }) { return true }
        }
        if snapshot.groceryCompletions.contains(where: { $0.revision != $0.baseRevision }) { return true }
        if snapshot.memory.contains(where: { $0.revision != $0.baseRevision }) { return true }
        if snapshot.recipeProjections.contains(where: { $0.revision != $0.baseRevision }) { return true }
        if snapshot.tasteProjections.contains(where: { $0.revision != $0.baseRevision }) { return true }
        return false
    }

    private static func mergeHousehold(local: Household?, server: Household?) -> Household? {
        switch (local, server) {
        case let (l?, s?):
            return keep(local: l, server: s, localRevision: l.revision, localBase: l.baseRevision, serverRevision: s.revision) { server in
                var copy = server
                copy.baseRevision = server.revision
                return copy
            }
        case let (nil, s?):
            var copy = s
            copy.baseRevision = s.revision
            return copy
        case let (l?, nil):
            return l.baseRevision == 0 ? l : nil
        case (nil, nil):
            return nil
        }
    }

    private static func mergePreference(local: HouseholdPreference?, server: HouseholdPreference?) -> HouseholdPreference? {
        switch (local, server) {
        case let (l?, s?):
            return keep(local: l, server: s, localRevision: l.revision, localBase: l.baseRevision, serverRevision: s.revision) { server in
                var copy = server
                copy.baseRevision = server.revision
                return copy
            }
        case let (nil, s?):
            var copy = s
            copy.baseRevision = s.revision
            return copy
        case let (l?, nil):
            return l.revision != l.baseRevision && l.baseRevision == 0 ? l : nil
        case (nil, nil):
            return nil
        }
    }

    private static func mergeMembers(local: [HouseholdMember], server: [HouseholdMember]) -> [HouseholdMember] {
        mergeRows(local: local, server: server, id: \.userId, revision: \.revision, base: \.baseRevision) { server in
            var copy = server
            copy.baseRevision = server.revision
            return copy
        }
    }

    private static func mergeInvites(local: [HouseholdInvite], server: [HouseholdInvite]) -> [HouseholdInvite] {
        mergeRows(local: local, server: server, id: \.id, revision: \.revision, base: \.baseRevision) { server in
            var copy = server
            copy.baseRevision = server.revision
            return copy
        }
    }

    private static func mergePlan(
        local: SharedMealPlan?,
        server: SharedMealPlan?,
        memberIds: [String]
    ) -> SharedMealPlan? {
        switch (local, server) {
        case let (l?, s?):
            var plan = s
            plan.meals = mergeRows(local: l.meals, server: s.meals, id: \.id, revision: \.revision, base: \.baseRevision) { server in
                var copy = server
                copy.baseRevision = server.revision
                return copy
            }.sorted { $0.dayOffset < $1.dayOffset }
            let mealsPending = plan.meals.contains { $0.revision != $0.baseRevision }
            if l.revision != l.baseRevision && s.revision == l.baseRevision && !mealsPending {
                plan.isFinalized = l.isFinalized
                plan.revision = l.revision
                plan.baseRevision = l.baseRevision
            } else if mealsPending {
                plan.revision = max(l.revision, s.revision) + 1
                plan.baseRevision = s.revision
            } else {
                plan.baseRevision = plan.revision
            }
            HouseholdPlanRules.refresh(&plan, memberIds: memberIds)
            return plan
        case let (nil, s?):
            var copy = s
            copy.baseRevision = s.revision
            return copy
        case let (l?, nil):
            return l.baseRevision == 0 ? l : nil
        case (nil, nil):
            return nil
        }
    }

    private static func mergeGrocery(
        local: [HouseholdGroceryCompletion],
        server: [HouseholdGroceryCompletion]
    ) -> [HouseholdGroceryCompletion] {
        mergeRows(local: local, server: server, id: \.itemKey, revision: \.revision, base: \.baseRevision) { server in
            var copy = server
            copy.baseRevision = server.revision
            return copy
        }
    }

    private static func mergeMemory(
        local: [HouseholdMemorySignal],
        server: [HouseholdMemorySignal]
    ) -> [HouseholdMemorySignal] {
        mergeRows(local: local, server: server, id: \.recipeSlug, revision: \.revision, base: \.baseRevision) { server in
            var copy = server
            copy.baseRevision = server.revision
            return copy
        }
    }

    private static func mergeRecipes(
        local: [HouseholdRecipeProjection],
        server: [HouseholdRecipeProjection]
    ) -> [HouseholdRecipeProjection] {
        mergeRows(local: local, server: server, id: \.slug, revision: \.revision, base: \.baseRevision) { server in
            var copy = server
            copy.baseRevision = server.revision
            return copy
        }
    }

    private static func mergeTastes(
        local: [MemberTasteProjection],
        server: [MemberTasteProjection]
    ) -> [MemberTasteProjection] {
        mergeRows(local: local, server: server, id: \.userId, revision: \.revision, base: \.baseRevision) { server in
            var copy = server
            copy.baseRevision = server.revision
            return copy
        }
    }

    private static func mergeActivities(
        local: [HouseholdActivity],
        server: [HouseholdActivity]
    ) -> [HouseholdActivity] {
        var byID: [UUID: HouseholdActivity] = [:]
        for item in server { byID[item.id] = item }
        for item in local { byID[item.id] = item }
        return byID.values.sorted { $0.createdAt > $1.createdAt }.prefix(HouseholdLimits.activityCap).map { $0 }
    }

    private static func keep<T>(
        local: T,
        server: T,
        localRevision: Int,
        localBase: Int,
        serverRevision: Int,
        adopt: (T) -> T
    ) -> T {
        let pending = localRevision != localBase
        if pending && serverRevision == localBase {
            return local
        }
        return adopt(server)
    }

    private static func mergeRows<T, ID: Hashable>(
        local: [T],
        server: [T],
        id: (T) -> ID,
        revision: (T) -> Int,
        base: (T) -> Int,
        adopt: (T) -> T
    ) -> [T] {
        var serverByID = Dictionary(uniqueKeysWithValues: server.map { (id($0), $0) })
        var localByID = Dictionary(uniqueKeysWithValues: local.map { (id($0), $0) })
        let ids = Set(serverByID.keys).union(localByID.keys)
        var merged: [T] = []
        for key in ids {
            let localRow = localByID.removeValue(forKey: key)
            let serverRow = serverByID.removeValue(forKey: key)
            switch (localRow, serverRow) {
            case let (l?, s?):
                merged.append(keep(local: l, server: s, localRevision: revision(l), localBase: base(l), serverRevision: revision(s), adopt: adopt))
            case let (nil, s?):
                merged.append(adopt(s))
            case let (l?, nil):
                let pending = revision(l) != base(l)
                if pending && base(l) == 0 {
                    merged.append(l)
                }
            case (nil, nil):
                break
            }
        }
        return merged
    }
}

enum HouseholdNotificationPolicy {
    static func make(
        activity: HouseholdActivity,
        recipientUserId: String
    ) -> HouseholdPush? {
        guard activity.actorId != recipientUserId else { return nil }
        let kind: HouseholdNotificationKind?
        let body: String
        switch activity.kind {
        case .planGenerated:
            kind = .planReview
            body = L10n.text("household.push.planReview", "Haftalık planın kararını bekliyor.")
        case .veto:
            kind = .veto
            body = L10n.format("household.push.veto", "%1$@, %2$@ için bu hafta olmaz dedi.", activity.actorName, activity.mealTitle)
        case .replacement:
            kind = .replacement
            body = L10n.format("household.push.replacement", "%1$@ yerine %2$@ önerdi.", activity.actorName, activity.mealTitle)
        case .planFinalized:
            kind = .planFinalized
            body = L10n.text("household.push.planFinalized", "Bu haftanın planı hazır.")
        case .householdCreated, .memberJoined, .memberRemoved, .want, .okay, .mealCooked, .groceryChecked:
            kind = nil
            body = ""
        }
        guard let kind else { return nil }
        return HouseholdPush(
            id: activity.id,
            kind: kind,
            title: "MealRoutine",
            body: body
        )
    }
}

enum MemberTasteProjectionBuilder {
    static func make(
        userId: String,
        displayName: String,
        memories: [String: MealMemorySnapshot],
        dislikedIngredientIds: Set<String>,
        now: Date
    ) -> MemberTasteProjection {
        var recipes: [String: MemberRecipeSignal] = [:]
        for (slug, memory) in memories where memory.hasPersonalSignal {
            recipes[slug] = MemberRecipeSignal(
                lovedCount: memory.lovedCount,
                okayCount: memory.okayCount,
                neverAgain: memory.neverAgain,
                isFavorite: memory.isFavorite,
                timesCooked: memory.timesCooked,
                timesReplaced: memory.timesReplaced,
                latestRatingRaw: memory.latestRating?.rawValue ?? ""
            )
        }
        return MemberTasteProjection(
            userId: userId,
            displayName: displayName,
            dislikedIngredientIds: dislikedIngredientIds.sorted(),
            recipes: recipes,
            updatedAt: now,
            revision: 1,
            baseRevision: 0
        )
    }

    static func taste(from projection: MemberTasteProjection) -> MemberTaste {
        var memories: [String: MealMemorySnapshot] = [:]
        for (slug, signal) in projection.recipes {
            memories[slug] = MealMemorySnapshot(
                recipeID: slug,
                timesCooked: signal.timesCooked,
                timesReplaced: signal.timesReplaced,
                lovedCount: signal.lovedCount,
                okayCount: signal.okayCount,
                latestRating: MealRating(rawValue: signal.latestRatingRaw),
                neverAgain: signal.neverAgain,
                isFavorite: signal.isFavorite
            )
        }
        return MemberTaste(
            userId: projection.userId,
            displayName: projection.displayName,
            memories: memories,
            dislikedIngredientIds: Set(projection.dislikedIngredientIds)
        )
    }
}

enum HouseholdRecommendation {
    /// Priority 1–3 remove a recipe. Later priorities only change rank.
    /// A current household veto wins for this week even when both people loved it before.
    static func exclusion(
        for candidate: PickerCandidate,
        tastes: [MemberTaste],
        vetoSlugs: Set<String>,
        householdAvoided: Set<String>,
        maxCookMinutes: Int
    ) -> HouseholdExclusion? {
        if candidate.timeIsUnknown || candidate.totalMinutes > maxCookMinutes {
            return .cookTime
        }
        if candidate.rating == .never || tastes.contains(where: { $0.memories[candidate.slug]?.neverAgain == true }) {
            return .neverAgain
        }
        if vetoSlugs.contains(candidate.slug) {
            return .currentHouseholdVeto
        }
        if strongDislike(candidate, tastes: tastes) || !candidate.ingredientIds.isDisjoint(with: householdAvoided) {
            return candidate.ingredientIds.isDisjoint(with: householdAvoided) ? .strongPersonalDislike : .householdAvoided
        }
        return nil
    }

    static func score(
        _ candidate: PickerCandidate,
        tastes: [MemberTaste],
        memory: [HouseholdMemorySignal],
        anchors: [PickerCandidate],
        preferredCategories: Set<String>,
        preferredProteins: Set<String>
    ) -> Int {
        var total = candidate.trDogfoodScore / 5
        total += compatibility(candidate.slug, tastes: tastes)
        total += personal(candidate.slug, tastes: tastes)
        total += household(candidate.slug, memory: memory)
        total -= varietyPenalty(candidate, anchors: anchors)
        total += discovery(candidate.slug, tastes: tastes, memory: memory)
        let category = candidate.category.lowercased()
        if preferredCategories.contains(category) { total += 8 }
        if !candidate.protein.isEmpty, preferredProteins.contains(candidate.protein) { total += 10 }
        return total
    }

    static func affinity(_ memory: MealMemorySnapshot?) -> Int {
        guard let memory else { return 0 }
        if memory.neverAgain || memory.latestRating == .never { return -1 }
        if memory.isFavorite || memory.lovedCount > 0 || memory.latestRating == .loved { return 3 }
        if memory.okayCount > 0 || memory.latestRating == .okay || memory.timesCooked > 0 { return 2 }
        return 0
    }

    private static func strongDislike(_ candidate: PickerCandidate, tastes: [MemberTaste]) -> Bool {
        for taste in tastes {
            if !candidate.ingredientIds.isDisjoint(with: taste.dislikedIngredientIds) {
                return true
            }
            if let memory = taste.memories[candidate.slug] {
                let loved = memory.lovedCount > 0 || memory.isFavorite || memory.latestRating == .loved || memory.latestRating == .okay
                if memory.timesReplaced >= 2 && !loved {
                    return true
                }
            }
        }
        return false
    }

    private static func compatibility(_ slug: String, tastes: [MemberTaste]) -> Int {
        let values = tastes.map { affinity($0.memories[slug]) }
        guard values.count >= 2 else {
            return (values.first ?? 0) >= 3 ? 20 : 0
        }
        let first = values[0]
        let second = values[1]
        if first >= 3 && second >= 3 { return 70 }
        if first >= 2 && second >= 2 { return 40 }
        if first >= 3 || second >= 3 { return 12 }
        return 0
    }

    private static func personal(_ slug: String, tastes: [MemberTaste]) -> Int {
        tastes.reduce(0) { partial, taste in
            let memory = taste.memories[slug]
            var score = partial
            if memory?.isFavorite == true { score += 16 }
            if (memory?.lovedCount ?? 0) > 0 { score += 14 }
            if (memory?.timesCooked ?? 0) > 0 { score += 8 }
            if (memory?.okayCount ?? 0) > 0 { score += 4 }
            return score
        }
    }

    private static func household(_ slug: String, memory: [HouseholdMemorySignal]) -> Int {
        guard let signal = memory.first(where: { $0.recipeSlug == slug }) else { return 0 }
        return signal.togetherCooked * 6
            + signal.bothLiked * 10
            + signal.selectedCount * 3
            - signal.vetoCount * 20
            - signal.replacedCount * 8
            - signal.skippedCount * 4
    }

    private static func varietyPenalty(_ candidate: PickerCandidate, anchors: [PickerCandidate]) -> Int {
        var penalty = 0
        if !candidate.protein.isEmpty, anchors.contains(where: { $0.protein == candidate.protein }) {
            penalty += 18
        }
        if !candidate.cuisine.isEmpty, anchors.contains(where: { $0.cuisine == candidate.cuisine }) {
            penalty += 12
        }
        if !candidate.category.isEmpty, anchors.contains(where: { $0.category == candidate.category }) {
            penalty += 8
        }
        return penalty
    }

    private static func discovery(
        _ slug: String,
        tastes: [MemberTaste],
        memory: [HouseholdMemorySignal]
    ) -> Int {
        let cooked = tastes.contains { ($0.memories[slug]?.timesCooked ?? 0) > 0 }
        let together = memory.first { $0.recipeSlug == slug }?.togetherCooked ?? 0
        return !cooked && together == 0 ? 8 : 0
    }
}

enum HouseholdPlanner {
    static func slugs(
        candidates: [PickerCandidate],
        evenings: Int,
        dayOffsets: [Int],
        maxCookMinutes: Int,
        weekdayCap: Int?,
        tastes: [MemberTaste],
        memory: [HouseholdMemorySignal],
        vetoSlugs: Set<String>,
        householdAvoided: Set<String>,
        preferredCategories: Set<String> = [],
        preferredProteins: Set<String> = [],
        allowsHard: Bool = true
    ) -> [String] {
        let offsets = dayOffsets.isEmpty ? Array(0..<max(0, evenings)) : dayOffsets
        var blocked: Set<String> = []
        var anchors: [PickerCandidate] = []
        var chosen: [String] = []
        for offset in offsets.prefix(MealRecommender.eveningCap) {
            let cap = (offset < 5 ? weekdayCap : nil).map { min(maxCookMinutes, $0) } ?? maxCookMinutes
            let ranked = candidates
                .filter { candidate in
                    !blocked.contains(candidate.slug)
                        && (allowsHard || candidate.difficulty.lowercased() != "hard")
                        && HouseholdRecommendation.exclusion(
                            for: candidate,
                            tastes: tastes,
                            vetoSlugs: vetoSlugs,
                            householdAvoided: householdAvoided,
                            maxCookMinutes: cap
                        ) == nil
                }
                .map { candidate in
                    (
                        candidate,
                        HouseholdRecommendation.score(
                            candidate,
                            tastes: tastes,
                            memory: memory,
                            anchors: anchors,
                            preferredCategories: preferredCategories,
                            preferredProteins: preferredProteins
                        )
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                    return lhs.0.slug < rhs.0.slug
                }
            guard let next = ranked.first?.0 else { break }
            chosen.append(next.slug)
            blocked.insert(next.slug)
            anchors.append(next)
        }
        return chosen
    }
}

enum HouseholdReplacementIntent: String, CaseIterable, Identifiable, Sendable {
    case bothWillLike
    case faster
    case favorite
    case different
    case noChicken
    case noMushrooms
    case surprise

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bothWillLike: L10n.text("household.replace.intent.bothWillLike", "İkiniz de seversiniz")
        case .faster: L10n.text("replace.chip.faster", "Daha hızlı")
        case .favorite: L10n.text("replace.chip.loved", "Bir favori kullan")
        case .different: L10n.text("household.replace.intent.different", "Bundan farklı")
        case .noChicken: L10n.text("replace.chip.noChicken", "Tavuksuz")
        case .noMushrooms: L10n.text("household.replace.intent.noMushrooms", "Mantarsız")
        case .surprise: L10n.text("household.replace.intent.surprise", "Bizi şaşırt")
        }
    }
}

enum HouseholdReplacementReason: String, Equatable, Sendable {
    case faster
    case bothLike
    case householdFit
    case youUsuallyLike
    case surprise
    case fitsThisWeek

    var text: String {
        switch self {
        case .faster: L10n.text("replace.reason.faster", "Daha kısa sürer")
        case .bothLike: L10n.text("household.replace.reason.bothLike", "İkiniz de sever")
        case .householdFit: L10n.text("household.replace.reason.householdFit", "Ev uyumu")
        case .youUsuallyLike: L10n.text("household.replace.reason.youUsuallyLike", "Sen genellikle seversin")
        case .surprise: L10n.text("household.replace.reason.surprise", "Bu hafta için sürpriz")
        case .fitsThisWeek: L10n.text("household.replace.reason.fitsThisWeek", "Bu hafta için uygun")
        }
    }
}

struct HouseholdReplacementChoice: Equatable, Sendable, Identifiable {
    var slug: String
    var minutes: Int
    var reasonCode: HouseholdReplacementReason

    var id: String { slug }
    var reason: String { reasonCode.text }
}

enum HouseholdReplacement {
    static let listLimit = 8

    static func choices(
        catalog: [PickerCandidate],
        current: PickerCandidate,
        tastes: [MemberTaste],
        memory: [HouseholdMemorySignal],
        vetoSlugs: Set<String>,
        householdAvoided: Set<String>,
        maxCookMinutes: Int,
        intent: HouseholdReplacementIntent,
        currentUserId: String,
        blockedSlugs: Set<String> = []
    ) -> [HouseholdReplacementChoice] {
        var blocked = blockedSlugs
        blocked.insert(current.slug)
        let eligible = catalog.filter { candidate in
            guard !blocked.contains(candidate.slug) else { return false }
            guard HouseholdRecommendation.exclusion(
                for: candidate,
                tastes: tastes,
                vetoSlugs: vetoSlugs,
                householdAvoided: householdAvoided,
                maxCookMinutes: maxCookMinutes
            ) == nil else { return false }
            return matches(candidate, current: current, intent: intent, tastes: tastes, memory: memory)
        }
        let ranked = eligible.map { candidate in
            (
                candidate,
                HouseholdRecommendation.score(
                    candidate,
                    tastes: tastes,
                    memory: memory,
                    anchors: [current],
                    preferredCategories: [],
                    preferredProteins: []
                )
            )
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.slug < rhs.0.slug
        }
        .map(\.0)
        guard !ranked.isEmpty else { return [] }
        let picked: [PickerCandidate]
        if intent == .surprise {
            picked = [ranked[stableIndex(seed: current.slug, count: ranked.count)]]
        } else {
            picked = Array(ranked.prefix(listLimit))
        }
        return picked.map { candidate in
            HouseholdReplacementChoice(
                slug: candidate.slug,
                minutes: candidate.totalMinutes,
                reasonCode: reason(
                    for: candidate,
                    current: current,
                    intent: intent,
                    tastes: tastes,
                    memory: memory,
                    currentUserId: currentUserId
                )
            )
        }
    }

    /// Mushroom family by dictionary id (`mushrooms`, `porcini-mushroom`, …). Imported `import:` lines
    /// resolve through the dictionary; an unresolved one counts when its text contains a mushroom
    /// entry's source-locale name or alias, so the filter never depends on hard-coded words.
    static func containsMushroom(_ candidate: PickerCandidate, dictionary: IngredientDictionary = .shared) -> Bool {
        candidate.ingredientIds.contains { id in
            if let canonical = dictionary.canonicalId(id) { return isMushroomId(canonical) }
            if isMushroomId(id) { return true }
            guard id.hasPrefix("import:") else { return false }
            let text = IngredientDictionary.fold(String(id.dropFirst("import:".count)))
            guard !text.isEmpty else { return false }
            return mushroomNames(dictionary).contains { text.contains($0) }
        }
    }

    private static func isMushroomId(_ id: String) -> Bool {
        id.lowercased().contains("mushroom")
    }

    private static func mushroomNames(_ dictionary: IngredientDictionary) -> [String] {
        dictionary.entries
            .filter { isMushroomId($0.id) }
            .flatMap { entry in
                ([entry.name(in: IngredientEntry.sourceLocale)] + entry.aliases(in: IngredientEntry.sourceLocale))
                    .map { IngredientDictionary.fold($0) }
            }
            .filter { $0.count >= 3 }
    }

    private static func matches(
        _ candidate: PickerCandidate,
        current: PickerCandidate,
        intent: HouseholdReplacementIntent,
        tastes: [MemberTaste],
        memory: [HouseholdMemorySignal]
    ) -> Bool {
        switch intent {
        case .bothWillLike:
            let values = tastes.map { HouseholdRecommendation.affinity($0.memories[candidate.slug]) }
            if values.count >= 2 { return values.allSatisfy { $0 >= 2 } }
            return (values.first ?? 0) >= 2 || (memory.first { $0.recipeSlug == candidate.slug }?.bothLiked ?? 0) > 0
        case .faster:
            return candidate.totalMinutes < current.totalMinutes
        case .favorite:
            return tastes.contains { taste in
                let memory = taste.memories[candidate.slug]
                return memory?.isFavorite == true || (memory?.lovedCount ?? 0) > 0
            } || candidate.rating == .loved
        case .different:
            return MealReplacement.isDifferent(candidate, from: current)
        case .noChicken:
            return !MealReplacement.isChicken(candidate)
        case .noMushrooms:
            return !containsMushroom(candidate)
        case .surprise:
            return true
        }
    }

    static func reason(
        for candidate: PickerCandidate,
        current: PickerCandidate,
        intent: HouseholdReplacementIntent,
        tastes: [MemberTaste],
        memory: [HouseholdMemorySignal],
        currentUserId: String
    ) -> HouseholdReplacementReason {
        if intent == .faster, candidate.totalMinutes < current.totalMinutes {
            return .faster
        }
        let mine = HouseholdRecommendation.affinity(tastes.first { $0.userId == currentUserId }?.memories[candidate.slug])
        let others = tastes.filter { $0.userId != currentUserId }.map { HouseholdRecommendation.affinity($0.memories[candidate.slug]) }
        if mine >= 3, !others.isEmpty, others.allSatisfy({ $0 >= 3 }) {
            return .bothLike
        }
        if (memory.first { $0.recipeSlug == candidate.slug }?.bothLiked ?? 0) > 0 || (mine >= 2 && others.allSatisfy { $0 >= 2 } && !others.isEmpty) {
            return .householdFit
        }
        if mine >= 3 {
            return .youUsuallyLike
        }
        if intent == .surprise {
            return .surprise
        }
        return .fitsThisWeek
    }

    private static func stableIndex(seed: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var total = 0
        for byte in seed.utf8 {
            total = (total &* 33) &+ Int(byte)
        }
        return total % count
    }
}

enum HouseholdWeekCopy {
    static func headline(members: [HouseholdMember]) -> String {
        let names = members
            .sorted { lhs, rhs in
                if lhs.role != rhs.role { return lhs.role == .owner }
                return lhs.joinedAt < rhs.joinedAt
            }
            .map(\.displayName)
        return names.joined(separator: " + ")
    }
}
