import XCTest
import QuotioDomain
@testable import QuotioApplication

final class AccountMonitoringStateTests: XCTestCase {
    func testProviderRowsUseHostFreshnessWithoutRecomputingAge() {
        let account = Account.make(providerID: .init(rawValue: "claude"), accountKey: "logical", source: .nativeCredential)
        for freshness in [QuotaRefreshState.fresh, .stale] {
            var quota = QuotaSnapshot(quotas: [.claude: [account.accountKey: ProviderQuota(lastUpdated: .distantPast)]])
            quota.accountStates[.init(provider: .claude, accountKey: account.accountKey)] = .init(connection: .connected, quota: freshness)
            let state = ProviderSettingsState(provider: .claude, accounts: [account], permissions: [], quota: quota, tracking: .init())
            XCTAssertEqual(state.accountStates[account.id]?.quota, freshness)
            XCTAssertEqual(state.connection, .connected)
        }
    }

    func testMissingHostStateDoesNotInventConnectionAndPermissionStateIsPreserved() {
        let account = Account.make(providerID: .init(rawValue: "claude"), accountKey: "logical", source: .nativeCredential)
        var quota = QuotaSnapshot()
        let missing = ProviderSettingsState(provider: .claude, accounts: [account], permissions: [], quota: quota, tracking: .init())
        XCTAssertEqual(missing.accountStates[account.id]?.quota, .notLoaded)
        XCTAssertEqual(missing.connection, .notConnected)
        quota.accountStates[.init(provider: .claude, accountKey: account.accountKey)] = .init(connection: .permissionRequired, quota: .notLoaded)
        let blocked = ProviderSettingsState(provider: .claude, accounts: [account], permissions: [], quota: quota, tracking: .init())
        XCTAssertEqual(blocked.connection, .permissionRequired)
        XCTAssertTrue(blocked.needsAttention)
    }
}
