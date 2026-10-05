import XCTest
import SwiftData
@testable import MealRoutine

@MainActor
final class HouseholdTestModeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testTestModeSelectsFakeBackendAndProductionDoesNot() {
        let fake = HouseholdSyncRouting.makeTransport(testMode: true)
        XCTAssertTrue(fake is FakeHouseholdBackend)
        let production = HouseholdSyncRouting.makeTransport(testMode: false)
        XCTAssertFalse(production is FakeHouseholdBackend)
        #if HOUSEHOLD_LOCAL
        XCTAssertTrue(production is OfflineHouseholdTransport)
        #else
        XCTAssertTrue(production is CloudKitHouseholdBackend)
        #endif
    }

    func testFakeBackendDrivesCreateInviteJoinReactionsVetoAndHistory() async throws {
        let backend = FakeHouseholdBackend()
        let owner = HouseholdUser(id: "owner-test", displayName: "Test Kullanıcı", createdAt: now)
        let partner = HouseholdTestPartner.user(now: now)
        var ownerBoard = try HouseholdReducer.createHousehold(
            user: owner,
            name: "Test Evi",
            now: now,
            householdId: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            memberId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        )
        ownerBoard = try await backend.push(ownerBoard)
        let invite = try HouseholdReducer.createInvite(
            snapshot: &ownerBoard,
            user: owner,
            now: now,
            inviteId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            seed: 42
        )
        ownerBoard = try await backend.push(ownerBoard)
        let shareURL = try await backend.publishInvite(invite, householdName: "Test Evi", snapshot: ownerBoard)
        let code = invite.inviteCode
        XCTAssertEqual(code.count, HouseholdInviteCode.length)
        XCTAssertEqual(HouseholdInviteLink.url(for: code).absoluteString.contains(code), true)
        XCTAssertEqual(shareURL, FakeHouseholdBackend.shareURL(for: code) as URL?)

        let lookup = try await backend.lookup(code: code)
        XCTAssertEqual(lookup.status, HouseholdInviteStatus.pending.rawValue)
        let url = try XCTUnwrap(lookup.shareURL)
        try await backend.acceptShare(url: url)
        var partnerBoard = try XCTUnwrap(try await backend.pullShared(url: url))
        try HouseholdReducer.acceptInvite(
            snapshot: &partnerBoard,
            user: partner,
            code: code,
            now: now,
            memberId: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        )
        HouseholdReducer.publishTaste(snapshot: &partnerBoard, projection: HouseholdTestPartner.taste(now: now))
        partnerBoard = try await backend.push(partnerBoard)
        let householdId = try XCTUnwrap(partnerBoard.household?.id)
        ownerBoard = HouseholdConflictResolver.merge(
            local: ownerBoard,
            server: try XCTUnwrap(try await backend.pull(householdId: householdId))
        )
        XCTAssertEqual(ownerBoard.members.count, HouseholdLimits.maxMembers)
        XCTAssertNotNil(ownerBoard.member(partner.id))
        XCTAssertThrowsError(
            try HouseholdReducer.createInvite(snapshot: &ownerBoard, user: owner, now: now, seed: 7)
        ) { error in
            assertHouseholdError(error, .householdFull)
        }
        let stranger = HouseholdUser(id: "stranger", displayName: "Üçüncü", createdAt: now)
        XCTAssertThrowsError(
            try HouseholdReducer.acceptInvite(snapshot: &ownerBoard, user: stranger, code: code, now: now)
        ) { error in
            assertHouseholdError(error, .householdFull)
        }

        let firstMeal = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let secondMeal = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        try HouseholdReducer.installPlan(
            snapshot: &ownerBoard,
            drafts: [
                HouseholdMealDraft(dayOffset: 0, recipeSlug: "menemen", title: "Menemen", recipeOwnerUserId: nil),
                HouseholdMealDraft(dayOffset: 1, recipeSlug: "lahmacun", title: "Lahmacun", recipeOwnerUserId: nil),
            ],
            weekStart: now,
            actor: owner,
            now: now,
            planId: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            mealIds: [firstMeal, secondMeal]
        )
        try HouseholdReducer.setReaction(snapshot: &ownerBoard, mealId: firstMeal, user: owner, reaction: .want, now: now)
        ownerBoard = try await backend.push(ownerBoard)
        partnerBoard = try XCTUnwrap(try await backend.pull(householdId: householdId))
        try HouseholdReducer.setReaction(snapshot: &partnerBoard, mealId: firstMeal, user: partner, reaction: .okay, now: now)
        try HouseholdReducer.setReaction(snapshot: &partnerBoard, mealId: secondMeal, user: partner, reaction: .veto, now: now)
        partnerBoard = try await backend.push(partnerBoard)
        ownerBoard = HouseholdConflictResolver.merge(
            local: ownerBoard,
            server: try XCTUnwrap(try await backend.pull(householdId: householdId))
        )

        let vetoed = try XCTUnwrap(ownerBoard.plan?.meals.first { $0.id == secondMeal })
        XCTAssertEqual(vetoed.status, .vetoed)
        XCTAssertEqual(ownerBoard.plan?.status, .needsDecisions)
        XCTAssertEqual(
            HouseholdConflict.label(reactions: vetoed.reactions, memberIds: ownerBoard.members.map(\.userId)),
            .needsDecision
        )
        XCTAssertEqual(HouseholdConflict.label(reactions: vetoed.reactions, memberIds: ownerBoard.members.map(\.userId)).title, "Karar gerekiyor")
        let signal = try XCTUnwrap(ownerBoard.memory.first { $0.recipeSlug == "lahmacun" })
        XCTAssertGreaterThan(signal.vetoCount, 0)
        let partnerTaste = try XCTUnwrap(ownerBoard.tasteProjections.first { $0.userId == partner.id })
        XCTAssertEqual(partnerTaste.recipes["menemen"]?.neverAgain, false as Bool?)
        XCTAssertEqual(partnerTaste.recipes["iskender-kebab"]?.neverAgain, true as Bool?)

        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        context.insert(MealMemory(snapshot: MealMemorySnapshot(recipeID: "lahmacun", lovedCount: 1), updatedAt: now))
        try context.save()
        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<MealMemory>()).first { $0.recipeSlug == "lahmacun" })
        XCTAssertFalse(stored.neverAgain)

        let vetoSlugs: Set<String> = ["lahmacun"]
        let choices = HouseholdReplacement.choices(
            catalog: [
                TestFixtures.candidate("lahmacun", score: 90, minutes: 40),
                TestFixtures.candidate("menemen", score: 80, minutes: 25),
                TestFixtures.candidate("mercimek-corbasi", score: 70, minutes: 35),
            ],
            current: TestFixtures.candidate("lahmacun", score: 90, minutes: 40),
            tastes: ownerBoard.tasteProjections.map(MemberTasteProjectionBuilder.taste(from:)),
            memory: ownerBoard.memory,
            vetoSlugs: vetoSlugs,
            householdAvoided: [],
            maxCookMinutes: 90,
            intent: .surprise,
            currentUserId: owner.id
        )
        XCTAssertFalse(choices.contains { $0.slug == "lahmacun" })
        XCTAssertFalse(choices.isEmpty)

        let replacement = try XCTUnwrap(choices.first)
        try HouseholdReducer.replaceMeal(
            snapshot: &ownerBoard,
            mealId: secondMeal,
            slug: replacement.slug,
            title: replacement.slug,
            recipeOwnerUserId: nil,
            actor: owner,
            now: now
        )
        let replaced = try XCTUnwrap(ownerBoard.plan?.meals.first { $0.id == secondMeal })
        XCTAssertNotEqual(replaced.recipeSlug, "lahmacun")
        XCTAssertFalse(HouseholdConflict.needsDecision(replaced.reactions))
        ownerBoard = try await backend.push(ownerBoard)

        try syncGrocery(backend: backend, householdId: householdId, owner: owner, partner: partner, ownerBoard: &ownerBoard)

        let kinds = Set(ownerBoard.activities.map(\.kind))
        XCTAssertTrue(kinds.contains(.householdCreated))
        XCTAssertTrue(kinds.contains(.memberJoined))
        XCTAssertTrue(kinds.contains(.planGenerated))
        XCTAssertTrue(kinds.contains(.want))
        XCTAssertTrue(kinds.contains(.okay))
        XCTAssertTrue(kinds.contains(.veto))
        XCTAssertTrue(kinds.contains(.replacement))

        let vetoActivity = try XCTUnwrap(ownerBoard.activities.first { $0.kind == .veto })
        let push = HouseholdNotificationPolicy.make(activity: vetoActivity, recipientUserId: owner.id)
        XCTAssertEqual(push?.kind, .veto)
        XCTAssertNil(HouseholdNotificationPolicy.make(activity: vetoActivity, recipientUserId: partner.id))
        let wantActivity = try XCTUnwrap(ownerBoard.activities.first { $0.kind == .want })
        XCTAssertNil(HouseholdNotificationPolicy.make(activity: wantActivity, recipientUserId: partner.id))

        let suite = "household-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let mode = HouseholdTestMode(defaults: defaults, launchArguments: [])
        mode.setEnabled(true)
        mode.record([try XCTUnwrap(push)], audience: .local)
        XCTAssertEqual(mode.notices.count, 1)
        XCTAssertEqual(mode.banner?.body, push?.body)
        defaults.removePersistentDomain(forName: suite)
    }

    func testInviteExpiredRevokedAndUnknown() async throws {
        let backend = FakeHouseholdBackend()
        let owner = HouseholdUser(id: "owner-test", displayName: "Test Kullanıcı", createdAt: now)
        var board = try HouseholdReducer.createHousehold(user: owner, name: "Test Evi", now: now)
        let invite = try HouseholdReducer.createInvite(snapshot: &board, user: owner, now: now, seed: 99)
        _ = try await backend.publishInvite(invite, householdName: "Test Evi", snapshot: board)
        board = try XCTUnwrap(try await backend.pull(householdId: try XCTUnwrap(board.household?.id)))
        board.invites[0].expiresAt = now.addingTimeInterval(-60)
        board.invites[0].revision += 1
        board.revision += 1
        board = try await backend.push(board)
        let expired = try await backend.lookup(code: invite.inviteCode)
        XCTAssertLessThanOrEqual(expired.expiresAt, now)
        let joiner = HouseholdUser(id: "joiner", displayName: "Konuk", createdAt: now)
        XCTAssertThrowsError(try HouseholdReducer.acceptInvite(snapshot: &board, user: joiner, code: invite.inviteCode, now: now)) { error in
            assertHouseholdError(error, .inviteExpired)
        }

        var revokedBoard = try HouseholdReducer.createHousehold(user: owner, name: "Diğer", now: now)
        let live = try HouseholdReducer.createInvite(snapshot: &revokedBoard, user: owner, now: now, seed: 100)
        _ = try await backend.publishInvite(live, householdName: "Diğer", snapshot: revokedBoard)
        revokedBoard = try XCTUnwrap(try await backend.pull(householdId: try XCTUnwrap(revokedBoard.household?.id)))
        try HouseholdReducer.revokeInvite(snapshot: &revokedBoard, userId: owner.id, inviteId: live.id, now: now)
        revokedBoard = try await backend.push(revokedBoard)
        let lookup = try await backend.lookup(code: live.inviteCode)
        XCTAssertEqual(lookup.status, HouseholdInviteStatus.revoked.rawValue)
        XCTAssertThrowsError(try HouseholdReducer.acceptInvite(snapshot: &revokedBoard, user: joiner, code: live.inviteCode, now: now)) { error in
            assertHouseholdError(error, .inviteRevoked)
        }
        do {
            _ = try await backend.lookup(code: "ZZZZZZ")
            XCTFail("missing code")
        } catch let error as HouseholdError {
            XCTAssertEqual(error, .inviteNotFound)
        }
    }

    func testSameMealConcurrentEditKeepsTheServerReaction() async throws {
        let backend = FakeHouseholdBackend()
        let owner = HouseholdUser(id: "owner-test", displayName: "Test Kullanıcı", createdAt: now)
        let partner = HouseholdTestPartner.user(now: now)
        var ownerBoard = try twoMemberPlan(owner: owner, partner: partner)
        ownerBoard = try await backend.push(ownerBoard)
        let householdId = try XCTUnwrap(ownerBoard.household?.id)
        var partnerBoard = try XCTUnwrap(try await backend.pull(householdId: householdId))
        let mealId = try XCTUnwrap(ownerBoard.plan?.meals.first?.id)
        try HouseholdReducer.setReaction(snapshot: &ownerBoard, mealId: mealId, user: owner, reaction: .want, now: now)
        try HouseholdReducer.setReaction(snapshot: &partnerBoard, mealId: mealId, user: partner, reaction: .veto, now: now)
        partnerBoard = try await backend.push(partnerBoard)
        do {
            _ = try await backend.push(ownerBoard)
            XCTFail("same-meal push should conflict")
        } catch let conflict as HouseholdServerConflict {
            let merged = HouseholdConflictResolver.merge(local: ownerBoard, server: conflict.server)
            let meal = try XCTUnwrap(merged.plan?.meals.first { $0.id == mealId })
            XCTAssertTrue(meal.reactions.contains { $0.userId == partner.id && $0.reaction == .veto })
            XCTAssertFalse(meal.reactions.contains { $0.userId == owner.id && $0.reaction == .want })
            XCTAssertEqual(merged.plan?.status, .needsDecisions)
            XCTAssertEqual(HouseholdPlanRules.planStatus(meals: merged.plan?.meals ?? [], isFinalized: false), .needsDecisions)
        }
    }

    func testFakeBackendRoundTripsThroughSwiftData() async throws {
        let backend = FakeHouseholdBackend()
        let owner = HouseholdUser(id: "owner-test", displayName: "Test Kullanıcı", createdAt: now)
        var board = try HouseholdReducer.createHousehold(user: owner, name: "Önbellek", now: now)
        board = try await backend.push(board)
        let data = try backend.exportData()
        let container = try ModelContainerFactory.make(inMemory: true)
        let context = ModelContext(container)
        HouseholdCacheStore.saveData(data, updatedAt: now, in: context, key: HouseholdCacheBox.testServerKey)
        HouseholdCacheStore.save(board, in: context, key: HouseholdCacheBox.testClientKey)
        let restored = FakeHouseholdBackend()
        try restored.importData(try XCTUnwrap(HouseholdCacheStore.loadData(in: context, key: HouseholdCacheBox.testServerKey)))
        let loaded = HouseholdCacheStore.load(in: context, key: HouseholdCacheBox.testClientKey)
        let pulled = try await restored.pull(householdId: try XCTUnwrap(board.household?.id))
        XCTAssertEqual(loaded.household?.name, "Önbellek" as String?)
        XCTAssertEqual(pulled?.household?.name, "Önbellek" as String?)
        XCTAssertEqual(HouseholdCacheStore.load(in: context).household, nil)
    }

    private func syncGrocery(
        backend: FakeHouseholdBackend,
        householdId: UUID,
        owner: HouseholdUser,
        partner: HouseholdUser,
        ownerBoard: inout HouseholdSnapshot
    ) async throws {
        var partnerBoard = try XCTUnwrap(try await backend.pull(householdId: householdId))
        try HouseholdReducer.setGrocery(snapshot: &ownerBoard, itemKey: "domates|g", isChecked: true, user: owner, now: now)
        ownerBoard = try await backend.push(ownerBoard)
        try HouseholdReducer.setGrocery(snapshot: &partnerBoard, itemKey: "sogan|adet", isChecked: true, user: partner, now: now)
        do {
            partnerBoard = try await backend.push(partnerBoard)
        } catch let conflict as HouseholdServerConflict {
            partnerBoard = HouseholdConflictResolver.merge(local: partnerBoard, server: conflict.server)
            try HouseholdReducer.setGrocery(snapshot: &partnerBoard, itemKey: "sogan|adet", isChecked: true, user: partner, now: now.addingTimeInterval(1))
            partnerBoard = try await backend.push(partnerBoard)
        }
        ownerBoard = HouseholdConflictResolver.merge(
            local: ownerBoard,
            server: try XCTUnwrap(try await backend.pull(householdId: householdId))
        )
        let checks = Dictionary(uniqueKeysWithValues: ownerBoard.groceryCompletions.map { ($0.itemKey, $0.isChecked) })
        XCTAssertEqual(checks["domates|g"], true as Bool?)
        XCTAssertEqual(checks["sogan|adet"], true as Bool?)
        let partnerChecks = Dictionary(uniqueKeysWithValues: partnerBoard.groceryCompletions.map { ($0.itemKey, $0.isChecked) })
        XCTAssertEqual(partnerChecks["domates|g"], true as Bool?)
        XCTAssertEqual(partnerChecks["sogan|adet"], true as Bool?)
    }

    private func assertHouseholdError(
        _ error: Error,
        _ expected: HouseholdError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(error as? HouseholdError, Optional(expected), file: file, line: line)
    }

    private func twoMemberPlan(owner: HouseholdUser, partner: HouseholdUser) throws -> HouseholdSnapshot {
        var board = try HouseholdReducer.createHousehold(user: owner, name: "Test Evi", now: now)
        let invite = try HouseholdReducer.createInvite(snapshot: &board, user: owner, now: now, seed: 3)
        try HouseholdReducer.acceptInvite(snapshot: &board, user: partner, code: invite.inviteCode, now: now)
        try HouseholdReducer.installPlan(
            snapshot: &board,
            drafts: [HouseholdMealDraft(dayOffset: 0, recipeSlug: "menemen", title: "Menemen", recipeOwnerUserId: nil)],
            weekStart: now,
            actor: owner,
            now: now
        )
        HouseholdReducer.markSynced(&board)
        return board
    }
}
