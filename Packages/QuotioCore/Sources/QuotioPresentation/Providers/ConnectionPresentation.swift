import QuotioApplication
import QuotioDomain
import SwiftUI

extension AccountRowData {
    @MainActor var sourceLabel: String {
        if let sourceKind {
            switch sourceKind {
            case "amp_native": return "connections.source.amp".localized()
            case "claude_native": return "connections.source.claude".localized()
            case "kiro_native": return "connections.source.kiro".localized()
            case "codex_native": return "connections.source.codex".localized()
            case "cursor_native", "devin_desktop_native", "grok_native":
                return "monitor.source.localIDE".localized()
            case "factory_native": return "connections.source.factory".localized()
            case "antigravity_native": return "connections.source.antigravity".localized()
            case "quotio_custom_provider": return "connections.source.custom".localized()
            case "cli_proxy_auth_file": return "monitor.source.cliProxyFile".localized()
            default: break
            }
        }
        return source.displayName
    }
}

extension QuotaRefreshIssue {
    @MainActor var explanation: String {
        let key: String
        switch reason {
        case .authentication: key = "connections.failure.authentication"
        case .ownerRefreshRequired: key = "connections.failure.owner"
        case .sourceDisabled: key = "connections.failure.disabled"
        case .timeout, .transient: key = "connections.failure.network"
        case .rateLimited: key = "connections.failure.rateLimited"
        case .credentialStorage, .localCredentialStorage: key = "connections.failure.storage"
        case .unavailable: key = "connections.failure.unavailable"
        case .quotaUnavailable: key = "connections.failure.quota"
        case .invalidData: key = "connections.failure.invalidData"
        case nil: key = "connections.failure.unknown"
        }
        return key.localized()
    }
}

enum ProviderConnectionState {
    case available, configured, permissionRequired, disabled, attention

    static func resolve(
        hasAccounts: Bool, hasEnabledAccounts: Bool, needsPermission: Bool, hasIssue: Bool
    ) -> Self {
        if hasAccounts && !hasEnabledAccounts { return .disabled }
        if needsPermission { return .permissionRequired }
        if hasAccounts { return hasIssue ? .attention : .configured }
        return .available
    }

    var localizationKey: String {
        switch self {
        case .available: "connections.available"
        case .configured: "connections.configured"
        case .permissionRequired: "providers.nativePermission.title"
        case .disabled: "connections.disabled"
        case .attention: "connections.attention"
        }
    }

    var symbol: String {
        switch self {
        case .available: "plus.circle"
        case .configured: "checkmark.circle"
        case .permissionRequired: "lock"
        case .disabled: "pause.circle"
        case .attention: "exclamationmark.triangle"
        }
    }

    var color: Color {
        switch self {
        case .available, .disabled: .secondary
        case .configured: .green
        case .permissionRequired, .attention: .orange
        }
    }
}

extension QuotaProvider {
    var hasDiscoverableNativeLogin: Bool {
        switch self {
        case .amp, .antigravity, .claude, .codex, .copilot, .cursor, .devin, .factoryDroid, .grok, .kiro: true
        default: false
        }
    }
}
