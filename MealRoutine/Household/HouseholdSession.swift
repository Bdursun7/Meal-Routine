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
            if isTestMode, HouseholdTestLaunch.isResetRequested {
                resetTestData(in: context)
                statusMessage = nil
            } else {
                account = HouseholdAccountStore.load(testMode: isTestMode)
                snapshot = HouseholdCacheStore.load(in: context, key: clientCacheKey)
                if isTestMode {
                    restoreTestServer(in: context)
                }
            }
            isStarted = true
        }
        await refresh(in: context)
        await consumePendingInvite(in: context)
        await drainPending(in: context)
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
        PendingOperationStore.replace([], in: context)
        if enabled {
            restoreTestServer(in: context)
            statusMessage = "Test modu açık. Apple, iCloud ve bildirim yok."
            syncState = .idle
        } else {
            FakeHouseholdBackend.shared.setOffline(false)
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
        HouseholdTestMode.shared.clearSyncSimulation()
        HouseholdAccountStore.clear(testMode: true)
        HouseholdCacheStore.clear(in: context, key: HouseholdCacheBox.testClientKey)
        HouseholdCacheStore.clear(in: context, key: HouseholdCacheBox.testServerKey)
        account = nil
        snapshot = .empty()
        deliveredPushIDs = []
        PendingOperationStore.replace([], in: context)
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
        if usesHouseholdAPI {
            Task { await self.createRemote(name: name, in: context) }
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
        if usesHouseholdAPI {
            Task { await self.inviteRemote(in: context) }
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
        if usesHouseholdAPI {
            await performRemote(in: context, success: "Ev halkına katıldın.") {
                try await self.lifecycleAPI().accept(code: code)
            }
            pendingInviteCode = nil
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
        if usesHouseholdAPI {
            Task { await self.cancelRemote(inviteId: inviteId, in: context) }
            return
        }
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
        if usesHouseholdAPI {
            Task { await self.removeRemote(memberId: memberId, in: context) }
            return
        }
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
        if usesHouseholdAPI {
            let transferring = snapshot.role(of: account.id) == .owner && snapshot.members.count > 1
            let message = transferring
                ? "Ev sahipliği devredildi. Ortak plan evde kaldı. Kişisel verin duruyor."
                : "Ev halkından ayrıldın. Kişisel verin duruyor."
            Task { await self.leaveRemote(message: message, in: context) }
            return
        }
        let householdId = snapshot.household?.id
        let ownerAlone = snapshot.role(of: account.id) == .owner && snapshot.members.count <= 1
        do {
            try HouseholdReducer.leave(snapshot: &snapshot, userId: account.id, now: .now)
            persist(in: context)
            if ownerAlone, let householdId {
                let transport = activeTransport()
                Task { try? await transport.deleteBoard(householdId: householdId) }
            } else {
                enqueueTestSync { await self.push(in: context) }
            }
            statusMessage = ownerAlone
                ? "Ev halkı kapandı. Kişisel verin duruyor."
                : "Ev halkından ayrıldın. Ortak plan evde kaldı."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func renameHousehold(name: String, in context: ModelContext) {
        guard let account else { return }
        if usesHouseholdAPI {
            Task { await self.renameRemote(name: name, in: context) }
            return
        }
        do {
            try HouseholdReducer.rename(snapshot: &snapshot, userId: account.id, name: name, now: .now)
            persist(in: context)
            enqueueTestSync { await self.push(in: context) }
            statusMessage = "Ev halkının adı güncellendi."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func resendInvite(inviteId: UUID, in context: ModelContext) {
        guard let account else { return }
        if usesHouseholdAPI {
            Task { await self.resendRemote(inviteId: inviteId, in: context) }
            return
        }
        do {
            let invite = try HouseholdReducer.resendInvite(snapshot: &snapshot, userId: account.id, inviteId: inviteId, now: .now)
            persist(in: context)
            enqueueTestSync { await self.publish(invite: invite, in: context) }
            statusMessage = "Davet yeniden gönderildi. Kod \(invite.inviteCode)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func rejectInvite(code: String, in context: ModelContext) {
        if usesHouseholdAPI {
            Task { await self.rejectRemote(code: code, in: context) }
            return
        }
        Task { await self.rejectOnFake(code: code, in: context) }
    }

    func transferOwnership(to memberId: String, in context: ModelContext) {
        guard let account else { return }
        if usesHouseholdAPI {
            Task { await self.transferRemote(memberId: memberId, in: context) }
            return
        }
        do {
            try HouseholdReducer.transferOwnership(snapshot: &snapshot, actorId: account.id, memberUserId: memberId, now: .now)
            persist(in: context)
            enqueueTestSync { await self.push(in: context) }
            statusMessage = "Ev sahipliği devredildi. Ortak plan evde kaldı."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func deleteHousehold(in context: ModelContext) {
        guard let account, let householdId = snapshot.household?.id else { return }
        if usesHouseholdAPI {
            Task { await self.deleteRemote(in: context) }
            return
        }
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
        let preferenceBefore = snapshot.preference
        let preferenceBase = preferenceBefore.map { preference in
            preference.baseRevision == 0 ? preference.revision : preference.baseRevision
        } ?? 1
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
            finishSharedEdit(
                entityType: "preference",
                entityId: snapshot.household?.id.uuidString ?? account.id,
                operationType: "update",
                body: BoardMutationEncoder.preference(
                    householdId: snapshot.household?.id ?? UUID(),
                    baseRevision: preferenceBase,
                    cookingDays: cookingDays,
                    maxWeekdayMinutes: maxWeekdayMinutes,
                    preferredCategories: split(preferredCategories),
                    preferredProteins: split(preferredProteins),
                    avoidedIngredients: split(avoidedIngredients)
                ),
                in: context
            )
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
            let weekStart = WeekCalendar.weekStart(containing: now)
            let sameWeek = snapshot.plan.map { WeekCalendar.isSameDay($0.weekStart, weekStart) } ?? false
            let locked = sameWeek ? (snapshot.plan?.meals.filter { $0.cookedAt != nil } ?? []) : []
            var vetoes = Set((snapshot.plan?.meals ?? []).filter { HouseholdConflict.needsDecision($0.reactions) }.map(\.recipeSlug))
            vetoes.formUnion(locked.map(\.recipeSlug))
            let evenings = min(max(prefs?.eveningsPerWeek ?? 5, 1), MealRecommender.eveningCap)
            let offsets = preference?.cookingDays ?? []
            let requestedOffsets = offsets.isEmpty ? Array(0..<evenings) : offsets
            let lockedOffsets = Set(locked.map(\.dayOffset))
            let openOffsets = requestedOffsets.filter { !lockedOffsets.contains($0) }
            let allowsHard = (prefs?.difficultyPreference ?? .mostlyEasy) == .openToHard
            let slugs: [String]
            if openOffsets.isEmpty {
                slugs = []
            } else {
                slugs = HouseholdPlanner.slugs(
                    candidates: HouseholdPlanBridge.candidates(
                        recipes: recipes,
                        ratings: ratings,
                        projections: snapshot.recipeProjections
                    ),
                    evenings: evenings,
                    dayOffsets: openOffsets,
                    maxCookMinutes: prefs?.maxCookMinutes ?? 60,
                    weekdayCap: preference?.maxWeekdayMinutes,
                    tastes: tastes,
                    memory: snapshot.memory,
                    vetoSlugs: vetoes,
                    householdAvoided: avoided,
                    preferredCategories: Set((preference?.preferredCategories ?? []).map { $0.lowercased() }),
                    preferredProteins: Set(preference?.preferredProteins ?? []),
                    allowsHard: allowsHard
                )
            }
            if slugs.isEmpty, locked.isEmpty {
                statusMessage = PlanExplanationBuilder.emptyPool
                return
            }
            let names = Dictionary(recipes.map { ($0.slug, $0.displayName) }, uniquingKeysWith: { first, _ in first })
            let owners = Dictionary(snapshot.recipeProjections.map { ($0.slug, $0.ownerUserId) }, uniquingKeysWith: { first, _ in first })
            var placeOffsets = requestedOffsets
            for meal in locked where !placeOffsets.contains(meal.dayOffset) {
                placeOffsets.append(meal.dayOffset)
            }
            var slugIndex = 0
            var drafts: [HouseholdMealDraft] = []
            for offset in placeOffsets {
                if let kept = locked.first(where: { $0.dayOffset == offset }) {
                    drafts.append(
                        HouseholdMealDraft(
                            dayOffset: offset,
                            recipeSlug: kept.recipeSlug,
                            title: kept.title,
                            recipeOwnerUserId: kept.recipeOwnerUserId,
                            cookedAt: kept.cookedAt,
                            preservedID: kept.id
                        )
                    )
                } else if slugIndex < slugs.count {
                    let slug = slugs[slugIndex]
                    slugIndex += 1
                    drafts.append(
                        HouseholdMealDraft(
                            dayOffset: offset,
                            recipeSlug: slug,
                            title: names[slug] ?? snapshot.recipeProjections.first { $0.slug == slug }?.title ?? slug,
                            recipeOwnerUserId: owners[slug]
                        )
                    )
                }
            }
            guard !drafts.isEmpty else {
                statusMessage = PlanExplanationBuilder.emptyPool
                return
            }
            try HouseholdReducer.installPlan(
                snapshot: &snapshot,
                drafts: drafts,
                weekStart: weekStart,
                actor: account,
                now: now
            )
            try HouseholdPlanBridge.apply(snapshot: snapshot, in: context, now: now)
            if openOffsets.isEmpty {
                statusMessage = PlanExplanationBuilder.lockedMeals
            } else if slugs.count < openOffsets.count {
                statusMessage = PlanExplanationBuilder.shortPool(filled: drafts.count, requested: requestedOffsets.count)
            } else {
                statusMessage = "Ortak plan hazır. İkiniz de bakabilirsiniz."
            }
            if let message = statusMessage,
               message != "Ortak plan hazır. İkiniz de bakabilirsiniz.",
               let week = try WeekPlanService.currentWeek(in: context, now: now) {
                week.explanation = message
                try context.save()
            }
            persist(in: context)
            notifyPartners()
            if let plan = snapshot.plan {
                finishSharedEdit(
                    entityType: "plan",
                    entityId: plan.id.uuidString,
                    operationType: "upsert",
                    body: BoardMutationEncoder.plan(plan, baseRevision: 0),
                    in: context
                )
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func setReaction(_ reaction: MealReactionKind, mealID: UUID, in context: ModelContext) {
        guard let account else { return }
        if isTestMode, HouseholdTestMode.shared.simulatePartnerEdit {
            recordPartnerMealConflict(mealID: mealID, in: context)
            return
        }
        let meal = snapshot.plan?.meals.first { $0.id == mealID }
        let mealRevision = meal?.revision ?? 0
        let reactionBase = meal?.reactions.first { $0.userId == account.id }?.revision ?? 0
        do {
            try HouseholdReducer.setReaction(snapshot: &snapshot, mealId: mealID, user: account, reaction: reaction, now: .now)
            persist(in: context)
            GroceryListService.discardRebuildCache()
            try? GroceryListService.rebuild(in: context)
            notifyPartners()
            finishSharedEdit(
                entityType: "reaction",
                entityId: mealID.uuidString,
                operationType: "set",
                body: BoardMutationEncoder.reaction(
                    mealId: mealID,
                    reactionBase: reactionBase,
                    mealRevision: mealRevision,
                    reaction: reaction.rawValue
                ),
                in: context
            )
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
        if isTestMode, HouseholdTestMode.shared.simulatePartnerEdit {
            recordPartnerMealConflict(mealID: mealID, in: context)
            return
        }
        let mealRevision = snapshot.plan?.meals.first { $0.id == mealID }?.revision ?? 0
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
            finishSharedEdit(
                entityType: "meal",
                entityId: mealID.uuidString,
                operationType: "replace",
                body: BoardMutationEncoder.replace(mealId: mealID, baseRevision: mealRevision, slug: slug, title: title),
                in: context
            )
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func noteCooked(mealID: UUID, in context: ModelContext) {
        guard let account else { return }
        do {
            let mealRevision = snapshot.plan?.meals.first { $0.id == mealID }?.revision ?? 0
            try HouseholdReducer.markCooked(snapshot: &snapshot, mealId: mealID, actor: account, now: .now, cooked: true)
            persist(in: context)
            finishSharedEdit(
                entityType: "meal",
                entityId: mealID.uuidString,
                operationType: "cook",
                body: BoardMutationEncoder.cook(mealId: mealID, baseRevision: mealRevision),
                in: context
            )
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
            if let plan = snapshot.plan {
                finishSharedEdit(
                    entityType: "plan",
                    entityId: plan.id.uuidString,
                    operationType: "upsert",
                    body: BoardMutationEncoder.plan(plan, baseRevision: max(0, plan.revision - 1)),
                    in: context
                )
            }
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
        let previous = snapshot.groceryCompletions.first { $0.itemKey == key }
        do {
            try HouseholdReducer.setGrocery(
                snapshot: &snapshot,
                itemKey: key,
                isChecked: item.isChecked,
                user: account,
                now: .now
            )
            persist(in: context)
            let body: Data
            let operationType: String
            if let previous {
                body = BoardMutationEncoder.groceryCheck(
                    id: item.uuid,
                    baseRevision: previous.revision,
                    isChecked: item.isChecked
                )
                operationType = "check"
            } else {
                body = BoardMutationEncoder.groceryAdd(
                    id: item.uuid,
                    itemKey: key,
                    quantity: GrocerySyncQuantity.whole(item.quantity),
                    baseRevision: 0
                )
                operationType = "add"
            }
            finishSharedEdit(
                entityType: "grocery",
                entityId: item.uuid.uuidString,
                operationType: operationType,
                body: body,
                in: context
            )
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func refresh(in context: ModelContext) async {
        guard account != nil else { return }
        publishRecipesIfNeeded(in: context)
        if usesHouseholdAPI {
            await refreshFromAPI(in: context)
            return
        }
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
            let pushed = try await repository.push(snapshot)
            if !isTestMode {
                statusMessage = "Sunucudaki plan uygulandı."
            }
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

    func setSimulateOffline(_ offline: Bool, in context: ModelContext) {
        guard isTestMode else { return }
        HouseholdTestMode.shared.simulateOffline = offline
        FakeHouseholdBackend.shared.setOffline(offline)
        if offline {
            syncState = .offline
            return
        }
        Task { await self.drainPending(in: context) }
    }

    func drainPending(in context: ModelContext) async {
        let simulatedOffline = isTestMode && HouseholdTestMode.shared.simulateOffline
        if simulatedOffline || (usesHouseholdAPI && !SyncEngine.shared.online) {
            syncState = .offline
            return
        }
        let now = Date()
        let queued = PendingOperationStore.items(in: context)
        if isTestMode {
            let ready = queued.contains { SyncQueueMachine.isReady($0, now: now) }
            guard ready else { return }
            syncState = .syncing
            do {
                _ = try await pushThrowing()
                let updated = await SyncDrainer.drain(items: queued, online: true, now: now.addingTimeInterval(120)) { _ in
                    .applied
                }
                PendingOperationStore.replace(updated, in: context)
                syncState = .idle
            } catch HouseholdError.offline {
                syncState = .offline
            } catch is HouseholdServerConflict {
                let updated = queued.map { item -> SyncWorkItem in
                    if item.status == .pending || item.status == .syncing {
                        return SyncQueueMachine.markConflict(item)
                    }
                    return item
                }
                PendingOperationStore.replace(updated, in: context)
                statusMessage = SharedConflictNotice.mealUpdated
                syncState = .failed
            } catch {
                syncState = .failed
                statusMessage = error.localizedDescription
            }
            return
        }
        let personal = queued.filter { PersonalRecipeSync.isPersonal($0) }
        let board = queued.filter { !PersonalRecipeSync.isPersonal($0) }
        let drainedPersonal = await PersonalRecipeSync.send(personal)
        func storeBoard(_ items: [SyncWorkItem]) {
            PendingOperationStore.replace(items + drainedPersonal, in: context)
        }
        guard usesHouseholdAPI, let householdId = snapshot.household?.id else {
            if drainedPersonal != personal {
                storeBoard(board)
            }
            return
        }
        let ready = board.contains { SyncQueueMachine.isReady($0, now: now) }
        guard ready else {
            let pulled = await pullBoardChanges(
                householdId: householdId,
                pending: board,
                preserving: drainedPersonal,
                in: context
            )
            if !pulled && drainedPersonal != personal {
                storeBoard(board)
            }
            return
        }
        syncState = .syncing
        let api = BoardSyncClient(client: lifecycleAPI().client)
        let jitter = Double.random(in: 0...1)
        let updated = await SyncDrainer.drain(items: board, online: true, now: now, jitterUnit: jitter) { item in
            do {
                let result = try await api.mutate(householdId: householdId, idempotencyKey: item.idempotencyKey, body: item.payload)
                if let meal = result.meal {
                    BoardReactionSync.apply(meal, to: &self.snapshot)
                    self.persist(in: context)
                }
                return .applied
            } catch BoardSyncFailure.conflict(let meal) {
                if let meal {
                    BoardReactionSync.apply(meal, to: &self.snapshot)
                    self.persist(in: context)
                }
                return .conflict
            } catch {
                return .retry
            }
        }
        storeBoard(updated)
        if await pullBoardChanges(
            householdId: householdId,
            pending: updated,
            preserving: drainedPersonal,
            in: context
        ) {
            return
        }
        let conflicted = updated.contains { item in
            item.status == .requiresResolution && queued.first { $0.id == item.id }?.status != .requiresResolution
        }
        let retried = updated.contains { item in
            item.retryCount > (queued.first { $0.id == item.id }?.retryCount ?? 0)
        }
        if conflicted {
            statusMessage = SharedConflictNotice.mealUpdated
            syncState = .failed
        } else if updated.contains(where: { $0.status == .failed }) {
            syncState = .failed
        } else if retried {
            syncState = .offline
        } else {
            syncState = .idle
        }
    }

    /// Pulls the household delta and keeps a pending meal edit when the server revision moved.
    private func pullBoardChanges(
        householdId: UUID,
        pending: [SyncWorkItem],
        preserving personal: [SyncWorkItem] = [],
        in context: ModelContext
    ) async -> Bool {
        let api = BoardSyncClient(client: lifecycleAPI().client)
        guard let page = try? await api.changes(
            householdId: householdId,
            cursor: BoardSyncCursor.load(householdId: householdId)
        ) else { return false }
        BoardSyncCursor.save(page.cursor, householdId: householdId)
        var revisions: [String: Int] = [:]
        var appliedMeal = false
        for change in page.changes {
            if change.entityType == "meal" {
                revisions[change.entityId.lowercased()] = change.revision
            }
            if let meal = change.meal {
                BoardReactionSync.apply(meal, to: &snapshot)
                appliedMeal = true
            }
        }
        if appliedMeal {
            persist(in: context)
        }
        let overridden = Set(BoardDeltaMerge.overriddenMealIDs(pending: pending, remoteRevisions: revisions))
        guard !overridden.isEmpty else { return false }
        let resolved = pending.map { item -> SyncWorkItem in
            if overridden.contains(item.entityId) && (item.status == .pending || item.status == .syncing) {
                return SyncQueueMachine.markConflict(item)
            }
            return item
        }
        PendingOperationStore.replace(resolved + personal, in: context)
        statusMessage = SharedConflictNotice.mealUpdated
        syncState = .failed
        return true
    }

    private var queuesSharedEdits: Bool {
        usesHouseholdAPI || (isTestMode && HouseholdTestMode.shared.simulateOffline)
    }

    private func finishSharedEdit(
        entityType: String,
        entityId: String,
        operationType: String,
        body: Data,
        in context: ModelContext
    ) {
        guard queuesSharedEdits else {
            enqueueTestSync { await self.push(in: context) }
            return
        }
        let item = SyncWorkItem(
            id: UUID(),
            entityType: entityType,
            entityId: entityId,
            operationType: operationType,
            payload: body,
            createdAt: .now,
            retryCount: 0,
            status: .pending
        )
        PendingOperationStore.upsert(item, in: context)
        if isTestMode && HouseholdTestMode.shared.simulateOffline {
            syncState = .offline
            return
        }
        Task { await self.drainPending(in: context) }
    }

    private func recordPartnerMealConflict(mealID: UUID, in context: ModelContext) {
        guard var plan = snapshot.plan, let index = plan.meals.firstIndex(where: { $0.id == mealID }) else { return }
        plan.meals[index].revision += 1
        plan.meals[index].baseRevision = plan.meals[index].revision
        snapshot.plan = plan
        let payload = BoardMutationEncoder.replace(
            mealId: mealID,
            baseRevision: plan.meals[index].revision - 1,
            slug: plan.meals[index].recipeSlug,
            title: plan.meals[index].title
        )
        let item = SyncWorkItem(
            id: UUID(),
            entityType: "meal",
            entityId: mealID.uuidString,
            operationType: "replace",
            payload: payload,
            createdAt: .now,
            retryCount: 0,
            status: .requiresResolution
        )
        PendingOperationStore.upsert(item, in: context)
        persist(in: context)
        statusMessage = SharedConflictNotice.mealUpdated
        syncState = .failed
    }

    private var usesHouseholdAPI: Bool {
        !isTestMode && MealRoutineConfig.apiBaseURL != nil
    }

    private func lifecycleAPI() -> HouseholdLifecycleAPI {
        let base = MealRoutineConfig.apiBaseURL ?? URL(string: "http://127.0.0.1:8080")!
        return HouseholdLifecycleAPI(
            client: APIClient(
                baseURL: base,
                tokens: AuthServices.sharedTokens,
                refreshGate: AuthServices.refreshGate,
                expiry: AuthServices.expiry
            )
        )
    }

    private func performRemote(
        in context: ModelContext,
        success: String,
        work: () async throws -> HouseholdRemoteState
    ) async {
        syncState = .syncing
        do {
            let state = try await work()
            snapshot = HouseholdRemoteMerge.apply(state, to: snapshot, now: .now)
            try? HouseholdPlanBridge.apply(snapshot: snapshot, in: context)
            persist(in: context)
            statusMessage = success
            syncState = .idle
        } catch let error as HouseholdError {
            syncState = error == .offline ? .offline : .failed
            statusMessage = error.errorDescription
        } catch {
            syncState = .failed
            statusMessage = error.localizedDescription
        }
    }

    private func createRemote(name: String, in context: ModelContext) async {
        await performRemote(in: context, success: "Ev halkı kuruldu. Partnerini davet edebilirsin.") {
            try await self.lifecycleAPI().create(name: name)
        }
    }

    private func renameRemote(name: String, in context: ModelContext) async {
        guard let householdId = snapshot.household?.id else { return }
        await performRemote(in: context, success: "Ev halkının adı güncellendi.") {
            try await self.lifecycleAPI().rename(householdId: householdId, name: name)
        }
    }

    private func inviteRemote(in context: ModelContext) async {
        guard let householdId = snapshot.household?.id else { return }
        await performRemote(in: context, success: "Davet hazır.") {
            try await self.lifecycleAPI().createInvite(householdId: householdId)
        }
        guard syncState == .idle,
              let code = snapshot.invites.last(where: { $0.status == .pending })?.inviteCode else { return }
        statusMessage = "Davet kodu \(code)"
    }

    private func resendRemote(inviteId: UUID, in context: ModelContext) async {
        guard let householdId = snapshot.household?.id else { return }
        await performRemote(in: context, success: "Davet yeniden gönderildi.") {
            try await self.lifecycleAPI().resendInvite(householdId: householdId, inviteId: inviteId)
        }
        guard syncState == .idle,
              let code = snapshot.invites.last(where: { $0.status == .pending })?.inviteCode else { return }
        statusMessage = "Davet yeniden gönderildi. Kod \(code)"
    }

    private func cancelRemote(inviteId: UUID, in context: ModelContext) async {
        guard let householdId = snapshot.household?.id else { return }
        await performRemote(in: context, success: "Davet geri alındı.") {
            try await self.lifecycleAPI().cancelInvite(householdId: householdId, inviteId: inviteId)
        }
    }

    private func removeRemote(memberId: String, in context: ModelContext) async {
        guard let householdId = snapshot.household?.id else { return }
        await performRemote(in: context, success: "Üye çıkarıldı. Kişisel verisi duruyor. Ortak plan evde kaldı.") {
            try await self.lifecycleAPI().removeMember(householdId: householdId, accountId: memberId)
        }
    }

    private func leaveRemote(message: String, in context: ModelContext) async {
        guard let householdId = snapshot.household?.id else { return }
        await performRemote(in: context, success: message) {
            try await self.lifecycleAPI().leave(householdId: householdId)
        }
    }

    private func transferRemote(memberId: String, in context: ModelContext) async {
        guard let householdId = snapshot.household?.id else { return }
        await performRemote(in: context, success: "Ev sahipliği devredildi. Ortak plan evde kaldı.") {
            try await self.lifecycleAPI().transfer(householdId: householdId, accountId: memberId)
        }
    }

    private func deleteRemote(in context: ModelContext) async {
        guard let householdId = snapshot.household?.id else { return }
        await performRemote(in: context, success: "Ev halkı silindi. Kişisel planın duruyor.") {
            try await self.lifecycleAPI().deleteHousehold(householdId: householdId)
        }
    }

    private func rejectRemote(code: String, in context: ModelContext) async {
        syncState = .syncing
        do {
            try await lifecycleAPI().reject(code: code)
            statusMessage = "Davet reddedildi."
            syncState = .idle
        } catch let error as HouseholdError {
            syncState = error == .offline ? .offline : .failed
            statusMessage = error.errorDescription
        } catch {
            syncState = .failed
            statusMessage = error.localizedDescription
        }
    }

    private func rejectOnFake(code: String, in context: ModelContext) async {
        let transport = activeTransport()
        do {
            if snapshot.invites.contains(where: { HouseholdInviteCode.normalize($0.inviteCode) == HouseholdInviteCode.normalize(code) }) {
                try HouseholdReducer.rejectInvite(snapshot: &snapshot, code: code, now: .now)
                persist(in: context)
                enqueueTestSync { await self.push(in: context) }
                statusMessage = "Davet reddedildi."
                return
            }
            let lookup = try await transport.lookup(code: code)
            guard let url = lookup.shareURL else { throw HouseholdError.inviteNotFound }
            try await transport.acceptShare(url: url)
            guard var remote = try await transport.pullShared(url: url) else { throw HouseholdError.inviteNotFound }
            try HouseholdReducer.rejectInvite(snapshot: &remote, code: code, now: .now)
            _ = try await transport.push(remote)
            statusMessage = "Davet reddedildi."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func refreshFromAPI(in context: ModelContext) async {
        guard AuthServices.sharedTokens.load() != nil else {
            syncState = .idle
            return
        }
        syncState = .syncing
        do {
            let state = try await lifecycleAPI().current()
            snapshot = HouseholdRemoteMerge.apply(state, to: snapshot, now: .now)
            try? HouseholdPlanBridge.apply(snapshot: snapshot, in: context)
            persist(in: context)
            syncState = .idle
        } catch let error as HouseholdError where error == .notMember {
            snapshot = .empty(now: .now)
            persist(in: context)
            syncState = .idle
        } catch HouseholdError.offline {
            syncState = .offline
        } catch {
            syncState = .failed
            statusMessage = (error as? HouseholdError)?.errorDescription ?? error.localizedDescription
        }
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
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else { return }
            for push in pushes {
                let content = UNMutableNotificationContent()
                content.title = push.title
                content.body = push.body
                content.sound = .default
                content.userInfo = ["route": NotificationDeepLink.url(for: push.kind)]
                let request = UNNotificationRequest(identifier: push.id.uuidString, content: content, trigger: nil)
                center.add(request)
            }
        }
        #endif
        #endif
    }
}
