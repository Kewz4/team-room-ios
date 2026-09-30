import Foundation
import XCTest
@testable import TeamRoom

final class ResponseDecodingTests: XCTestCase {
    private let endpoint = URL(string: "https://private.example/api/state?token=SECRET")!

    private func fixture(_ timestamps: [Any]) throws -> Data {
        let names = ["flint", "scout", "atlas", "nova", "sage"]
        let agents: [[String: Any]] = timestamps.enumerated().map { index, timestamp in
            var usage: [String: Any] = ["activity": "Fixed QA", "weekly": 80.0,
                "fiveHour": 51.0, "source": "owner status", "resetAt": NSNull()]
            if !(timestamp is Missing) { usage["updatedAt"] = timestamp }
            return ["id": names[index], "label": names[index].capitalized,
                "provider": "native", "modelLabel": "preserved", "effort": "high",
                "state": "idle", "connection": ["ready": true, "checkedAt": "2026-09-30T03:57:06Z"],
                "statusSummary": ["kind": "completed", "label": "Finished", "eventId": "fixed-evidence"],
                "usage": usage, "canStop": false, "messages": [], "queue": [], "events": [], "prompts": []]
        }
        return try JSONSerialization.data(withJSONObject: ["revision": 42, "mediaPreviews": true,
            "serverTime": "2026-09-30T03:57:06Z", "freeMemoryGb": 8.0, "agents": agents])
    }

    private struct Missing {}

    func testOriginalNumericMtimeDecodesFullStateAndRetainsUsage() throws {
        struct LegacyState: Decodable {
            struct LegacyAgent: Decodable {
                struct LegacyUsage: Decodable { var updatedAt: String? }
                var usage: LegacyUsage?
            }
            var agents: [LegacyAgent]
        }
        XCTAssertThrowsError(try JSONDecoder().decode(LegacyState.self, from: fixture([1790735536386.456])))
        let state = try ResponseDecoder.decode(StateResponse.self,
            from: fixture([1790735536386.456]), endpoint: endpoint)
        let usage = try XCTUnwrap(state.agents.first?.usage)
        let date = try XCTUnwrap(TimeFormat.date(usage.updatedAt))
        XCTAssertEqual(date.timeIntervalSince1970, 1790735536.386456, accuracy: 0.001)
        XCTAssertEqual(usage.weekly, 80)
        XCTAssertEqual(usage.fiveHour, 51)
        XCTAssertEqual(state.agents.first?.taskStatus.kind, "completed")
    }

    func testStringTimestampIsPreservedExactly() throws {
        let stamp = "2026-09-30T02:29:41Z"
        let state = try JSONDecoder().decode(StateResponse.self, from: fixture([stamp]))
        XCTAssertEqual(state.agents[0].usage?.updatedAt, stamp)
    }

    func testNullTimestampRemainsNil() throws {
        let state = try JSONDecoder().decode(StateResponse.self, from: fixture([NSNull()]))
        XCTAssertNil(state.agents[0].usage?.updatedAt)
    }

    func testMissingTimestampRemainsNil() throws {
        let state = try JSONDecoder().decode(StateResponse.self, from: fixture([Missing()]))
        XCTAssertNil(state.agents[0].usage?.updatedAt)
    }

    func testMixedFiveAccountStateDoesNotDiscardOtherAgents() throws {
        let state = try ResponseDecoder.decode(StateResponse.self,
            from: fixture([1790735536386.456, "2026-09-30T03:57:06Z", NSNull(), Missing(), 0]), endpoint: endpoint)
        XCTAssertEqual(state.agents.map(\.id), ["flint", "scout", "atlas", "nova", "sage"])
        XCTAssertEqual(state.agents[4].usage?.updatedAt, "1970-01-01T00:00:00.000Z")
        XCTAssertTrue(state.agents.allSatisfy { $0.connection?.ready == true })
    }

    func testNormalizedLegacyTimestampEncodesAsString() throws {
        let state = try JSONDecoder().decode(StateResponse.self, from: fixture([1790735536386.456]))
        let encoded = try JSONEncoder().encode(state)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let agents = try XCTUnwrap(object["agents"] as? [[String: Any]])
        let usage = try XCTUnwrap(agents[0]["usage"] as? [String: Any])
        XCTAssertTrue(usage["updatedAt"] is String)
    }

    func testUnsupportedTimestampShapesIdentifyFieldWithoutEchoingSecrets() throws {
        for value in [true, ["cookie": "BODY_SECRET"], ["BODY_SECRET"]] as [Any] {
            XCTAssertThrowsError(try ResponseDecoder.decode(StateResponse.self,
                from: fixture([value]), endpoint: endpoint)) { error in
                XCTAssertEqual((error as? ClientError)?.message,
                    "Unexpected response from /api/state at agents[0].usage.updatedAt.")
                XCTAssertFalse(error.localizedDescription.contains("SECRET"))
                XCTAssertFalse(error.localizedDescription.contains("private.example"))
            }
        }
    }

    func testOutOfRangeNumericTimestampFailsAtTimestampField() throws {
        for value in [1e308, -1e308] {
            XCTAssertThrowsError(try ResponseDecoder.decode(StateResponse.self,
                from: fixture([value]), endpoint: endpoint)) { error in
                XCTAssertEqual((error as? ClientError)?.message,
                    "Unexpected response from /api/state at agents[0].usage.updatedAt.")
            }
        }
    }

