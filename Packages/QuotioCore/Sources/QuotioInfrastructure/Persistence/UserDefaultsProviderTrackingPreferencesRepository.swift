import Foundation
import QuotioApplication
import QuotioDomain

public final class UserDefaultsProviderTrackingPreferencesRepository: ProviderTrackingPreferencesRepository, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ProviderTrackingPreferences {
        if defaults.object(forKey: "providerTrackingV2") != nil {
            let value = defaults.dictionary(forKey: "providerTrackingV2") ?? [:]
            return ProviderTrackingPreferences(disabledProviders: Set(
                (value["disabled"] as? [String] ?? []).compactMap(QuotaProvider.init(rawValue:))
            ), automaticallyDiscoverLogins: value["automatic"] as? Bool ?? true)
        }
        return ProviderTrackingPreferences(disabledProviders: Set(
            (defaults.stringArray(forKey: "disabledProviders") ?? []).map(canonicalLegacyMacProviderID).compactMap(QuotaProvider.init(rawValue:))
        ), automaticallyDiscoverLogins: defaults.object(forKey: "automaticallyDiscoverLogins") as? Bool ?? true)
    }

    public func save(_ preferences: ProviderTrackingPreferences) {
        defaults.set(["automatic": preferences.automaticallyDiscoverLogins,
                      "disabled": preferences.disabledProviders.map(\.rawValue).sorted()], forKey: "providerTrackingV2")
    }
}

// Historical macOS preference IDs only. Runtime host IDs are never translated.
func canonicalLegacyMacProviderID(_ id: String) -> String {
    switch id {
    case "github-copilot": "copilot"
    case "factory-droid": "factory"
    case "vertex": "vertexai"
    case "devin": "devin-desktop"
    case "glm": "zai"
    default: id
    }
}
