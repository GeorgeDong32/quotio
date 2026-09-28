//
//  FallbackScreenModel.swift
//  QuotioForkExtras — screen model for fallback + request-log screens
//

import Foundation
import Observation
import QuotioDomain

/// Backing model for the fork's Fallback and request-log screens.
///
/// Provides the model list used by the add-entry sheet: seeded from the
/// static catalog and refreshed live from the running proxy's
/// `/v1/models` endpoint (through the bridge port, authenticating with the
/// first API key found in the proxy config file — the same source the fork
/// used pre-port).
@MainActor
@Observable
public final class FallbackScreenModel {
    public let settings = FallbackSettingsManager.shared
    public let tracker = RequestTracker.shared

    /// Provider of `http://127.0.0.1:<user port>` (the bridge endpoint).
    private let baseURLProvider: @MainActor () -> String
    /// Path of the proxy config.yaml (for the client API key).
    private let configPathProvider: @MainActor () -> String?

    public private(set) var availableModels: [AvailableModel] = []
    public private(set) var isRefreshingModels = false

    public init(
        baseURLProvider: @escaping @MainActor () -> String,
        configPathProvider: @escaping @MainActor () -> String?
    ) {
        self.baseURLProvider = baseURLProvider
        self.configPathProvider = configPathProvider
        availableModels = AvailableModel.allModels.sorted { $0.displayName < $1.displayName }
    }

    /// Fetch the live model list from the proxy; returns success.
    @discardableResult
    public func refreshAvailableModels() async -> Bool {
        guard !isRefreshingModels else { return false }
        isRefreshingModels = true
        defer { isRefreshingModels = false }

        guard let apiKey = firstConfigAPIKey() else { return false }
        var request = URLRequest(url: URL(string: "\(baseURLProvider())/v1/models")!)
        request.timeoutInterval = 10
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                return false
            }
            var models = Self.parseModels(data)
            // Keep locally-configured virtual models out of the pick list.
            models.removeAll { $0.provider.lowercased() == "fallback" }
            guard !models.isEmpty else { return false }
            availableModels = models.sorted { $0.displayName < $1.displayName }
            return true
        } catch {
            return false
        }
    }

    /// Extracts the first `api-keys` entry from the proxy config file.
    private func firstConfigAPIKey() -> String? {
        guard let path = configPathProvider(),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }
        guard let range = content.range(of: "api-keys:") else { return nil }
        let remainder = content[range.upperBound...]
        for line in remainder.split(separator: "\n", maxSplits: 20).prefix(20) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") {
                let value = trimmed.dropFirst(2).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                if !value.isEmpty { return value }
            }
            if !trimmed.hasPrefix("-"), !trimmed.isEmpty, !line.hasPrefix(" ") {
                break // left the api-keys block
            }
        }
        return nil
    }

    /// Parses an OpenAI-style `/v1/models` payload.
    static func parseModels(_ data: Data) -> [AvailableModel] {
        struct Payload: Decodable {
            struct Item: Decodable {
                let id: String
                let ownedBy: String?

                enum CodingKeys: String, CodingKey {
                    case id
                    case ownedBy = "owned_by"
                }
            }

            let data: [Item]?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let items = payload.data else {
            return []
        }
        return items.map {
            AvailableModel(id: $0.id, name: $0.id, provider: $0.ownedBy ?? "unknown", isDefault: false)
        }
    }
}
