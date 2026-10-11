import QuotioApplication
import QuotioDomain
import XCTest

@testable import QuotioForkExtras

final class ManualProviderConfigModeTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: ManualProviderConfigStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "manual-provider-config-tests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        store = ManualProviderConfigStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Store

    func testStoreDefaultsToDisabled() {
        XCTAssertFalse(store.isEnabled)
    }

    func testStorePersistsAcrossInstances() {
        store.isEnabled = true
        XCTAssertTrue(ManualProviderConfigStore(defaults: defaults).isEnabled)

        store.isEnabled = false
        XCTAssertFalse(ManualProviderConfigStore(defaults: defaults).isEnabled)
    }

    // MARK: - Synchronizer decorator

    func testSynchronizerForwardsWhenModeDisabled() throws {
        let spy = SpyConfigurationSynchronizer()
        let sut = ManualModeConfigurationSynchronizer(base: spy, store: store)
        let providers = [makeProvider(name: "relay")]

        try sut.synchronize(providers, at: "/tmp/quotio-config.yaml")

        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertEqual(spy.calls.first?.providers, providers)
        XCTAssertEqual(spy.calls.first?.path, "/tmp/quotio-config.yaml")
    }

    func testSynchronizerSkipsWhenModeEnabled() throws {
        let spy = SpyConfigurationSynchronizer()
        store.isEnabled = true
        let sut = ManualModeConfigurationSynchronizer(base: spy, store: store)

        try sut.synchronize([makeProvider(name: "relay")], at: "/tmp/quotio-config.yaml")

        XCTAssertTrue(spy.calls.isEmpty)
    }

    /// Both write paths (lifecycle supplement before every proxy start and
    /// the Providers screen's explicit synchronize) go through
    /// `CustomProviderService.synchronizeConfiguration`; the decorator must
    /// gate that service-level path too.
    func testServiceLevelSynchronizationIsGatedWhileModeEnabled() throws {
        store.isEnabled = true
        let spy = SpyConfigurationSynchronizer()
        let service = CustomProviderService(
            repository: InMemoryProviderRepository(providers: [makeProvider(name: "relay")]),
            discovery: NoopModelDiscovery(),
            connectionTester: NoopConnectionTester(),
            configurationSynchronizer: ManualModeConfigurationSynchronizer(base: spy, store: store)
        )

        try service.synchronizeConfiguration(at: "/tmp/quotio-config.yaml")

        XCTAssertTrue(spy.calls.isEmpty)
    }

    func testServiceLevelSynchronizationForwardsWhenModeDisabled() throws {
        let spy = SpyConfigurationSynchronizer()
        let service = CustomProviderService(
            repository: InMemoryProviderRepository(providers: [makeProvider(name: "relay")]),
            discovery: NoopModelDiscovery(),
            connectionTester: NoopConnectionTester(),
            configurationSynchronizer: ManualModeConfigurationSynchronizer(base: spy, store: store)
        )

        try service.synchronizeConfiguration(at: "/tmp/quotio-config.yaml")

        XCTAssertEqual(spy.calls.count, 1)
    }

    // MARK: - Fixtures

    private func makeProvider(name: String) -> CustomProvider {
        CustomProvider(
            name: name,
            type: .openaiCompatibility,
            baseURL: "https://example.com/v1",
            apiKeys: [CustomAPIKeyEntry(apiKey: "sk-test")],
            models: [ModelMapping(name: "model-a", alias: "alias-a")]
        )
    }
}

// MARK: - Test doubles

private final class SpyConfigurationSynchronizer: CustomProviderConfigurationSynchronizing, @unchecked Sendable {
    struct Call {
        let providers: [CustomProvider]
        let path: String
    }

    private let lock = NSLock()
    private(set) var recordedCalls: [Call] = []

    var calls: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCalls
    }

    func synchronize(_ providers: [CustomProvider], at path: String) throws {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append(Call(providers: providers, path: path))
    }
}

private struct InMemoryProviderRepository: CustomProviderRepository {
    private let providers: [CustomProvider]

    init(providers: [CustomProvider]) {
        self.providers = providers
    }

    func load() throws -> [CustomProvider] { providers }
    func save(_ providers: [CustomProvider]) throws {}
}

private struct NoopModelDiscovery: CustomProviderModelDiscovering {
    func discoverModels(for provider: CustomProvider) async throws -> [DiscoveredModel] { [] }
}

private struct NoopConnectionTester: CustomProviderConnectionTesting {
    func testConnection(to provider: CustomProvider) async throws {}
}
