//
//  FallbackProxyLifecycleCoordinator.swift
//  QuotioForkExtras — bridge-mode proxy lifecycle composition
//

import Foundation
import QuotioApplication
import QuotioDomain

/// Composes the upstream proxy lifecycle controller with the fork's
/// ProxyBridge so that CLI agents talk to the bridge (user port) which
/// forwards to the proxy binary (internal port = user + 10000) and applies
/// virtual-model fallback routing.
///
/// The wrapped controller is constructed with a `BridgePortMetadataRepository`
/// (offset 10000) and a `PlusProxyVersionRepository`; this coordinator then:
/// - rewrites snapshot ports back to the user port so every consumer
///   (endpoint display, agent configuration, management URL) points at the
///   bridge;
/// - starts/stops the bridge around the binary lifecycle;
/// - keeps fork parity for the update surface (bundled plus binary, no
///   auto-upgrades).
public actor FallbackProxyLifecycleCoordinator: ProxyControlling {
    public static let portOffset: UInt16 = 10000

    private let controller: any ProxyControlling
    private let bridge: ProxyBridge
    private let bridgeModeEnabled: Bool
    private var userPort: UInt16

    public init(
        controller: any ProxyControlling,
        bridge: ProxyBridge,
        userPort: UInt16,
        bridgeModeEnabled: Bool = UserDefaults.standard.object(forKey: "useBridgeMode") as? Bool ?? true
    ) {
        self.controller = controller
        self.bridge = bridge
        self.userPort = userPort
        self.bridgeModeEnabled = bridgeModeEnabled
    }

    public var isBridgeModeEnabled: Bool { bridgeModeEnabled }

    public var internalPort: UInt16 {
        guard bridgeModeEnabled, userPort <= UInt16.max - Self.portOffset else { return userPort }
        return userPort + Self.portOffset
    }

    // MARK: - Snapshots

    public func snapshots() async -> AsyncStream<ProxySnapshot> {
        guard bridgeModeEnabled else { return await controller.snapshots() }
        let upstreamStream = await controller.snapshots()
        return AsyncStream { continuation in
            let task = Task {
                for await snapshot in upstreamStream {
                    continuation.yield(Self.userView(of: snapshot, subtracting: Self.portOffset))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func snapshot() async -> ProxySnapshot {
        let snapshot = await controller.snapshot()
        guard bridgeModeEnabled else { return snapshot }
        return Self.userView(of: snapshot, subtracting: Self.portOffset)
    }

    private static func userView(of snapshot: ProxySnapshot, subtracting offset: UInt16) -> ProxySnapshot {
        var updated = snapshot
        if updated.status.port >= offset {
            updated.status.port -= offset
        }
        return updated
    }

    // MARK: - Lifecycle

    public func initialize() async {
        if bridgeModeEnabled {
            // Install the bundled plus binary before the controller looks for it.
            try? PlusBinaryStore().ensureInstalled()
        }
        await controller.initialize()
    }

    public func start() async throws {
        if bridgeModeEnabled {
            await bridge.configure(listenPort: userPort, targetPort: internalPort)
        }
        try await controller.start()
        if bridgeModeEnabled {
            await bridge.start()
        }
    }

    public func stop() async {
        if bridgeModeEnabled { await bridge.stop() }
        await controller.stop()
    }

    public func stopAndWait() async {
        if bridgeModeEnabled { await bridge.stop() }
        await controller.stopAndWait()
    }

    public func restart() async throws {
        if bridgeModeEnabled { await bridge.stop() }
        try await controller.restart()
        if bridgeModeEnabled {
            await bridge.configure(listenPort: userPort, targetPort: internalPort)
            await bridge.start()
        }
    }

    public func shutdown() async {
        if bridgeModeEnabled { await bridge.stop() }
        await controller.shutdown()
    }

    // MARK: - Update surface (fork parity: fixed bundled binary)

    public func installLatest() async throws {
        // The plus binary ships inside the app bundle and never auto-updates.
        try PlusBinaryStore().ensureInstalled()
    }

    public func checkForUpgrade() async {}

    public func availableVersions(limit: Int) async throws -> [ProxyVersionInfo] { [] }

    public func install(_ version: ProxyVersionInfo) async throws {
        throw PlusBinaryError.installationFailed("The bundled plus binary cannot be replaced")
    }

    public func activate(version: String) async throws {
        try await controller.activate(version: version)
    }

    public func delete(version: String) async throws {
        // Invariant: never delete the current proxy version.
        try await controller.delete(version: version)
    }

    public func rollback() async throws {
        try await controller.rollback()
    }

    public func versionsToDeleteAfterInstalling(keeping count: Int) async -> [String] { [] }

    // MARK: - Configuration

    public func setPort(_ port: UInt16) async {
        if bridgeModeEnabled {
            await bridge.stop()
            userPort = port
        }
        await controller.setPort(internalPort(for: port))
        if bridgeModeEnabled {
            await bridge.configure(listenPort: userPort, targetPort: internalPort)
            await bridge.start()
        }
    }

    public func setNetworkAccess(_ enabled: Bool) async {
        await controller.setNetworkAccess(enabled)
    }

    public func setRemoteAccess(_ enabled: Bool) async {
        await controller.setRemoteAccess(enabled)
    }

    public func setLogging(_ enabled: Bool) async {
        await controller.setLogging(enabled)
    }

    public func setRoutingStrategy(_ strategy: String) async {
        await controller.setRoutingStrategy(strategy)
    }

    public func setProxyURL(_ url: String?) async {
        await controller.setProxyURL(url)
    }

    public func regenerateManagementKey() async throws {
        try await controller.regenerateManagementKey()
    }

    private func internalPort(for userPort: UInt16) -> UInt16 {
        guard bridgeModeEnabled, userPort <= UInt16.max - Self.portOffset else { return userPort }
        return userPort + Self.portOffset
    }
}
