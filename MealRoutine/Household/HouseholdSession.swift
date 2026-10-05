import Foundation
import Observation
import SwiftData
#if canImport(UserNotifications)
import UserNotifications
#endif

enum HouseholdSyncState: Equatable, Sendable {
    case idle
    case syncing
    case offline
    case failed
}

/// In-memory household board plus the local cache. CloudKit is consulted when iCloud is available.
@MainActor
@Observable
final class HouseholdSession {
    static let shared = HouseholdSession()

    var account: HouseholdUser?
    var snapshot: HouseholdSnapshot = .empty()
    var syncState: HouseholdSyncState = .idle
    var statusMessage: String?
    var pendingInviteCode: String?
    private var deliveredPushIDs: Set<UUID> = []
    private var isStarted = false

    var hasHousehold: Bool { snapshot.hasHousehold }

    /// Shared week replaces the personal week only while this Apple account is in a household.
    var isHouseholdMode: Bool { account != nil && snapshot.hasHousehold }

    func start(in context: ModelContext) async {
        if !isStarted {
            account = HouseholdAccountStore.load()
            snapshot = HouseholdCacheStore.load(in: context)
            isStarted = true
        }
        await refresh(in: context)
        await consumePendingInvite(in: context)
    }

    func adoptAppleUser(id: String, displayName: String?) {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let existing = account?.displayName ?? ""
        let name = trimmed.isEmpty ? existing : trimmed
        let user = HouseholdUser(
            id: id,
            displayName: name,
            createdAt: account?.createdAt ?? .now
        )
        account = user
        HouseholdAccountStore.save(user)
        statusMessage = nil
    }

    func signOut(in context: ModelContext) {
        account = nil
        HouseholdAccountStore.clear()
        statusMessage = "Bu telefonda Apple oturumu kapatıldı. Ev halkı iCloud'da durur."
    }

    func queueInvite(_ code: String) {
        pendingInviteCode = HouseholdInviteCode.normalize(code)
    }

