//
//  ManualProviderConfigMode.swift
//  QuotioForkExtras — manual ownership of config.yaml provider sections
//

import Foundation
import QuotioApplication
import QuotioDomain

/// UserDefaults-backed flag deciding who owns the provider/model sections
/// of the proxy `config.yaml` (key `manualProviderConfig`, default off).
///
/// While enabled Quotio keeps managing the proxy process and still writes
/// back the port and management key, but it never rewrites the provider
/// sections (`openai-compatibility`, `claude-api-key`, `gemini-api-key`,
/// `codex-api-key`, `glm-api-key`) — those become hand-maintained and
/// survive every proxy (re)start, including silent health-recovery
/// restarts.
public final class ManualProviderConfigStore: @unchecked Sendable {
    public static let defaultsKey = "manualProviderConfig"
    private let defaults: UserDefaults

    /// - Parameter defaults: injectable for tests; `UserDefaults` is
    ///   thread-safe, hence `@unchecked Sendable` on the class.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Self.defaultsKey) }
        set { defaults.set(newValue, forKey: Self.defaultsKey) }
    }
}

/// `CustomProviderConfigurationSynchronizing` decorator that stops the
/// managed-sections rewrite (remove + regenerate) while manual provider
/// config mode is on. This gates both write paths: the lifecycle
/// `configurationSupplement` invoked before every proxy start and the
/// Providers screen's explicit synchronize. Port / management-key
/// write-backs live in the configuration repository and are unaffected.
public struct ManualModeConfigurationSynchronizer<Base: CustomProviderConfigurationSynchronizing>:
    CustomProviderConfigurationSynchronizing
{
    private let base: Base
    private let store: ManualProviderConfigStore

    public init(base: Base, store: ManualProviderConfigStore = ManualProviderConfigStore()) {
        self.base = base
        self.store = store
    }

    public func synchronize(_ providers: [CustomProvider], at path: String) throws {
        guard !store.isEnabled else { return }
        try base.synchronize(providers, at: path)
    }
}
