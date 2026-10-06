import Foundation
import Observation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

enum HouseholdSyncState: Equatable, Sendable {
    case idle
    case syncing
    case offline
    case failed
}

/// In-memory household board plus the local cache.
/// CloudKit is the store when test mode is off and this build can sign iCloud.
/// Test mode uses FakeHouseholdBackend and never calls CloudKit, Apple sign-in, or push.
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
    /// Keeps test-mode pushes in order so a later invite is not overwritten by an earlier save.
    private var testSyncChain: Task<Void, Never>?

    var hasHousehold: Bool { snapshot.hasHousehold }

    var isTestMode: Bool { HouseholdTestMode.shared.isEnabled }

    /// Shared week replaces the personal week only while this account is in a household.
    var isHouseholdMode: Bool { account != nil && snapshot.hasHousehold }

    var showsPartnerControls: Bool {
        isTestMode && snapshot.member(HouseholdTestPartner.userID) != nil
    }

    func start(in context: ModelContext) async {
        if HouseholdTestLaunch.isRequestedByLaunch {
            HouseholdTestMode.shared.setEnabled(true)
        }
        if !isStarted {
            account = HouseholdAccountStore.load(testMode: isTestMode)
            snapshot = HouseholdCacheStore.load(in: context, key: clientCacheKey)
            if isTestMode {
                restoreTestServer(in: context)
            }
            isStarted = true
        }
        await refresh(in: context)
        await consumePendingInvite(in: context)
    }

    func adoptAccount(id: String, displayName: String?) {
        adoptAppleUser(id: id, displayName: displayName)
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
        HouseholdAccountStore.save(user, testMode: isTestMode)
        statusMessage = nil
    }

    func signInForTest() {
        guard isTestMode else { return }
        adoptAppleUser(
            id: HouseholdTestPartner.localUserID,
            displayName: HouseholdTestPartner.localDisplayName
        )
        statusMessage = "Test oturumu açıldı. Apple kimliği yok."
    }

    func signOut(in context: ModelContext) {
        account = nil
        HouseholdAccountStore.clear(testMode: isTestMode)
        if !isTestMode {
            Task { await AuthSession.shared.signOutTokensOnly() }
        }
        statusMessage = isTestMode
            ? "Test oturumu kapatıldı. Ev verisi bu telefonda duruyor."
            : "Bu telefonda oturum kapatıldı."
    }

    func dropAccount(message: String) {
        account = nil
        HouseholdAccountStore.clear(testMode: isTestMode)
        statusMessage = message
    }

    func setTestMode(_ enabled: Bool, in context: ModelContext) async {
        guard isTestMode != enabled else { return }
        HouseholdCacheStore.save(snapshot, in: context, key: clientCacheKey)
        if isTestMode, let data = try? FakeHouseholdBackend.shared.exportData() {
            HouseholdCacheStore.saveData(data, in: context, key: HouseholdCacheBox.testServerKey)
        }
        HouseholdTestMode.shared.setEnabled(enabled)
        deliveredPushIDs = []
        snapshot = HouseholdCacheStore.load(in: context, key: clientCacheKey)
        account = HouseholdAccountStore.load(testMode: enabled)
        if enabled {
            restoreTestServer(in: context)
            statusMessage = "Test modu açık. Apple, iCloud ve bildirim yok."
            syncState = .idle
        } else {
            statusMessage = "Test modu kapalı."
            #if canImport(UIKit)
            if HouseholdTestLaunch.allowsAppleServices {
                UIApplication.shared.registerForRemoteNotifications()
            }
            #endif
            await refresh(in: context)
        }
    }

    func resetTestData(in context: ModelContext) {
        guard isTestMode else { return }
        FakeHouseholdBackend.shared.reset()
        HouseholdTestMode.shared.clearNotices()
        HouseholdAccountStore.clear(testMode: true)
        HouseholdCacheStore.clear(in: context, key: HouseholdCacheBox.testClientKey)
        HouseholdCacheStore.clear(in: context, key: HouseholdCacheBox.testServerKey)
        account = nil
        snapshot = .empty()
        deliveredPushIDs = []
        syncState = .idle
        statusMessage = "Test verisi silindi."
    }

    func queueInvite(_ code: String) {
        pendingInviteCode = HouseholdInviteCode.normalize(code)
    }

    func createHousehold(name: String, in context: ModelContext) {
        guard let account else {
            statusMessage = signedInRequired
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
            enqueueTestSync { await self.push(in: context) }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func createInvite(in context: ModelContext) {
        guard let account else {
            statusMessage = signedInRequired
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
            enqueueTestSync { await self.publish(invite: invite, in: context) }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func acceptInvite(code: String, in context: ModelContext) async {
        guard let account else {
            queueInvite(code)
            statusMessage = signedInRequired
            return
        }
        if snapshot.hasHousehold, snapshot.member(account.id) == nil {
            statusMessage = HouseholdError.alreadyInHousehold.errorDescription
            return
        }
        syncState = .syncing
        do {
            let transport = activeTransport()
            let lookup = try await transport.lookup(code: code)
            if lookup.status == HouseholdInviteStatus.revoked.rawValue { throw HouseholdError.inviteRevoked }
            if lookup.expiresAt <= .now { throw HouseholdError.inviteExpired }
            if let url = lookup.shareURL {
                try await transport.acceptShare(url: url)
                if let remote = try await transport.pullShared(url: url) {
                    snapshot = HouseholdConflictResolver.merge(local: snapshot.hasHousehold ? snapshot : remote, server: remote)
                }
            }
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
            enqueueTestSync { await self.push(in: context) }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func remove(memberId: String, in context: ModelContext) {
        guard let account else { return }
        do {
            try HouseholdReducer.removeMember(snapshot: &snapshot, actorId: account.id, memberUserId: memberId, now: .now)
            persist(in: context)
            enqueueTestSync { await self.push(in: context) }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func leave(in context: ModelContext) {
        guard let account else { return }
        do {
            try HouseholdReducer.leave(snapshot: &snapshot, userId: account.id, now: .now)
            persist(in: context)
            enqueueTestSync { await self.push(in: context) }
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
            let transport = activeTransport()
            Task {
                try? await transport.deleteBoard(householdId: householdId)
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
            enqueueTestSync { await self.push(in: context) }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func generateSharedWeek(in context: ModelContext, now: Date = .now) {
        guard let account else {
            statusMessage = signedInRequired
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
            enqueueTestSync { await self.push(in: context) }
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
            enqueueTestSync { await self.push(in: context) }
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
            enqueueTestSync { await self.push(in: context) }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func noteCooked(mealID: UUID, in context: ModelContext) {
        guard let account else { return }
        do {
            try HouseholdReducer.markCooked(snapshot: &snapshot, mealId: mealID, actor: account, now: .now, cooked: true)
            persist(in: context)
            enqueueTestSync { await self.push(in: context) }
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
            enqueueTestSync { await self.push(in: context) }
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
            enqueueTestSync { await self.push(in: context) }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refresh(in context: ModelContext) async {
        guard account != nil else { return }
        publishRecipesIfNeeded(in: context)
        syncState = .syncing
        do {
            let transport = activeTransport()
            await transport.registerChangeSubscription()
            if let householdId = snapshot.household?.id, snapshot.role(of: account?.id ?? "") == .owner {
                if let remote = try await transport.pull(householdId: householdId) {
                    snapshot = HouseholdConflictResolver.merge(local: snapshot, server: remote)
                }
            } else if let urlString = snapshot.invites.compactMap(\.shareURL).first, let url = URL(string: urlString) {
                if let remote = try await transport.pullShared(url: url) {
                    snapshot = HouseholdConflictResolver.merge(local: snapshot, server: remote)
                }
            }
            if HouseholdConflictResolver.hasPending(snapshot) {
                snapshot = try await pushThrowing()
            }
            try HouseholdPlanBridge.apply(snapshot: snapshot, in: context)
            syncState = .idle
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
        do {
            let transport = activeTransport()
            let url = try await transport.publishInvite(
                invite,
                householdName: snapshot.household?.name ?? "Ev",
                snapshot: snapshot
            )
            if isTestMode, let householdId = snapshot.household?.id, let remote = try await transport.pull(householdId: householdId) {
                snapshot = remote
            }
            if let url {
                HouseholdReducer.attachShareURL(snapshot: &snapshot, inviteId: invite.id, shareURL: url.absoluteString)
                persist(in: context)
            }
            syncState = .idle
        } catch HouseholdError.offline {
            syncState = .offline
            statusMessage = isTestMode
                ? "Davet kodu bu telefonda hazır."
                : "Davet kodu bu telefonda hazır. iCloud açılınca bağlantı da paylaşılır."
        } catch {
            syncState = .failed
            statusMessage = error.localizedDescription
        }
    }

    private func push(in context: ModelContext) async {
        do {
            snapshot = try await pushThrowing()
            persist(in: context)
            syncState = .idle
        } catch HouseholdError.offline {
            syncState = .offline
        } catch {
            syncState = .failed
        }
    }

    private func pushThrowing() async throws -> HouseholdSnapshot {
        let repository = HouseholdRepository(transport: activeTransport())
        do {
            return try await repository.push(snapshot)
        } catch let conflict as HouseholdServerConflict {
            snapshot = HouseholdConflictResolver.merge(local: snapshot, server: conflict.server)
            let pushed = try await transport.push(snapshot)
            statusMessage = "Sunucudaki plan uygulandı."
            return pushed
        }
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

    func simulatePartnerJoin(in context: ModelContext) async {
        guard isTestMode, account != nil else {
            statusMessage = "Önce test olarak gir."
            return
        }
        guard snapshot.role(of: account?.id ?? "") == .owner else {
            statusMessage = HouseholdError.notOwner.errorDescription
            return
        }
        guard let invite = snapshot.invites.last(where: { $0.status == .pending && $0.expiresAt > .now }) else {
            statusMessage = "Önce bir davet kodu oluştur."
            return
        }
        let partner = HouseholdTestPartner.user()
        syncState = .syncing
        await testSyncChain?.value
        do {
            let transport = activeTransport()
            if HouseholdConflictResolver.hasPending(snapshot) {
                snapshot = try await transport.push(snapshot)
            }
            let lookup = try await ensureLookup(for: invite, transport: transport)
            if lookup.status == HouseholdInviteStatus.revoked.rawValue { throw HouseholdError.inviteRevoked }
            if lookup.expiresAt <= .now { throw HouseholdError.inviteExpired }
            guard let url = lookup.shareURL else { throw HouseholdError.inviteNotFound }
            try await transport.acceptShare(url: url)
            guard var remote = try await transport.pullShared(url: url) else { throw HouseholdError.inviteNotFound }
            try HouseholdReducer.acceptInvite(snapshot: &remote, user: partner, code: invite.inviteCode, now: .now)
            HouseholdReducer.publishTaste(snapshot: &remote, projection: HouseholdTestPartner.taste(now: .now))
            remote = try await transport.push(remote)
            snapshot = HouseholdConflictResolver.merge(local: snapshot, server: remote)
            persist(in: context)
            try? HouseholdPlanBridge.apply(snapshot: snapshot, in: context)
            statusMessage = "Test Partner katıldı."
            syncState = .idle
            notifyPartners()
        } catch {
            syncState = .failed
            statusMessage = error.localizedDescription
        }
    }

    func partnerSetReaction(_ reaction: MealReactionKind, mealID: UUID, in context: ModelContext) async {
        await performAsPartner(in: context) { remote, partner in
            try HouseholdReducer.setReaction(
                snapshot: &remote,
                mealId: mealID,
                user: partner,
                reaction: reaction,
                now: .now
            )
        }
    }

    func partnerSuggestReplacement(mealID: UUID, in context: ModelContext) async {
        guard let choice = replacementChoice(mealID: mealID, in: context) else {
            statusMessage = HouseholdError.noAlternative.errorDescription
            return
        }
        await performAsPartner(in: context) { remote, partner in
            try HouseholdReducer.replaceMeal(
                snapshot: &remote,
                mealId: mealID,
                slug: choice.slug,
                title: choice.title,
                recipeOwnerUserId: choice.owner,
                actor: partner,
                now: .now
            )
        }
    }

    func partnerCheckNextGrocery(in context: ModelContext) async {
        let items = (try? context.fetch(FetchDescriptor<GroceryItem>())) ?? []
        guard let item = items.first(where: { !$0.isChecked }) ?? items.first else {
            statusMessage = "Market listesinde satır yok."
            return
        }
        let key = HouseholdGroceryKey.make(
            ingredientId: item.ingredientId,
            unit: item.unit,
            isManual: item.isManual,
            uuid: item.uuid
        )
        let checked = !item.isChecked
        await performAsPartner(in: context) { remote, partner in
            try HouseholdReducer.setGrocery(
                snapshot: &remote,
                itemKey: key,
                isChecked: checked,
                user: partner,
                now: .now
            )
        }
        if statusMessage == nil || syncState == .idle {
            statusMessage = checked ? "Test Partner bir malzemeyi işaretledi." : "Test Partner işareti kaldırdı."
        }
    }

    private func performAsPartner(
        in context: ModelContext,
        mutate: (inout HouseholdSnapshot, HouseholdUser) throws -> Void
    ) async {
        guard isTestMode, snapshot.hasHousehold else { return }
        let partner = HouseholdTestPartner.user()
        guard snapshot.member(partner.id) != nil else {
            statusMessage = "Önce Test Partner katılsın."
            return
        }
        await testSyncChain?.value
        do {
            let transport = activeTransport()
            if HouseholdConflictResolver.hasPending(snapshot) {
                snapshot = try await transport.push(snapshot)
            }
            guard let householdId = snapshot.household?.id else { return }
            guard var remote = try await transport.pull(householdId: householdId) else {
                throw HouseholdError.offline
            }
            try mutate(&remote, partner)
            remote = try await transport.push(remote)
            snapshot = HouseholdConflictResolver.merge(local: snapshot, server: remote)
            persist(in: context)
            try? HouseholdPlanBridge.apply(snapshot: snapshot, in: context)
            try? HouseholdPlanBridge.applyGrocery(snapshot, in: context)
            notifyPartners()
            syncState = .idle
        } catch {
            syncState = .failed
            statusMessage = error.localizedDescription
        }
    }

    private func ensureLookup(
        for invite: HouseholdInvite,
        transport: any HouseholdSyncTransport
    ) async throws -> HouseholdInviteLookup {
        do {
            return try await transport.lookup(code: invite.inviteCode)
        } catch HouseholdError.inviteNotFound {
            if let url = try await transport.publishInvite(
                invite,
                householdName: snapshot.household?.name ?? "Ev",
                snapshot: snapshot
            ) {
                HouseholdReducer.attachShareURL(snapshot: &snapshot, inviteId: invite.id, shareURL: url.absoluteString)
            }
            return try await transport.lookup(code: invite.inviteCode)
        }
    }

    private struct PartnerReplacementChoice {
        var slug: String
        var title: String
        var owner: String?
    }

    private func replacementChoice(mealID: UUID, in context: ModelContext) -> PartnerReplacementChoice? {
        guard let meal = snapshot.plan?.meals.first(where: { $0.id == mealID }) else { return nil }
        let recipes = (try? context.fetch(FetchDescriptor<Recipe>())) ?? []
        let feedback = (try? context.fetch(FetchDescriptor<RecipeFeedback>())) ?? []
        let ratings = FeedbackIndex.latestRatings(in: feedback)
        let candidates = HouseholdPlanBridge.candidates(
            recipes: recipes,
            ratings: ratings,
            projections: snapshot.recipeProjections
        )
        guard let current = candidates.first(where: { $0.slug == meal.recipeSlug }) else {
            return fallbackReplacement(meal: meal, recipes: recipes)
        }
        let tastes = snapshot.tasteProjections.map(MemberTasteProjectionBuilder.taste(from:))
        let vetoes = Set((snapshot.plan?.meals ?? []).filter { HouseholdConflict.needsDecision($0.reactions) }.map(\.recipeSlug))
        let intents: [HouseholdReplacementIntent] = [.bothWillLike, .different, .surprise]
        var picked: HouseholdReplacementChoice?
        for intent in intents {
            let choices = HouseholdReplacement.choices(
                catalog: candidates,
                current: current,
                tastes: tastes,
                memory: snapshot.memory,
                vetoSlugs: vetoes,
                householdAvoided: Set(snapshot.preference?.avoidedIngredients ?? []),
                maxCookMinutes: 90,
                intent: intent,
                currentUserId: HouseholdTestPartner.userID
            )
            if let first = choices.first {
                picked = first
                break
            }
        }
        guard let picked else { return fallbackReplacement(meal: meal, recipes: recipes) }
        return titled(slug: picked.slug, recipes: recipes)
    }

    private func fallbackReplacement(meal: SharedMeal, recipes: [Recipe]) -> PartnerReplacementChoice? {
        let blocked = Set((snapshot.plan?.meals ?? []).map(\.recipeSlug))
        guard let recipe = recipes.first(where: { recipe in
            recipe.collectionState == .readyToCook && !blocked.contains(recipe.slug) && recipe.slug != meal.recipeSlug
        }) else { return nil }
        return PartnerReplacementChoice(slug: recipe.slug, title: recipe.displayName, owner: nil)
    }

    private func titled(slug: String, recipes: [Recipe]) -> PartnerReplacementChoice {
        let title = recipes.first { $0.slug == slug }?.displayName
            ?? snapshot.recipeProjections.first { $0.slug == slug }?.title
            ?? slug
        let owner = snapshot.recipeProjections.first { $0.slug == slug }?.ownerUserId
        return PartnerReplacementChoice(slug: slug, title: title, owner: owner)
    }

    private var clientCacheKey: String {
        isTestMode ? HouseholdCacheBox.testClientKey : HouseholdCacheBox.currentKey
    }

    private var signedInRequired: String {
        isTestMode ? "Test modunda önce Test olarak gir." : (HouseholdError.notSignedIn.errorDescription ?? "")
    }

    private func activeTransport() -> any HouseholdSyncTransport {
        HouseholdSyncRouting.makeTransport(testMode: isTestMode)
    }

    private func enqueueTestSync(_ operation: @escaping @MainActor () async -> Void) {
        guard isTestMode else {
            Task { await operation() }
            return
        }
        let previous = testSyncChain
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        testSyncChain = task
    }

    private func restoreTestServer(in context: ModelContext) {
        guard let data = HouseholdCacheStore.loadData(in: context, key: HouseholdCacheBox.testServerKey) else { return }
        try? FakeHouseholdBackend.shared.importData(data)
    }

    private func persist(in context: ModelContext) {
        HouseholdCacheStore.save(snapshot, in: context, key: clientCacheKey)
        guard isTestMode, let data = try? FakeHouseholdBackend.shared.exportData() else { return }
        HouseholdCacheStore.saveData(data, in: context, key: HouseholdCacheBox.testServerKey)
    }

    private func notifyPartners() {
        guard let account else { return }
        if isTestMode, snapshot.member(HouseholdTestPartner.userID) != nil {
            let outgoing = snapshot.activities.compactMap { activity in
                HouseholdNotificationPolicy.make(activity: activity, recipientUserId: HouseholdTestPartner.userID)
            }
            HouseholdTestMode.shared.record(outgoing, audience: .partner)
        }
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

@MainActor
enum HouseholdNotifier {
    static func deliver(_ pushes: [HouseholdPush]) {
        if HouseholdTestMode.shared.isEnabled {
            HouseholdTestMode.shared.record(pushes, audience: .local)
            return
        }
        #if HOUSEHOLD_LOCAL
        return
        #else
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
        #endif
    }
}
