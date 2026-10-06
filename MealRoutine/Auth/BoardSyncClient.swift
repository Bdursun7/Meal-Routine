import Foundation

enum BoardSyncFailure: Error, Equatable {
    case conflict
    case retry
    case offline
}

struct BoardChangePage: Decodable, Equatable, Sendable {
    var cursor: Int
    var changes: [BoardChangeRow]
}

struct BoardChangeRow: Decodable, Equatable, Sendable {
    var cursor: Int
    var entityType: String
    var entityId: String
    var operationType: String
    var revision: Int
}

/// Shared-data mutations. The same Idempotency-Key is sent on every retry.
struct BoardSyncClient: Sendable {
    var client: APIClient

    func mutate(householdId: UUID, idempotencyKey: String, body: Data) async throws {
        let (data, http) = try await perform(
            method: "POST",
            path: "/v1/households/\(householdId.uuidString)/mutations",
            body: body,
            headers: ["Idempotency-Key": idempotencyKey]
        )
        if (200..<300).contains(http.statusCode) { return }
        if http.statusCode == 409 {
            let code = (try? JSONDecoder().decode(BoardErrorBody.self, from: data))?.error
            if code == "version_conflict" { throw BoardSyncFailure.conflict }
        }
        throw BoardSyncFailure.retry
    }

    func changes(householdId: UUID, cursor: Int) async throws -> BoardChangePage {
        let (data, http) = try await perform(
            method: "GET",
            path: "/v1/households/\(householdId.uuidString)/changes?cursor=\(cursor)",
            body: nil,
            headers: [:]
        )
        guard (200..<300).contains(http.statusCode) else { throw BoardSyncFailure.retry }
        return try JSONDecoder().decode(BoardChangePage.self, from: data)
    }

    private func perform(
        method: String,
        path: String,
        body: Data?,
        headers: [String: String]
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await client.request(method: method, path: path, body: body, authenticated: true, headers: headers)
        } catch AuthAPIError.sessionExpired {
            throw HouseholdError.sessionExpired
        } catch AuthAPIError.transport {
            throw BoardSyncFailure.offline
        } catch let error as BoardSyncFailure {
            throw error
        } catch {
            throw BoardSyncFailure.retry
        }
    }
}

enum BoardMutationEncoder {
    static func reaction(mealId: UUID, reactionBase: Int, mealRevision: Int, reaction: String) -> Data {
        encode(
            entityType: "reaction",
            entityId: mealId.uuidString,
            operationType: "set",
            baseRevision: reactionBase,
            payload: ["reaction": reaction, "mealRevision": mealRevision]
        )
    }

    static func replace(mealId: UUID, baseRevision: Int, slug: String, title: String) -> Data {
        encode(
            entityType: "meal",
            entityId: mealId.uuidString,
            operationType: "replace",
            baseRevision: baseRevision,
            payload: ["recipeSlug": slug, "title": title]
        )
    }

    static func groceryAdd(id: UUID, itemKey: String, quantity: Int, baseRevision: Int) -> Data {
        encode(
            entityType: "grocery",
            entityId: id.uuidString,
            operationType: "add",
            baseRevision: baseRevision,
            payload: ["itemKey": itemKey, "quantity": quantity]
        )
    }

    static func plan(_ plan: SharedMealPlan, baseRevision: Int) -> Data {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let meals: [[String: Any]] = plan.meals.map { meal in
            [
                "id": meal.id.uuidString,
                "dayOffset": meal.dayOffset,
                "recipeSlug": meal.recipeSlug,
                "title": meal.title,
                "status": meal.status.rawValue,
            ]
        }
        return encode(
            entityType: "plan",
            entityId: plan.id.uuidString,
            operationType: "upsert",
            baseRevision: baseRevision,
            payload: [
                "weekStart": formatter.string(from: plan.weekStart),
                "status": plan.status.rawValue,
                "isFinalized": plan.isFinalized,
                "meals": meals,
            ]
        )
    }

    static func preference(
        householdId: UUID,
        baseRevision: Int,
        cookingDays: [Int],
        maxWeekdayMinutes: Int,
        preferredCategories: [String],
        preferredProteins: [String],
        avoidedIngredients: [String]
    ) -> Data {
        encode(
            entityType: "preference",
            entityId: householdId.uuidString,
            operationType: "update",
            baseRevision: baseRevision,
            payload: [
                "cookingDays": cookingDays,
                "maxWeekdayMinutes": maxWeekdayMinutes,
                "preferredCategories": preferredCategories,
                "preferredProteins": preferredProteins,
                "avoidedIngredients": avoidedIngredients,
            ]
        )
    }

    static func cook(mealId: UUID, baseRevision: Int) -> Data {
        encode(
            entityType: "meal",
            entityId: mealId.uuidString,
            operationType: "cook",
            baseRevision: baseRevision,
            payload: [:]
        )
    }

    static func groceryCheck(id: UUID, baseRevision: Int, isChecked: Bool) -> Data {
        encode(
            entityType: "grocery",
            entityId: id.uuidString,
            operationType: "check",
            baseRevision: baseRevision,
            payload: ["isChecked": isChecked]
        )
    }

    private static func encode(
        entityType: String,
        entityId: String,
        operationType: String,
        baseRevision: Int,
        payload: [String: Any]
    ) -> Data {
        let object: [String: Any] = [
            "entityType": entityType,
            "entityId": entityId,
            "operationType": operationType,
            "baseRevision": baseRevision,
            "payload": payload,
        ]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}

private struct BoardErrorBody: Decodable {
    var error: String
}
