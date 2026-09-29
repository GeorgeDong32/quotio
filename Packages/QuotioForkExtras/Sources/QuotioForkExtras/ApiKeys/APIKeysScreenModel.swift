//
//  APIKeysScreenModel.swift
//  QuotioForkExtras — proxy client API key management
//

import Foundation
import Observation
import QuotioApplication

/// Backing model for the fork's API Keys page: manages the proxy's
/// client-auth keys (`api-keys` in config.yaml) through the management API.
/// The page existed in the pre-port fork; upstream retired it.
@MainActor
@Observable
public final class APIKeysScreenModel {
    public private(set) var keys: [String] = []
    public private(set) var isLoading = false
    public private(set) var lastError: String?

    private let apiClientProvider: @MainActor () -> (any ProxyManagementAPI)?

    public init(apiClientProvider: @escaping @MainActor () -> (any ProxyManagementAPI)?) {
        self.apiClientProvider = apiClientProvider
    }

    public func refresh() async {
        guard let apiClient = apiClientProvider() else {
            lastError = "apiKeys.proxyNotRunning".localized()
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            keys = try await apiClient.fetchAPIKeys()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func add(key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !keys.contains(trimmed) else { return }
        guard let apiClient = apiClientProvider() else { return }
        do {
            try await apiClient.addAPIKey(trimmed)
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func addGeneratedKey() async {
        await add(key: Self.generateKey())
    }

    public func delete(key: String) async {
        guard let apiClient = apiClientProvider() else { return }
        do {
            try await apiClient.deleteAPIKey(value: key)
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// `quotio-`-prefixed random key, same shape the app itself generates.
    static func generateKey() -> String {
        let bytes = (0..<24).map { _ in UInt8.random(in: 0...255) }
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return "quotio-\(hex)"
    }
}