    func createHousehold(name: String, in context: ModelContext) {
        guard let account else {
            statusMessage = HouseholdError.notSignedIn.errorDescription
            return
        }
        guard !snapshot.hasHousehold else {
            statusMessage = HouseholdError.alreadyInHousehold.errorDescription
            return
        }
        do {
            snapshot = try HouseholdReducer.createHousehold(user: account, name: name, now: .now)
            statusMessage = "Ev halkı kuruldu. Partnerini davet edebilirsin."
            persist(in: context)
            Task { await push(in: context) }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func createInvite(in context: ModelContext) {
        guard let account else {
            statusMessage = HouseholdError.notSignedIn.errorDescription
            return
        }
        do {
            let invite = try HouseholdReducer.createInvite(
                snapshot: &snapshot,
                user: account,
                now: .now,
                seed: UInt64.random(in: 1...9_999_999_999)
            )
            statusMessage = "Davet kodu \(invite.inviteCode)"
            persist(in: context)
            Task { await publish(invite: invite, in: context) }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func acceptInvite(code: String, in context: ModelContext) async {
        guard let account else {
            queueInvite(code)
            statusMessage = HouseholdError.notSignedIn.errorDescription
            return
        }
        if snapshot.hasHousehold, snapshot.member(account.id) == nil {
            statusMessage = HouseholdError.alreadyInHousehold.errorDescription
            return
        }
        syncState = .syncing
        do {
            #if canImport(CloudKit)
            let lookup = try await CloudKitHouseholdTransport.lookup(code: code)
            if lookup.status == HouseholdInviteStatus.revoked.rawValue { throw HouseholdError.inviteRevoked }
            if lookup.expiresAt <= .now { throw HouseholdError.inviteExpired }
            if let url = lookup.shareURL {
                try await CloudKitHouseholdTransport.acceptShare(url: url)
                if let remote = try await CloudKitHouseholdTransport.pullShared(url: url) {
                    snapshot = HouseholdConflictResolver.merge(local: snapshot.hasHousehold ? snapshot : remote, server: remote)
                }
            }
            #endif
            try HouseholdReducer.acceptInvite(snapshot: &snapshot, user: account, code: code, now: .now)
            persist(in: context)
            try HouseholdPlanBridge.apply(snapshot: snapshot, in: context)
            await push(in: context)
            statusMessage = "Ev halkına katıldın."
            pendingInviteCode = nil
            syncState = .idle
        } catch let error as HouseholdError where error == .offline {
            syncState = .offline
            statusMessage = error.errorDescription
        } catch {
            syncState = .failed
            statusMessage = error.localizedDescription
        }
    }

    func revoke(inviteId: UUID, in context: ModelContext) {
        guard let account else { return }
        do {
            try HouseholdReducer.revokeInvite(snapshot: &snapshot, userId: account.id, inviteId: inviteId, now: .now)
            persist(in: context)
            Task { await push(in: context) }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func remove(memberId: String, in context: ModelContext) {
        guard let account else { return }
        do {
            try HouseholdReducer.removeMember(snapshot: &snapshot, actorId: account.id, memberUserId: memberId, now: .now)
            persist(in: context)
            Task { await push(in: context) }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func leave(in context: ModelContext) {
        guard let account else { return }
        do {
            try HouseholdReducer.leave(snapshot: &snapshot, userId: account.id, now: .now)
            persist(in: context)
            Task { await push(in: context) }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func deleteHousehold(in context: ModelContext) {
        guard let account, let householdId = snapshot.household?.id else { return }
        do {
            snapshot = try HouseholdReducer.deleteHousehold(snapshot: &snapshot, userId: account.id)
            persist(in: context)
            statusMessage = "Ev halkı silindi. Kişisel planın duruyor."
            Task {
                #if canImport(CloudKit)
                try? await CloudKitHouseholdTransport.deleteBoard(householdId: householdId)
                #endif
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func updatePreference(
        cookingDays: [Int],
        maxWeekdayMinutes: Int,
        preferredCategories: String,
        preferredProteins: String,
        avoidedIngredients: String,
        in context: ModelContext
    ) {
        guard let account else { return }
        do {
            try HouseholdReducer.updatePreference(
                snapshot: &snapshot,
                userId: account.id,
                cookingDays: cookingDays,
                maxWeekdayMinutes: maxWeekdayMinutes,
                preferredCategories: split(preferredCategories),
                preferredProteins: split(preferredProteins),
                avoidedIngredients: split(avoidedIngredients),
                now: .now
            )
            persist(in: context)
            Task { await push(in: context) }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func generateSharedWeek(in context: ModelContext, now: Date = .now) {
        guard let account else {
            statusMessage = HouseholdError.notSignedIn.errorDescription
            return
        }
        guard snapshot.hasHousehold else { return }
        do {
            let recipes = try context.fetch(FetchDescriptor<Recipe>())
            let feedback = try context.fetch(FetchDescriptor<RecipeFeedback>())
            let prefs = try UserPrefsStore.existing(in: context)
            publishPersonalRecipes(recipes, ownerId: account.id)
            let ratings = FeedbackIndex.latestRatings(in: feedback)
            let memories = (try? MealMemoryService.snapshots(in: context)) ?? [:]
            let disliked = Set(prefs?.dislikedIngredientIds ?? [])
            let selfTaste = MemberTaste(
                userId: account.id,
                displayName: HouseholdReducer.displayName(account),
                memories: memories,
                dislikedIngredientIds: disliked
            )
            HouseholdReducer.publishTaste(
                snapshot: &snapshot,
                projection: MemberTasteProjectionBuilder.make(
                    userId: account.id,
                    displayName: selfTaste.displayName,
                    memories: memories,
                    dislikedIngredientIds: disliked,
                    now: now
                )
            )
            var tastes = [selfTaste]
            tastes.append(contentsOf: snapshot.tasteProjections.filter { $0.userId != account.id }.map(MemberTasteProjectionBuilder.taste(from:)))
            let preference = snapshot.preference
            let avoided = Set((preference?.avoidedIngredients ?? []).map { $0.lowercased() })
            let vetoes = Set((snapshot.plan?.meals ?? []).filter { HouseholdConflict.needsDecision($0.reactions) }.map(\.recipeSlug))
            let evenings = min(max(prefs?.eveningsPerWeek ?? 5, 1), MealRecommender.eveningCap)
            let offsets = preference?.cookingDays ?? []
            let slugs = HouseholdPlanner.slugs(
                candidates: HouseholdPlanBridge.candidates(
                    recipes: recipes,
                    ratings: ratings,
                    projections: snapshot.recipeProjections
                ),
                evenings: evenings,
                dayOffsets: offsets,
                maxCookMinutes: prefs?.maxCookMinutes ?? 60,
                weekdayCap: preference?.maxWeekdayMinutes,
                tastes: tastes,
                memory: snapshot.memory,
                vetoSlugs: vetoes,
                householdAvoided: avoided,
                preferredCategories: Set((preference?.preferredCategories ?? []).map { $0.lowercased() }),
                preferredProteins: Set(preference?.preferredProteins ?? [])
            )
            guard !slugs.isEmpty else { throw HouseholdError.noAlternative }
            let names = Dictionary(recipes.map { ($0.slug, $0.displayName) }, uniquingKeysWith: { first, _ in first })
            let owners = Dictionary(snapshot.recipeProjections.map { ($0.slug, $0.ownerUserId) }, uniquingKeysWith: { first, _ in first })
            let days = offsets.isEmpty ? Array(slugs.indices) : Array(offsets.prefix(slugs.count))
            let drafts = slugs.enumerated().map { index, slug in
                HouseholdMealDraft(
                    dayOffset: days[index],
                    recipeSlug: slug,
                    title: names[slug] ?? snapshot.recipeProjections.first { $0.slug == slug }?.title ?? slug,
                    recipeOwnerUserId: owners[slug]
                )
            }
            try HouseholdReducer.installPlan(
                snapshot: &snapshot,
                drafts: drafts,
                weekStart: WeekCalendar.weekStart(containing: now),
                actor: account,
                now: now
            )
            try HouseholdPlanBridge.apply(snapshot: snapshot, in: context, now: now)
            persist(in: context)
            statusMessage = "Ortak plan hazır. İkiniz de bakabilirsiniz."
            notifyPartners()
            Task { await push(in: context) }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func setReaction(_ reaction: MealReactionKind, mealID: UUID, in context: ModelContext) {
        guard let account else { return }
        do {
            try HouseholdReducer.setReaction(snapshot: &snapshot, mealId: mealID, user: account, reaction: reaction, now: .now)
            persist(in: context)
            notifyPartners()
            Task { await push(in: context) }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func noteReplacement(mealID: UUID, slug: String, in context: ModelContext) {
        guard let account, snapshot.plan?.meals.contains(where: { $0.id == mealID }) == true else { return }
        let recipes = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
        let title = recipes.first { $0.slug == slug }?.displayName
            ?? snapshot.recipeProjections.first { $0.slug == slug }?.title
            ?? slug
        let owner = snapshot.recipeProjections.first { $0.slug == slug }?.ownerUserId
        do {
            try HouseholdReducer.replaceMeal(
                snapshot: &snapshot,
                mealId: mealID,
                slug: slug,
                title: title,
                recipeOwnerUserId: owner,
                actor: account,
                now: .now
            )
            persist(in: context)
            notifyPartners()
            Task { await push(in: context) }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func noteCooked(mealID: UUID, in context: ModelContext) {
        guard let account else { return }
        do {
            try HouseholdReducer.markCooked(snapshot: &snapshot, mealId: mealID, actor: account, now: .now, cooked: true)
            persist(in: context)
            Task { await push(in: context) }
        } catch {
            statusMessage = nil
        }
    }

    func finalize(in context: ModelContext) {
        guard let account else { return }
        do {
            try HouseholdReducer.finalize(snapshot: &snapshot, actor: account, now: .now)
            persist(in: context)
            notifyPartners()
            statusMessage = "Plan netleşti."
            Task { await push(in: context) }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func noteGrocery(id: UUID, in context: ModelContext) {
        guard let account, snapshot.hasHousehold else { return }
        guard let item = try? context.fetch(FetchDescriptor<GroceryItem>()).first(where: { $0.uuid == id }) else { return }
        let key = HouseholdGroceryKey.make(
            ingredientId: item.ingredientId,
            unit: item.unit,
            isManual: item.isManual,
            uuid: item.uuid
        )
        do {
            try HouseholdReducer.setGrocery(
                snapshot: &snapshot,
                itemKey: key,
                isChecked: item.isChecked,
                user: account,
                now: .now
            )
            persist(in: context)
            Task { await push(in: context) }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refresh(in context: ModelContext) async {
        guard account != nil else { return }
        publishRecipesIfNeeded(in: context)
        syncState = .syncing
        do {
            #if canImport(CloudKit)
            await CloudKitHouseholdTransport.registerChangeSubscription()
            if let householdId = snapshot.household?.id, snapshot.role(of: account?.id ?? "") == .owner {
                if let remote = try await CloudKitHouseholdTransport.pull(householdId: householdId) {
                    snapshot = HouseholdConflictResolver.merge(local: snapshot, server: remote)
                }
            } else if let urlString = snapshot.invites.compactMap(\.shareURL).first, let url = URL(string: urlString) {
                if let remote = try await CloudKitHouseholdTransport.pullShared(url: url) {
                    snapshot = HouseholdConflictResolver.merge(local: snapshot, server: remote)
                }
            }
            if HouseholdConflictResolver.hasPending(snapshot) {
                try await pushThrowing()
            }
            try HouseholdPlanBridge.apply(snapshot: snapshot, in: context)
            syncState = .idle
            #else
            syncState = .offline
            #endif
            persist(in: context)
            notifyPartners()
        } catch HouseholdError.offline {
            syncState = .offline
        } catch {
            syncState = .failed
            statusMessage = error.localizedDescription
        }
    }

    private func consumePendingInvite(in context: ModelContext) async {
        guard let code = pendingInviteCode, account != nil else { return }
        await acceptInvite(code: code, in: context)
    }

    private func publish(invite: HouseholdInvite, in context: ModelContext) async {
        #if canImport(CloudKit)
        do {
            let url = try await CloudKitHouseholdTransport.publishInvite(
                invite,
                householdName: snapshot.household?.name ?? "Ev",
                snapshot: snapshot
            )
            if let url {
                HouseholdReducer.attachShareURL(snapshot: &snapshot, inviteId: invite.id, shareURL: url.absoluteString)
                persist(in: context)
            }
            syncState = .idle
        } catch HouseholdError.offline {
            syncState = .offline
            statusMessage = "Davet kodu bu telefonda hazır. iCloud açılınca bağlantı da paylaşılır."
        } catch {
            syncState = .failed
            statusMessage = error.localizedDescription
        }
        #endif
    }

    private func push(in context: ModelContext) async {
        do {
            try await pushThrowing()
            persist(in: context)
            syncState = .idle
        } catch HouseholdError.offline {
            syncState = .offline
        } catch {
            syncState = .failed
        }
    }

    private func pushThrowing() async throws {
        #if canImport(CloudKit)
        do {
            snapshot = try await CloudKitHouseholdTransport.push(snapshot)
        } catch let conflict as HouseholdServerConflict {
            snapshot = HouseholdConflictResolver.merge(local: snapshot, server: conflict.server)
            snapshot = try await CloudKitHouseholdTransport.push(snapshot)
            statusMessage = "Sunucudaki plan uygulandı."
        }
        #else
        throw HouseholdError.offline
        #endif
    }

    private func publishRecipesIfNeeded(in context: ModelContext) {
        guard let account, snapshot.hasHousehold else { return }
        let recipes = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
        publishPersonalRecipes(recipes, ownerId: account.id)
        let memories = (try? MealMemoryService.snapshots(in: context)) ?? [:]
        let prefs = try? UserPrefsStore.existing(in: context)
        HouseholdReducer.publishTaste(
            snapshot: &snapshot,
            projection: MemberTasteProjectionBuilder.make(
                userId: account.id,
                displayName: HouseholdReducer.displayName(account),
                memories: memories,
                dislikedIngredientIds: Set(prefs?.dislikedIngredientIds ?? []),
                now: .now
            )
        )
    }

    private func publishPersonalRecipes(_ recipes: [Recipe], ownerId: String) {
        HouseholdReducer.publishRecipes(
            snapshot: &snapshot,
            projections: HouseholdPlanBridge.projections(from: recipes, ownerId: ownerId),
            ownerId: ownerId
        )
    }

    private func persist(in context: ModelContext) {
        HouseholdCacheStore.save(snapshot, in: context)
    }

    private func notifyPartners() {
        guard let account else { return }
        let pushes = snapshot.activities.compactMap { activity in
            HouseholdNotificationPolicy.make(activity: activity, recipientUserId: account.id)
        }
        let fresh = pushes.filter { !deliveredPushIDs.contains($0.id) }
        guard !fresh.isEmpty else { return }
        fresh.forEach { deliveredPushIDs.insert($0.id) }
        HouseholdNotifier.deliver(fresh)
    }

    private func split(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
    }
}

enum HouseholdNotifier {
    static func deliver(_ pushes: [HouseholdPush]) {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            for push in pushes {
                let content = UNMutableNotificationContent()
                content.title = push.title
                content.body = push.body
                content.sound = .default
                let request = UNNotificationRequest(identifier: push.id.uuidString, content: content, trigger: nil)
                center.add(request)
            }
        }
        #endif
    }
}
