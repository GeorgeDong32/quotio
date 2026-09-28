import Foundation
import XCTest
@testable import QuotioApplication
@testable import QuotioDomain
@testable import QuotioPresentation

@MainActor
final class QuotaScreenModelsTests: XCTestCase {
    func testManualAndDevicePromptsUseHostStateWithoutProviderRules() {
        let manual = QuotaOAuthState(.awaitingManualCode(providerID: .init(rawValue: "codex"),
            prompt: .init(authorizationURL: URL(string: "https://auth.example.test")), state: "private-session-id"))
        XCTAssertEqual(manual?.requiresManualCode, true)
        XCTAssertNil(manual?.userCode)
        let device = QuotaOAuthState(.awaitingUser(providerID: .init(rawValue: "claude"),
            prompt: .init(authorizationURL: URL(string: "https://auth.example.test"), userCode: "DISPLAY-CODE")))
        XCTAssertEqual(device?.requiresManualCode, false)
        XCTAssertEqual(device?.userCode, "DISPLAY-CODE")
    }

    func testQuotaScreenModelBootstrapsAndRefreshesThroughCoordinator() async {
        let initial = Self.quota(20)
        let fresh = Self.quota(80)
        let initialSnapshot = QuotaSnapshot(quotas: [
            .codex: ["account": initial],
        ])
        let coordinator = TestQuotaCoordinator(
            snapshot: initialSnapshot,
            refreshedSnapshot: QuotaSnapshot(
                quotas: [.codex: ["account": fresh]],
                lastUpdated: PresentationClock.date
            )
        )
        let model = QuotaScreenModel(coordinator: coordinator)
        var observedStates: [QuotaSnapshot] = []
        model.setDidChangeHandler { observedStates.append($0) }

        await model.bootstrap(mode: .monitor)
        observedStates.removeAll()
        await model.refresh(provider: .codex, mode: .monitor)

        XCTAssertEqual(model.providerQuotas[.codex]?["account"], fresh)
        XCTAssertEqual(model.lastRefreshTime, PresentationClock.date)
        XCTAssertFalse(model.isLoadingQuotas)
        XCTAssertEqual(observedStates.last, model.state)
        await model.shutdown()
    }

    func testDashboardModelDerivesQuotaOverview() async {
        let coordinator = TestQuotaCoordinator(snapshot: QuotaSnapshot(quotas: [
            .codex: ["one": Self.quota(70)],
            .claude: ["two": Self.quota(30)],
        ]))
        let quota = QuotaScreenModel(coordinator: coordinator)
        let accounts = AccountsScreenModel(
            accountService: EmptyAccountManager()
        )
        let dashboard = DashboardScreenModel(quota: quota, accounts: accounts)

        await quota.bootstrap(mode: .monitor)

        XCTAssertEqual(dashboard.lowestQuotaPercentage, 30)
        await quota.shutdown()
    }

    func testDashboardDoesNotReportFullQuotaWithoutAnyReadings() {
        let quota = QuotaScreenModel(coordinator: TestQuotaCoordinator())
        let accounts = AccountsScreenModel(
            accountService: EmptyAccountManager()
        )
        XCTAssertNil(DashboardScreenModel(quota: quota, accounts: accounts).lowestQuotaPercentage)
    }

    func testDashboardModelHidesDisabledAccounts() {
        let quota = QuotaScreenModel(coordinator: TestQuotaCoordinator())
        let accounts = AccountsScreenModel(
            accountService: EmptyAccountManager()
        )
        accounts.replaceAccounts([
            Account.make(
                providerID: AccountProviderID(rawValue: QuotaProvider.codex.rawValue),
                accountKey: "enabled@example.com",
                source: .nativeCredential
            ),
            Account.make(
                providerID: AccountProviderID(rawValue: QuotaProvider.claude.rawValue),
                accountKey: "disabled@example.com",
                source: .nativeCredential,
                status: .disabled
            ),
        ])
        let dashboard = DashboardScreenModel(quota: quota, accounts: accounts)

        XCTAssertEqual(dashboard.trackedAccounts.map(\.accountKey), ["enabled@example.com"])
        XCTAssertEqual(dashboard.trackedAccountCount, 1)
        XCTAssertEqual(dashboard.connectedProviderCount, 1)
    }

    func testShutdownPreventsSuspendedRefreshFromRestartingObservation() async {
        let gate = TestAsyncGate()
        let coordinator = TestQuotaCoordinator(refreshGate: gate)
        let model = QuotaScreenModel(coordinator: coordinator)
        await model.bootstrap(mode: .monitor)

        let refresh = Task {
            await model.refresh(provider: .codex, mode: .monitor, force: true)
        }
        await coordinator.waitUntilRefreshStarts()
        await model.shutdown()
        await gate.resume()
        await refresh.value

        await coordinator.replaceQuotas(
            ["late": Self.quota(90)], for: .codex, mode: .monitor)
        for _ in 0..<10 { await Task.yield() }

        XCTAssertNil(model.providerQuotas[.codex]?["late"])
    }

    private static func quota(_ percentage: Double) -> ProviderQuota {
        ProviderQuota(
            models: [QuotaMetric(name: "usage", percentage: percentage, resetTime: "")],
            lastUpdated: PresentationClock.date
        )
    }
}

private struct PresentationClock: DateProviding {
    static let date = Date(timeIntervalSince1970: 2_000)
    func now() -> Date { Self.date }
}

private actor EmptyAccountManager: AccountManaging {
    func registerDetectedNativeAccounts() {}
    func rescanNativeAccounts(for provider: QuotaProvider) {}
    func nativeDiscoverySnapshot() -> NativeDiscoverySnapshot { .init() }
    func authorizeNativeSource(_ source: NativeSourcePermission) {}
    func accounts() -> [Account] { [] }
    func renameResolvedAccount(id: String, userLabel: String?) async throws {}
    func setSourceEnabled(_ enabled: Bool, sourceID: String) async throws {}
    func unlinkSource(sourceID: String) async throws {}

    func saveAPIKey(
        providerID: AccountProviderID,
        label: String,
        apiKey: String,
        existingAccountID: String?,
        fields: [String: String] = [:]
    ) throws {}
    func setDisabled(_ disabled: Bool, accountID: String) {}
    func delete(accountID: String) throws {}
}
