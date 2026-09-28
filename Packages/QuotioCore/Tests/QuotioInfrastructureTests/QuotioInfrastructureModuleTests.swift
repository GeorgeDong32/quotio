import XCTest
@testable import QuotioDomain
@testable import QuotioInfrastructure

final class QuotioInfrastructureModuleTests: XCTestCase {
    func testModuleDependsOnApplicationAndDomain() {
        XCTAssertEqual(
            QuotioInfrastructureModule.dependencyNames,
            ["QuotioApplication", "QuotioDomain"]
        )
    }

    func testBundleTelemetryRuntimeContextProviderReportsBundleFacts() {
        let provider = BundleTelemetryRuntimeContextProvider(
            bundle: .main,
            operatingSystemVersion: { "Version 26.0" }
        )

        let context = provider.context(updateChannel: .stable)

        XCTAssertEqual(context?.macOSVersion, "Version 26.0")
        XCTAssertEqual(context?.updateChannel, .stable)
        XCTAssertEqual(context?.bundleIdentifier, Bundle.main.bundleIdentifier ?? "unknown.bundle")
    }
}
