import Foundation

/// Shared assertions for the Linux script and the XCTest target.
enum HouseholdLogicChecks {
    static func runAll() -> [String] {
        var failures: [String] = []
        func check(_ name: String, _ body: () throws -> Void) {
            do {
                try body()
            } catch {
                failures.append("\(name): \(error)")
            }
        }
        check("create invite accept") { try assertCreateInviteAccept() }
        check("invite edges") { try assertInviteEdges() }
        check("veto is not never again") { try assertVetoIsNotNeverAgain() }
        check("conflict labels") { try assertConflictLabels() }
        check("replacement filters") { try assertReplacementFilters() }
        check("grocery sync") { try assertGrocerySync() }
        check("two member score") { try assertTwoMemberScore() }
        check("server wins same meal") { try assertServerWinsSameMeal() }
        check("different meals both survive") { try assertDifferentMealsMerge() }
        check("recipe ownership") { try assertRecipeOwnership() }
        check("notifications") { try assertNotifications() }
        check("plan status") { try assertPlanStatus() }
        return failures
    }

    private static func assertCreateInviteAccept() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let owner = HouseholdUser(id: "apple-owner", displayName: "Berkay", createdAt: now)
        var snapshot = try HouseholdReducer.createHousehold(user: owner, name: "  Ev  ", now: now, householdId: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!)
        try expect(snapshot.household?.name == "Ev", "trimmed name")
        try expect(snapshot.role(of: owner.id) == .owner, "owner role")
        try expect(snapshot.members.count == 1, "one member")
        let invite = try HouseholdReducer.createInvite(snapshot: &snapshot, user: owner, now: now, seed: 42)
        try expect(invite.inviteCode.count == 6, "code length")
        try expect(HouseholdInviteLink.code(from: HouseholdInviteLink.url(for: invite.inviteCode)) == invite.inviteCode, "link roundtrip")
        let partner = HouseholdUser(id: "apple-partner", displayName: "Ayşe", createdAt: now)
        try HouseholdReducer.acceptInvite(snapshot: &snapshot, user: partner, code: invite.inviteCode.lowercased(), now: now.addingTimeInterval(60))
        try expect(snapshot.members.count == 2, "two members")
        try expect(snapshot.role(of: partner.id) == .member, "member role")
        try expect(snapshot.members.count == HouseholdLimits.maxMembers, "cap")
        let third = HouseholdUser(id: "apple-third", displayName: "Üçüncü", createdAt: now)
        try expectThrows(HouseholdError.householdFull) {
            try HouseholdReducer.acceptInvite(snapshot: &snapshot, user: third, code: "ZZZZZZ", now: now)
        }
    }

    private static func assertInviteEdges() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let owner = HouseholdUser(id: "owner", displayName: "Berkay", createdAt: now)
        var snapshot = try HouseholdReducer.createHousehold(user: owner, name: "Ev", now: now)
        let invite = try HouseholdReducer.createInvite(snapshot: &snapshot, user: owner, now: now, seed: 7)
        var expired = snapshot
        try expectThrows(HouseholdError.inviteExpired) {
            try HouseholdReducer.acceptInvite(
                snapshot: &expired,
                user: HouseholdUser(id: "p", displayName: "Eş", createdAt: now),
                code: invite.inviteCode,
                now: invite.expiresAt.addingTimeInterval(1)
            )
        }
        try HouseholdReducer.revokeInvite(snapshot: &snapshot, userId: owner.id, inviteId: invite.id, now: now)
        try expectThrows(HouseholdError.inviteRevoked) {
            try HouseholdReducer.acceptInvite(
                snapshot: &snapshot,
                user: HouseholdUser(id: "p", displayName: "Eş", createdAt: now),
                code: invite.inviteCode,
                now: now
            )
        }
        try expectThrows(HouseholdError.notOwner) {
            var fresh = try HouseholdReducer.createHousehold(user: owner, name: "Ev", now: now)
            _ = try HouseholdReducer.createInvite(
                snapshot: &fresh,
                user: HouseholdUser(id: "other", displayName: "X", createdAt: now),
                now: now,
                seed: 1
            )
        }
    }

    private static func assertVetoIsNotNeverAgain() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let owner = HouseholdUser(id: "owner", displayName: "Berkay", createdAt: now)
        let partner = HouseholdUser(id: "partner", displayName: "Ayşe", createdAt: now)
        var snapshot = try joined(owner: owner, partner: partner, now: now)
        let mealId = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        try HouseholdReducer.installPlan(
            snapshot: &snapshot,
            drafts: [HouseholdMealDraft(dayOffset: 2, recipeSlug: "beyti", title: "Beyti Sarma", recipeOwnerUserId: nil)],
            weekStart: now,
            actor: owner,
            now: now,
            mealIds: [mealId]
        )
        let personal = MealMemorySnapshot(recipeID: "beyti")
        try HouseholdReducer.setReaction(snapshot: &snapshot, mealId: mealId, user: partner, reaction: .veto, now: now)
        try expect(personal.neverAgain == false, "veto does not write never again")
        try expect(snapshot.plan?.meals.first?.status == .vetoed, "meal vetoed")
        try expect(HouseholdConflict.needsDecision(snapshot.plan?.meals.first?.reactions ?? []), "conflict")
        let exclusion = HouseholdRecommendation.exclusion(
            for: candidate("beyti"),
            tastes: [taste(owner, loved: ["beyti"]), taste(partner, loved: ["beyti"])],
            vetoSlugs: ["beyti"],
            householdAvoided: [],
            maxCookMinutes: 60
        )
        try expect(exclusion == .currentHouseholdVeto, "veto beats love")
        var banned = MealMemorySnapshot(recipeID: "asla")
        banned.neverAgain = true
        let never = HouseholdRecommendation.exclusion(
            for: candidate("asla", score: 99),
            tastes: [
                MemberTaste(userId: owner.id, displayName: owner.displayName, memories: ["asla": banned], dislikedIngredientIds: []),
                taste(partner, loved: ["asla"]),
            ],
            vetoSlugs: [],
            householdAvoided: [],
            maxCookMinutes: 90
        )
        try expect(never == .neverAgain, "never again stays personal and hard")
        try expect(banned.neverAgain, "personal flag remains")
    }

    private static func assertConflictLabels() throws {
        let want = MealReaction(id: UUID(), sharedMealId: UUID(), userId: "a", reaction: .want, createdAt: .now)
        let okay = MealReaction(id: UUID(), sharedMealId: UUID(), userId: "b", reaction: .okay, createdAt: .now)
        let veto = MealReaction(id: UUID(), sharedMealId: UUID(), userId: "b", reaction: .veto, createdAt: .now)
        try expect(HouseholdConflict.label(reactions: [want, MealReaction(id: UUID(), sharedMealId: UUID(), userId: "b", reaction: .want, createdAt: .now)], memberIds: ["a", "b"]) == .greatMatch, "both want")
        try expect(HouseholdConflict.label(reactions: [want, okay], memberIds: ["a", "b"]) == .goodMatch, "want okay")
        try expect(HouseholdConflict.label(reactions: [want], memberIds: ["a", "b"]) == .unsure, "waiting")
        try expect(HouseholdConflict.label(reactions: [want, veto], memberIds: ["a", "b"]) == .needsDecision, "veto")
    }

    private static func assertReplacementFilters() throws {
        let owner = MemberTaste(userId: "owner", displayName: "Berkay", memories: [
            "sis": loved("sis"),
            "makarna": loved("makarna"),
        ], dislikedIngredientIds: [])
        var partnerMemory = loved("sis")
        partnerMemory.timesCooked = 2
        var mushroomDislike = MealMemorySnapshot(recipeID: "mantarli")
        mushroomDislike.timesReplaced = 3
        let partner = MemberTaste(userId: "partner", displayName: "Ayşe", memories: [
            "sis": partnerMemory,
            "makarna": MealMemorySnapshot(recipeID: "makarna", okayCount: 1, latestRating: .okay),
            "asla": MealMemorySnapshot(recipeID: "asla", neverAgain: true),
            "mantarli": mushroomDislike,
        ], dislikedIngredientIds: ["mushroom"])
        let current = candidate("beyti", minutes: 50, protein: "red-meat")
        let catalog = [
            current,
            candidate("sis", minutes: 40, protein: "poultry", ingredientIds: ["chicken"]),
            candidate("makarna", minutes: 25, protein: "dairy"),
            candidate("asla", minutes: 15, protein: "tofu"),
            candidate("mantarli", minutes: 20, protein: "legume", ingredientIds: ["mushroom"]),
            candidate("kofte", minutes: 35, protein: "red-meat"),
        ]
        let bothChoices = HouseholdReplacement.choices(
            catalog: catalog,
            current: current,
            tastes: [owner, partner],
            memory: [],
            vetoSlugs: ["beyti"],
            householdAvoided: [],
            maxCookMinutes: 60,
            intent: .bothWillLike,
            currentUserId: owner.userId
        )
        let both = bothChoices.map(\.slug)
        try expect(both.contains("sis"), "both like sis")
        try expect(bothChoices.contains { $0.slug == "sis" && $0.reason == "İkiniz de sever" }, "both will like reason")
        try expect(!both.contains("asla"), "never again out")
        try expect(!both.contains("beyti"), "current veto out")
        try expect(!both.contains("mantarli"), "strong dislike out")
        let neutral = MemberTaste(userId: "partner", displayName: "Ayşe", memories: [:], dislikedIngredientIds: [])
        let mushroom = candidate("orman", minutes: 30, protein: "legume", ingredientIds: ["porcini-mushroom"])
        let noMushroom = HouseholdReplacement.choices(
            catalog: catalog + [mushroom],
            current: current,
            tastes: [owner, neutral],
            memory: [],
            vetoSlugs: [],
            householdAvoided: [],
            maxCookMinutes: 60,
            intent: .noMushrooms,
            currentUserId: owner.userId
        ).map(\.slug)
        try expect(!noMushroom.contains("orman"), "mushroom filter")
        try expect(noMushroom.contains("makarna"), "other meals stay")
        let faster = HouseholdReplacement.choices(
            catalog: catalog,
            current: current,
            tastes: [owner, partner],
            memory: [],
            vetoSlugs: [],
            householdAvoided: [],
            maxCookMinutes: 60,
            intent: .faster,
            currentUserId: owner.userId
        )
        try expect(faster.allSatisfy { $0.minutes < current.totalMinutes }, "faster")
    }

    private static func assertGrocerySync() throws {
        let earlier = Date(timeIntervalSince1970: 100)
        let later = Date(timeIntervalSince1970: 200)
        let local = HouseholdGroceryCompletion(itemKey: "milk|l", isChecked: true, updatedAt: later, updatedBy: "a", revision: 2, baseRevision: 1)
        let server = HouseholdGroceryCompletion(itemKey: "milk|l", isChecked: false, updatedAt: earlier, updatedBy: "b", revision: 4, baseRevision: 4)
        let merged = GroceryCompletionSync.merge(local: local, server: server)
        try expect(merged.isChecked == false && merged.revision == 4, "higher server revision wins")
        let sameRevisionLocal = HouseholdGroceryCompletion(itemKey: "milk|l", isChecked: true, updatedAt: later, updatedBy: "a", revision: 3, baseRevision: 2)
        let sameRevisionServer = HouseholdGroceryCompletion(itemKey: "milk|l", isChecked: false, updatedAt: earlier, updatedBy: "b", revision: 3, baseRevision: 3)
        let laterWins = GroceryCompletionSync.merge(local: sameRevisionLocal, server: sameRevisionServer)
        try expect(laterWins.isChecked == true, "later timestamp on equal revision")
        let tieLocal = HouseholdGroceryCompletion(itemKey: "yogurt|kg", isChecked: false, updatedAt: earlier, updatedBy: "a", revision: 1, baseRevision: 1)
        let tieServer = HouseholdGroceryCompletion(itemKey: "yogurt|kg", isChecked: true, updatedAt: earlier, updatedBy: "b", revision: 1, baseRevision: 1)
        try expect(GroceryCompletionSync.merge(local: tieLocal, server: tieServer).isChecked, "tie adopts server")
    }

    private static func assertTwoMemberScore() throws {
        let lovedChicken = candidate("sis", score: 40, protein: "poultry")
        let disliked = candidate("mantar", score: 90, ingredientIds: ["mushroom"])
        let fresh = candidate("yeni", score: 70, protein: "legume", cuisine: "TR", category: "stew")
        let owner = MemberTaste(userId: "a", displayName: "Berkay", memories: [
            "sis": loved("sis"),
        ], dislikedIngredientIds: [])
        let partner = MemberTaste(userId: "b", displayName: "Ayşe", memories: [
            "sis": loved("sis"),
        ], dislikedIngredientIds: ["mushroom"])
        let memory = [
            HouseholdMemorySignal(
                recipeSlug: "sis",
                togetherCooked: 5,
                bothLiked: 4,
                splitReaction: 0,
                vetoCount: 0,
                selectedCount: 5,
                replacedCount: 0,
                skippedCount: 0,
                revision: 2,
                baseRevision: 2
            ),
        ]
        try expect(
            HouseholdRecommendation.exclusion(for: disliked, tastes: [owner, partner], vetoSlugs: [], householdAvoided: [], maxCookMinutes: 60) == .strongPersonalDislike,
            "partner dislike"
        )
        let vetoed = HouseholdRecommendation.exclusion(
            for: lovedChicken,
            tastes: [owner, partner],
            vetoSlugs: ["sis"],
            householdAvoided: [],
            maxCookMinutes: 60
        )
        try expect(vetoed == .currentHouseholdVeto, "current veto excludes a favorite")
        let sis = HouseholdRecommendation.score(lovedChicken, tastes: [owner, partner], memory: memory, anchors: [], preferredCategories: [], preferredProteins: [])
        let yeni = HouseholdRecommendation.score(fresh, tastes: [owner, partner], memory: [], anchors: [], preferredCategories: [], preferredProteins: [])
        try expect(sis > yeni, "shared favorite outranks discovery")
        let slugs = HouseholdPlanner.slugs(
            candidates: [lovedChicken, disliked, fresh, candidate("asla", score: 100)],
            evenings: 2,
            dayOffsets: [0, 1],
            maxCookMinutes: 60,
            weekdayCap: nil,
            tastes: [
                owner,
                MemberTaste(
                    userId: "b",
                    displayName: "Ayşe",
                    memories: [
                        "sis": loved("sis"),
                        "asla": MealMemorySnapshot(recipeID: "asla", neverAgain: true),
                    ],
                    dislikedIngredientIds: ["mushroom"]
                ),
            ],
            memory: memory,
            vetoSlugs: [],
            householdAvoided: []
        )
        try expect(slugs.first == "sis", "planner leads with compatibility")
        try expect(!slugs.contains("asla") && !slugs.contains("mantar"), "exclusions stay out")
    }

    private static func assertServerWinsSameMeal() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let owner = HouseholdUser(id: "owner", displayName: "Berkay", createdAt: now)
        let partner = HouseholdUser(id: "partner", displayName: "Ayşe", createdAt: now)
        var base = try joined(owner: owner, partner: partner, now: now)
        let mealId = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        try HouseholdReducer.installPlan(
            snapshot: &base,
            drafts: [HouseholdMealDraft(dayOffset: 0, recipeSlug: "tavuk", title: "Tavuk", recipeOwnerUserId: nil)],
            weekStart: now,
            actor: owner,
            now: now,
            mealIds: [mealId]
        )
        HouseholdReducer.markSynced(&base)
        var local = base
        var server = base
        try HouseholdReducer.replaceMeal(
            snapshot: &local,
            mealId: mealId,
            slug: "kofte",
            title: "Köfte",
            recipeOwnerUserId: nil,
            actor: owner,
            now: now.addingTimeInterval(10)
        )
        try HouseholdReducer.setReaction(
            snapshot: &server,
            mealId: mealId,
            user: partner,
            reaction: .veto,
            now: now.addingTimeInterval(20)
        )
        HouseholdReducer.markSynced(&server)
        let merged = HouseholdConflictResolver.merge(local: local, server: server)
        try expect(merged.plan?.meals.first?.recipeSlug == "tavuk", "server meal stays")
        try expect(merged.plan?.meals.first?.reactions.contains { $0.reaction == .veto } == true, "server veto kept")
    }

    private static func assertDifferentMealsMerge() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let owner = HouseholdUser(id: "owner", displayName: "Berkay", createdAt: now)
        let partner = HouseholdUser(id: "partner", displayName: "Ayşe", createdAt: now)
        var base = try joined(owner: owner, partner: partner, now: now)
        let monday = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let wednesday = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
        try HouseholdReducer.installPlan(
            snapshot: &base,
            drafts: [
                HouseholdMealDraft(dayOffset: 0, recipeSlug: "tavuk", title: "Tavuk", recipeOwnerUserId: nil),
                HouseholdMealDraft(dayOffset: 2, recipeSlug: "beyti", title: "Beyti", recipeOwnerUserId: nil),
            ],
            weekStart: now,
            actor: owner,
            now: now,
            mealIds: [monday, wednesday]
        )
        HouseholdReducer.markSynced(&base)
        var local = base
        var server = base
        try HouseholdReducer.replaceMeal(
            snapshot: &local,
            mealId: monday,
            slug: "kofte",
            title: "Köfte",
            recipeOwnerUserId: nil,
            actor: owner,
            now: now.addingTimeInterval(5)
        )
        try HouseholdReducer.setReaction(
            snapshot: &server,
            mealId: wednesday,
            user: partner,
            reaction: .veto,
            now: now.addingTimeInterval(5)
        )
        HouseholdReducer.markSynced(&server)
        let merged = HouseholdConflictResolver.merge(local: local, server: server)
        let meals = Dictionary(uniqueKeysWithValues: (merged.plan?.meals ?? []).map { ($0.id, $0) })
        try expect(meals[monday]?.recipeSlug == "kofte", "local replacement kept")
        try expect(meals[wednesday]?.status == .vetoed, "server veto kept")
    }

    private static func assertRecipeOwnership() throws {
        let projection = HouseholdRecipeProjection(
            slug: "annemin-makarna",
            ownerUserId: "owner",
            title: "Annemin Makarna Tarifi",
            totalMinutes: 30,
            ingredientIds: ["pasta"],
            protein: "dairy",
            category: "pasta",
            cuisine: "TR",
            diets: [],
            isReadyToCook: true,
            revision: 1,
            baseRevision: 0
        )
        try expect(HouseholdRecipeAccess.visibleForPlanning([projection]).count == 1, "visible")
        try expect(!HouseholdRecipeAccess.copiesIntoPersonalCollection(projection, viewerId: "partner"), "no copy")
        try expect(HouseholdRecipeAccess.isOwnedByViewer(projection, viewerId: "owner"), "owner")
        try expect(!HouseholdRecipeAccess.isOwnedByViewer(projection, viewerId: "partner"), "partner does not own")
        var snapshot = HouseholdSnapshot.empty(now: Date(timeIntervalSince1970: 10))
        HouseholdReducer.publishRecipes(snapshot: &snapshot, projections: [projection], ownerId: "owner")
        try expect(snapshot.recipeProjections.first?.ownerUserId == "owner", "publish keeps owner")
    }

    private static func assertNotifications() throws {
        let now = Date(timeIntervalSince1970: 50)
        let veto = HouseholdActivity(id: UUID(), householdId: UUID(), actorId: "a", actorName: "Ayşe", kind: .veto, mealTitle: "Beyti", detail: "Veto", createdAt: now)
        let push = HouseholdNotificationPolicy.make(activity: veto, recipientUserId: "b")
        try expect(push?.kind == .veto, "veto push")
        try expect(push?.body.contains("Beyti") == true, "meal in body")
        try expect(HouseholdNotificationPolicy.make(activity: veto, recipientUserId: "a") == nil, "no self push")
        let okay = HouseholdActivity(id: UUID(), householdId: UUID(), actorId: "a", actorName: "Ayşe", kind: .okay, mealTitle: "Köfte", detail: "Olur", createdAt: now)
        try expect(HouseholdNotificationPolicy.make(activity: okay, recipientUserId: "b") == nil, "okay is not a push")
        let grocery = HouseholdActivity(id: UUID(), householdId: UUID(), actorId: "a", actorName: "Ayşe", kind: .groceryChecked, mealTitle: "Süt", detail: "Alındı", createdAt: now)
        try expect(HouseholdNotificationPolicy.make(activity: grocery, recipientUserId: "b") == nil, "grocery is not a push")
        let review = HouseholdActivity(id: UUID(), householdId: UUID(), actorId: "a", actorName: "Berkay", kind: .planGenerated, mealTitle: "Bu hafta", detail: "", createdAt: now)
        try expect(HouseholdNotificationPolicy.make(activity: review, recipientUserId: "b")?.kind == .planReview, "review")
        let replacement = HouseholdActivity(id: UUID(), householdId: UUID(), actorId: "a", actorName: "Berkay", kind: .replacement, mealTitle: "Köfte", detail: "", createdAt: now)
        try expect(HouseholdNotificationPolicy.make(activity: replacement, recipientUserId: "b")?.kind == .replacement, "replacement")
        let finalized = HouseholdActivity(id: UUID(), householdId: UUID(), actorId: "a", actorName: "Berkay", kind: .planFinalized, mealTitle: "Bu hafta", detail: "", createdAt: now)
        try expect(HouseholdNotificationPolicy.make(activity: finalized, recipientUserId: "b")?.kind == .planFinalized, "finalized")
    }

    private static func assertPlanStatus() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let owner = HouseholdUser(id: "owner", displayName: "Berkay", createdAt: now)
        let partner = HouseholdUser(id: "partner", displayName: "Ayşe", createdAt: now)
        var snapshot = try joined(owner: owner, partner: partner, now: now)
        let mealId = UUID()
        try HouseholdReducer.installPlan(
            snapshot: &snapshot,
            drafts: [HouseholdMealDraft(dayOffset: 0, recipeSlug: "corba", title: "Çorba", recipeOwnerUserId: owner.id)],
            weekStart: now,
            actor: owner,
            now: now,
            mealIds: [mealId]
        )
        try expect(snapshot.plan?.status == .draft, "draft before reactions")
        try HouseholdReducer.setReaction(snapshot: &snapshot, mealId: mealId, user: owner, reaction: .want, now: now)
        try expect(snapshot.plan?.status == .draft, "still waiting")
        try HouseholdReducer.setReaction(snapshot: &snapshot, mealId: mealId, user: partner, reaction: .okay, now: now)
        try expect(snapshot.plan?.status == .ready, "ready")
        try HouseholdReducer.finalize(snapshot: &snapshot, actor: owner, now: now)
        try expect(snapshot.plan?.isFinalized == true, "finalized")
        try expect(snapshot.activities.contains { $0.kind == .planFinalized }, "history")
    }

    private static func joined(owner: HouseholdUser, partner: HouseholdUser, now: Date) throws -> HouseholdSnapshot {
        var snapshot = try HouseholdReducer.createHousehold(user: owner, name: "Ev", now: now)
        let invite = try HouseholdReducer.createInvite(snapshot: &snapshot, user: owner, now: now, seed: 99)
        try HouseholdReducer.acceptInvite(snapshot: &snapshot, user: partner, code: invite.inviteCode, now: now)
        return snapshot
    }

    private static func taste(_ user: HouseholdUser, loved slugs: [String]) -> MemberTaste {
        var memories: [String: MealMemorySnapshot] = [:]
        for slug in slugs { memories[slug] = loved(slug) }
        return MemberTaste(userId: user.id, displayName: user.displayName, memories: memories, dislikedIngredientIds: [])
    }

    private static func loved(_ slug: String) -> MealMemorySnapshot {
        MealMemorySnapshot(recipeID: slug, lovedCount: 1, latestRating: .loved, isFavorite: true)
    }

    private static func candidate(
        _ slug: String,
        score: Int = 50,
        minutes: Int = 30,
        protein: String = "poultry",
        ingredientIds: Set<String> = [],
        cuisine: String = "TR",
        category: String = "skillet"
    ) -> PickerCandidate {
        PickerCandidate(
            slug: slug,
            totalMinutes: minutes,
            trDogfoodScore: score,
            ingredientIds: ingredientIds,
            rating: nil,
            cuisine: cuisine,
            category: category,
            tags: [],
            protein: protein
        )
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw CheckError(message) }
    }

    private static func expectThrows(_ expected: HouseholdError, _ body: () throws -> Void) throws {
        do {
            try body()
            throw CheckError("expected \(expected)")
        } catch let error as HouseholdError {
            if error != expected { throw CheckError("expected \(expected) got \(error)") }
        }
    }
}

private struct CheckError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}
