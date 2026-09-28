//
//  BridgePortMetadataRepository.swift
//  QuotioForkExtras — port-pair shifting for bridge mode
//

import Foundation
import QuotioApplication

/// Shifts the stored user-facing port by a fixed offset for the wrapped
/// proxy lifecycle controller, so the proxy binary binds the internal port
/// (`userPort + 10000`) while ProxyBridge listens on the user port.
///
/// The on-disk value stays the user port: loads add the offset, saves
/// subtract it. Consumers reading the raw repository (e.g. the initial
/// screen-model state) keep seeing the user port.
public final class BridgePortMetadataRepository: ProxyRuntimeMetadataRepository, @unchecked Sendable {
    private let wrapped: any ProxyRuntimeMetadataRepository
    private let offset: UInt16

    public init(wrapping wrapped: any ProxyRuntimeMetadataRepository, offset: UInt16) {
        self.wrapped = wrapped
        self.offset = offset
    }

    public func loadPort() -> UInt16 {
        let port = wrapped.loadPort()
        guard port <= UInt16.max - offset else { return port }
        return port + offset
    }

    public func savePort(_ port: UInt16) {
        guard port >= offset else {
            wrapped.savePort(port)
            return
        }
        wrapped.savePort(port - offset)
    }

    public func loadLegacyInstalledVersion() -> String? { wrapped.loadLegacyInstalledVersion() }
    public func saveLegacyInstalledVersion(_ version: String) { wrapped.saveLegacyInstalledVersion(version) }
    public func loadLastUpdateCheckDate() -> Date? { wrapped.loadLastUpdateCheckDate() }
    public func saveLastUpdateCheckDate(_ date: Date) { wrapped.saveLastUpdateCheckDate(date) }
}
