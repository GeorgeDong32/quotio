//
//  ForkProviderIcon.swift
//  QuotioForkExtras — provider icon for fork screens
//

import SwiftUI

/// SF-Symbol-based provider icon for fallback UI (fork-local AIProvider).
public struct ProviderIcon: View {
    let provider: AIProvider
    let size: CGFloat

    public init(provider: AIProvider, size: CGFloat = 16) {
        self.provider = provider
        self.size = size
    }

    public var body: some View {
        Image(systemName: provider.iconName)
            .font(.system(size: size * 0.8))
            .foregroundStyle(color)
            .frame(width: size, height: size)
    }

    private var color: Color {
        switch provider {
        case .gemini: return .blue
        case .claude: return .orange
        case .codex: return .green
        case .qwen: return .purple
        case .iflow: return .cyan
        case .antigravity: return .indigo
        case .vertex: return .blue
        case .kiro: return .teal
        case .copilot: return .gray
        case .cursor: return .blue
        case .factoryDroid: return .red
        case .devin: return .blue
        case .grok: return .black
        case .openRouter: return .indigo
        case .amp: return .yellow
        case .trae: return .blue
        case .glm: return .blue
        case .warp: return .primary
        case .clinePass: return .orange
        }
    }
}