    func testOtherRequiredContractFailuresAreStillRejectedWithField() throws {
        let data = Data(#"{"agents":[{"id":"flint","label":true,"liveText":"BODY_SECRET"}]}"#.utf8)
        XCTAssertThrowsError(try ResponseDecoder.decode(StateResponse.self, from: data, endpoint: endpoint)) { error in
            XCTAssertEqual((error as? ClientError)?.message, "Unexpected response from /api/state at agents[0].label.")
        }
        XCTAssertThrowsError(try ResponseDecoder.decode(StateResponse.self,
            from: Data(#"{"agents":[{"id":"flint"}]}"#.utf8), endpoint: endpoint)) { error in
            XCTAssertEqual((error as? ClientError)?.message, "Unexpected response from /api/state at agents[0].label.")
        }
    }

    func testMalformedJSONGivesEndpointWithoutResponseBody() {
        XCTAssertThrowsError(try ResponseDecoder.decode(StateResponse.self,
            from: Data("BODY_SECRET invalid JSON".utf8), endpoint: endpoint)) { error in
            XCTAssertEqual((error as? ClientError)?.message, "Unexpected response from /api/state at response.")
        }
    }

    func testPrepaidBalanceDecodesWithoutUsageWindows() throws {
        let data = Data(#"{"revision":1,"agents":[{"id":"opencode-world","label":"Flint","provider":"dsh","state":"idle","usage":{"activity":"Terrain QA","source":"DeepSeek balance","updatedAt":"2026-09-30T16:30:00Z","balance":{"available":true,"currency":"USD","total":"12.34","granted":"0.00","toppedUp":"12.34","source":"DeepSeek /user/balance","updatedAt":"2026-09-30T16:30:00Z"}}}]}"#.utf8)
        let state = try JSONDecoder().decode(StateResponse.self, from: data)
        XCTAssertEqual(state.agents.first?.provider, "dsh")
        XCTAssertNil(state.agents.first?.usage?.weekly)
        XCTAssertNil(state.agents.first?.usage?.fiveHour)
        let balance = try XCTUnwrap(state.agents.first?.usage?.balance)
        XCTAssertTrue(balance.hasAmount)
        XCTAssertEqual(balance.currency, "USD")
        XCTAssertEqual(balance.source, "DeepSeek /user/balance")
        let amount = try XCTUnwrap(balance.displayAmount)
        XCTAssertTrue(amount.contains("12.34"), "expected the amount inside \(amount)")
        XCTAssertEqual(balance.walletAmounts, [amount], "a single wallet falls back to the primary amount")
    }

    func testMultiCurrencyWalletsAreListedWithThePrimaryFirst() throws {
        let data = Data(#"{"agents":[{"id":"opencode-world","label":"Flint","provider":"dsh","usage":{"balance":{"available":true,"currency":"CNY","total":"3.61","granted":"3.61","toppedUp":"0.00","source":"DeepSeek /user/balance","wallets":[{"currency":"CNY","total":"3.61","granted":"3.61","toppedUp":"0.00"},{"currency":"USD","total":"0.01","granted":"0.00","toppedUp":"0.01"}]}}}]}"#.utf8)
        let state = try JSONDecoder().decode(StateResponse.self, from: data)
        let balance = try XCTUnwrap(state.agents.first?.usage?.balance)
        let amounts = balance.walletAmounts
        XCTAssertEqual(amounts.count, 2, "both wallets must stay visible")
        XCTAssertTrue(amounts[0].contains("3.61"))
        XCTAssertTrue(amounts[1].contains("0.01"))
    }

    func testUnavailableBalanceKeepsItsReasonAndShowsNoAmount() throws {
        let data = Data(#"{"agents":[{"id":"opencode-world","label":"Flint","provider":"dsh","usage":{"balance":{"available":false,"source":"not configured","reason":"No DeepSeek key configured"}}}]}"#.utf8)
        let state = try JSONDecoder().decode(StateResponse.self, from: data)
        let balance = try XCTUnwrap(state.agents.first?.usage?.balance)
        XCTAssertFalse(balance.hasAmount)
        XCTAssertNil(balance.displayAmount)
        XCTAssertEqual(balance.reason, "No DeepSeek key configured")
    }

    func testAgentsWithoutABalanceStillDecode() throws {
        let state = try JSONDecoder().decode(StateResponse.self, from: fixture(["2026-09-30T03:57:06Z"]))
        XCTAssertNil(state.agents[0].usage?.balance)
        XCTAssertEqual(state.agents[0].usage?.weekly, 80)
    }

    func testMalformedBalanceIsRejectedAtItsFieldPathWithoutEchoingTheBody() throws {
        let data = Data(#"{"agents":[{"id":"flint","label":"Flint","usage":{"balance":"BODY_SECRET"}}]}"#.utf8)
        XCTAssertThrowsError(try ResponseDecoder.decode(StateResponse.self, from: data, endpoint: endpoint)) { error in
            XCTAssertEqual((error as? ClientError)?.message, "Unexpected response from /api/state at agents[0].usage.balance.")
            XCTAssertFalse(error.localizedDescription.contains("BODY_SECRET"))
        }
    }
}
