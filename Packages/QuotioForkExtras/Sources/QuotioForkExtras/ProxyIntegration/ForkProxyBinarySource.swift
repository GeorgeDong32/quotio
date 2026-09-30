//
//  ForkProxyBinarySource.swift
//  QuotioForkExtras — which proxy binary the app runs
//

import Foundation
import QuotioApplication
import QuotioDomain

/// Which CLIProxyAPI binary the fork runs.
///
/// Restores the pre-port binary-source selection, including its
/// UserDefaults key (`selectedProxyBinarySource`) so upgraded installs
/// keep the user's explicit choice. Fallback routing is app-side
/// (ProxyBridge model rewriting) and works with either binary.
public enum ForkProxyBinarySource: String, CaseIterable, Identifiable, Sendable {
    /// The official CLIProxyAPI from GitHub releases, installed and
    /// auto-updated by the upstream lifecycle machinery.
    case upstream
    /// The fork's bundled, sha-pinned plus build (fixed local version).
    case plusLocal

    public var id: String { rawValue }

    static let userDefaultsKey = "selectedProxyBinarySource"

    /// Stored preference; defaults to the official binary, matching what
    /// the pre-port fork's user base actually selected.
    public static func stored(defaults: UserDefaults = .standard) -> ForkProxyBinarySource {
        guard let raw = defaults.string(forKey: userDefaultsKey),
              let source = ForkProxyBinarySource(rawValue: raw) else {
            return .upstream
        }
        return source
    }

    public static func set(_ source: ForkProxyBinarySource, defaults: UserDefaults = .standard) {
        defaults.set(source.rawValue, forKey: userDefaultsKey)
    }
}

/// Version repository that forwards to the plus or upstream repository
/// according to the stored source, so the upstream lifecycle controller
/// manages whichever binary the user selected.
public final class ForkProxyVersionRepository: ProxyVersionRepository, @unchecked Sendable {
    private let plus: PlusProxyVersionRepository
    private let upstream: any ProxyVersionRepository

    public init(upstreamRepository: any ProxyVersionRepository) {
        self.plus = PlusProxyVersionRepository()
        self.upstream = upstreamRepository
    }

    private var active: any ProxyVersionRepository {
        ForkProxyBinarySource.stored() == .plusLocal ? plus : upstream
    }

    public func snapshot() async -> ProxyVersionSnapshot {
        await active.snapshot()
    }

    public func binaryPath(for version: String) async -> String? {
        await active.binaryPath(for: version)
    }

    public func install(version: String, data: Data, assetName: String) async throws -> InstalledProxyVersion {
        try await active.install(version: version, data: data, assetName: assetName)
    }

    public func activate(version: String) async throws {
        try await active.activate(version: version)
    }

    public func delete(version: String) async throws {
        try await active.delete(version: version)
    }

    public func cleanup(keeping count: Int) async {
        await active.cleanup(keeping: count)
    }

    public func versionsToDeleteAfterInstalling(keeping count: Int) async -> [String] {
        await active.versionsToDeleteAfterInstalling(keeping: count)
    }
}
