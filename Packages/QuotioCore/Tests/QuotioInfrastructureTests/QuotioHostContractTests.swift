import QuotioHostClient
import Foundation
import XCTest
@testable import QuotioInfrastructure

final class QuotioHostContractTests: XCTestCase {
    private func fixture() throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../").standardizedFileURL
        return try Data(contentsOf: root.appendingPathComponent("apps/cli/tests/fixtures/contracts/snapshot-v2.json"))
    }

    func testResolvedNamesSourcesAndPlanOnlyUsageAreNotReinterpreted() throws {
        let snapshot = try QuotioHostSnapshot.decode(fixture())
        XCTAssertEqual(snapshot.accounts.map(\.displayName), ["fixture-user", "person@example.test"])
        XCTAssertEqual(snapshot.accounts[1].sources.count, 2)
        XCTAssertEqual(snapshot.usage[0].accountId, snapshot.accounts[0].id)
        XCTAssertEqual(snapshot.usage[0].freshness, "fresh")
        XCTAssertEqual(snapshot.usage[0].plan, "Business")
        XCTAssertTrue(snapshot.usage[0].metrics.isEmpty)
        XCTAssertEqual(snapshot.usage[1].metrics[0].quota.remainingPercent, 75)
    }

    func testUnknownProvidersAndAdditiveFieldsDecodeButUnknownMajorVersionFails() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
        var accounts = try XCTUnwrap(object["accounts"] as? [[String: Any]])
        accounts[0]["provider_id"] = "future-provider"
        accounts[0]["future_optional_field"] = true
        object["accounts"] = accounts
        let snapshot = try QuotioHostSnapshot.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(snapshot.accounts[0].providerId, "future-provider")
        XCTAssertEqual(snapshot.accounts[0].displayName, "fixture-user")
        object["schema_version"] = 3
        XCTAssertThrowsError(try QuotioHostSnapshot.decode(JSONSerialization.data(withJSONObject: object)))
    }
}
