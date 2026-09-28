//
//  FallbackProvider.swift
//  QuotioForkExtras — Fork-local provider identity for fallback chains
//

import Foundation

/// Provider identity used by fallback entries and request logs.
///
/// This is a fork-local clone of the fork's historical `AIProvider` enum.
/// Raw values MUST stay stable: existing users' `fallbackConfiguration`
/// and `request-history.json` persist these values (see the upgrade-path
/// task in the port plan). The upstream provider catalog is host-driven
/// (string IDs) and intentionally not used here.
public enum AIProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case gemini = "gemini-cli"
    case claude = "claude"
    case codex = "codex"
    case qwen = "qwen"
    case iflow = "iflow"
    case antigravity = "antigravity"
    case vertex = "vertex"
    case kiro = "kiro"
    case copilot = "github-copilot"
    case cursor = "cursor"
    case factoryDroid = "factory-droid"
    case devin = "devin"
    case grok = "grok"
    case openRouter = "openrouter"
    case amp = "amp"
    case trae = "trae"
    case glm = "glm"
    case warp = "warp"
    case clinePass = "clinepass"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gemini: return "Gemini CLI"
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .qwen: return "Qwen Code"
        case .iflow: return "iFlow"
        case .antigravity: return "Antigravity"
        case .vertex: return "Vertex AI"
        case .kiro: return "Kiro"
        case .copilot: return "GitHub Copilot"
        case .cursor: return "Cursor"
        case .factoryDroid: return "Factory Droid"
        case .devin: return "Devin"
        case .grok: return "Grok"
        case .openRouter: return "OpenRouter"
        case .amp: return "Amp"
        case .trae: return "Trae"
        case .glm: return "Z.ai"
        case .warp: return "Warp"
        case .clinePass: return "ClinePass"
        }
    }

    public var iconName: String {
        switch self {
        case .gemini: return "sparkles"
        case .claude: return "brain.head.profile"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .qwen: return "cloud"
        case .iflow: return "arrow.triangle.branch"
        case .antigravity: return "wand.and.stars"
        case .vertex: return "cube"
        case .kiro: return "cloud.fill"
        case .copilot: return "chevron.left.forwardslash.chevron.right"
        case .cursor: return "cursorarrow.rays"
        case .factoryDroid: return "cpu"
        case .devin: return "bolt.horizontal.circle"
        case .grok: return "xmark.circle"
        case .openRouter: return "point.3.connected.trianglepath.dotted"
        case .amp: return "bolt.fill"
        case .trae: return "cursorarrow.rays"
        case .glm: return "brain"
        case .warp: return "terminal.fill"
        case .clinePass: return "cpu"
        }
    }

    /// Logo file name in the ProviderIcons asset catalog.
    public var logoAssetName: String {
        switch self {
        case .gemini: return "gemini"
        case .claude: return "claude"
        case .codex: return "openai"
        case .qwen: return "qwen"
        case .iflow: return "iflow"
        case .antigravity: return "antigravity"
        case .vertex: return "vertex"
        case .kiro: return "kiro"
        case .copilot: return "copilot"
        case .cursor: return "cursor"
        case .factoryDroid: return "factory-droid"
        case .devin: return "devin"
        case .grok: return "grok"
        case .openRouter: return "openrouter"
        case .amp: return "amp"
        case .trae: return "trae"
        case .glm: return "glm"
        case .warp: return "warp"
        case .clinePass: return "clinepass"
        }
    }
}
