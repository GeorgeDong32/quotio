import XCTest
@testable import Quotio

final class AppIdentityTests: XCTestCase {
    // Fork: ships as dev.quotio.desktop, which counts as production for
    // capability gates; the upstream bytrong domain is a legacy id here.
    func testProductionBundleIdentifierUsesForkDomain() {
        XCTAssertEqual(AppIdentity.productionBundleIdentifier, "dev.quotio.desktop")
        XCTAssertEqual(
            AppIdentity.quotioCLIVaultNamespace(for: AppIdentity.productionBundleIdentifier),
            "quotio-macos"
        )
        let legacy = AppIdentity.quotioCLIVaultNamespace(for: "app.bytrong.quotio")
        XCTAssertNotEqual(legacy, "quotio-macos")
        XCTAssertLessThanOrEqual(legacy.count, 32)
        XCTAssertTrue(legacy.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" })
    }

    func testApplicationBundleContainsExecutableQuotioCLIHelper() {
        let helper = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/quotio-cli")

        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: helper.path))
    }

    func testLegacyDefaultsMergePreservesCurrentValuesAndNewestLegacyDomain() {
        let merged = AppIdentity.mergingUserDefaults(
            current: ["existing": "current"],
            legacyDomains: [
                ["existing": "legacy", "legacyOnly": "newest"],
                ["legacyOnly": "oldest", "oldestOnly": true],
            ]
        )

        XCTAssertEqual(merged["existing"] as? String, "current")
        XCTAssertEqual(merged["legacyOnly"] as? String, "newest")
        XCTAssertEqual(merged["oldestOnly"] as? Bool, true)
    }
}
