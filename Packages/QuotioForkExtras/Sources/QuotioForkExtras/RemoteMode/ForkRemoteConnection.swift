//
//  ForkRemoteConnection.swift
//  QuotioForkExtras — remote CLIProxyAPI connection management
//

import Foundation
import Observation
import QuotioApplication
import QuotioDomain
import Security

/// Saved configuration for connecting to a remote CLIProxyAPI instance.
/// Codable shape is fork-compatible with the pre-port storage
/// (UserDefaults key `remoteConnectionConfig`) so existing fork users'
/// saved connections decode unchanged.
public struct RemoteConnectionConfig: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var endpointURL: String
    public var displayName: String
    public var verifySSL: Bool
    public var timeoutSeconds: Int
    public var lastConnected: Date?

    public init(
        id: UUID = UUID(),
        endpointURL: String,
        displayName: String = "",
        verifySSL: Bool = true,
        timeoutSeconds: Int = 30,
        lastConnected: Date? = nil
    ) {
        self.id = id
        self.endpointURL = endpointURL
        self.displayName = displayName
        self.verifySSL = verifySSL
        self.timeoutSeconds = timeoutSeconds
        self.lastConnected = lastConnected
    }

    /// Normalizes any input URL to the management API base
    /// (`…/v0/management`), mirroring the fork's original behavior.
    public var managementBaseURL: String {
        var url = endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.hasSuffix("/") { url.removeLast() }
        if url.hasSuffix("/v0/management") { return url }
        if url.hasSuffix("/v0") { return url + "/management" }
        return url + "/v0/management"
    }

    public var hostLabel: String {
        URL(string: endpointURL)?.host ?? endpointURL
    }
}

/// Sanitizes and validates remote endpoint input (fork parity).
public enum RemoteURLValidator {
    public static func sanitize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return "" }
        if !value.hasPrefix("http://") && !value.hasPrefix("https://") {
            value = "http://" + value
        }
        return value
    }

    /// Returns a normalized URL string when the input plausibly addresses a
    /// remote management endpoint.
    public static func validated(_ raw: String) -> String? {
        let sanitized = sanitize(raw)
        guard let url = URL(string: sanitized),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty,
              host != "127.0.0.1", host != "localhost", host != "::1"
        else { return nil }
        return sanitized
    }
}

/// Manages the saved remote connection + its management key.
@MainActor
@Observable
public final class ForkRemoteConnectionManager {
    private static let configKey = "remoteConnectionConfig"

    public private(set) var config: RemoteConnectionConfig?
    public private(set) var lastTestSucceeded: Bool?
    public private(set) var isTesting = false

    public init() {
        loadConfig()
    }

    public func save(_ config: RemoteConnectionConfig, managementKey: String) {
        let data = try? JSONEncoder().encode(config)
        if let data {
            UserDefaults.standard.set(data, forKey: Self.configKey)
        }
        self.config = config
        Keychain.remoteManagementKeyStore.save(configID: config.id, key: managementKey)
    }

    public func clear() {
        if let config {
            Keychain.remoteManagementKeyStore.delete(configID: config.id)
        }
        UserDefaults.standard.removeObject(forKey: Self.configKey)
        config = nil
        lastTestSucceeded = nil
    }

    public func managementKey() -> String? {
        guard let config else { return nil }
        return Keychain.remoteManagementKeyStore.load(configID: config.id)
    }

    /// Tests connectivity against the saved/pending endpoint using the
    /// upstream management client. Returns success.
    @discardableResult
    public func testConnection(endpoint: String, managementKey: String) async -> Bool {
        guard let validated = RemoteURLValidator.validated(endpoint) else {
            lastTestSucceeded = false
            return false
        }
        isTesting = true
        defer { isTesting = false }

        let normalized = RemoteConnectionConfig(endpointURL: validated).managementBaseURL
        let connection = ProxyManagementConnection(baseURL: normalized, authKey: managementKey)
        let api = RemoteManagementProbe(connection: connection)
        let result = await api.isReachable()
        lastTestSucceeded = result
        return result
    }

    /// Marks the current config as connected (fork parity bookkeeping).
    public func markConnected() {
        guard var config else { return }
        config.lastConnected = Date()
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.configKey)
        }
        self.config = config
    }

    public func loadConfig() {
        guard let data = UserDefaults.standard.data(forKey: Self.configKey),
              let decoded = try? JSONDecoder().decode(RemoteConnectionConfig.self, from: data) else {
            config = nil
            return
        }
        config = decoded
    }
}

/// Minimal reachability probe for a remote management endpoint.
/// NOTE: the port drops the fork's `verifySSL=false` self-signed support —
/// remote HTTPS now requires a system-trusted certificate (documented in
/// the port tasks; the saved flag is preserved for data compatibility).
struct RemoteManagementProbe: Sendable {
    let connection: ProxyManagementConnection

    func isReachable() async -> Bool {
        guard let url = URL(string: "\(connection.baseURL)/usage") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.addValue("Bearer \(connection.authKey)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode != 401 && http.statusCode != 404
        } catch {
            return false
        }
    }
}

/// Keychain storage for remote management keys, keyed by connection id under
/// `<bundle id>.remote-management` (same service name the fork used, so
/// existing entries keep working under the unchanged bundle id).
enum Keychain {
    static let remoteManagementService = (Bundle.main.bundleIdentifier ?? "dev.quotio.desktop")
        + ".remote-management"

    enum remoteManagementKeyStore {
        private static func account(for id: UUID) -> String { "management-key-\(id.uuidString)" }

        static func save(configID: UUID, key: String) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: remoteManagementService,
                kSecAttrAccount as String: account(for: configID),
            ]
            let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8)]
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard status == errSecItemNotFound else { return }
            var add = query
            add[kSecValueData as String] = Data(key.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }

        static func load(configID: UUID) -> String? {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: remoteManagementService,
                kSecAttrAccount as String: account(for: configID),
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data,
                  let key = String(data: data, encoding: .utf8) else {
                return nil
            }
            return key
        }

        static func delete(configID: UUID) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: remoteManagementService,
                kSecAttrAccount as String: account(for: configID),
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}
