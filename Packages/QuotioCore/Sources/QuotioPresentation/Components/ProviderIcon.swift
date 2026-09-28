//
//  ProviderIcon.swift
//  Quotio
//

import AppKit
import QuotioApplication
import QuotioDomain
import SwiftUI

struct ProviderIcon: View {
    let provider: QuotaProvider
    var size: CGFloat = 24
    
    @Environment(ProviderImageScreenModel.self) private var imageModel
    
    var body: some View {
        Group {
            if let nsImage = imageModel.image(named: provider.logoAssetName, size: size) {
                Image(nsImage: nsImage)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.primary)
            } else {
                // Fallback to SF Symbol if image not found
                Image(systemName: provider.iconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Symbol Effect Transition Modifier (macOS 15+ compatibility)

/// A ViewModifier that applies `.contentTransition(.symbolEffect(.replace))` on macOS 15+
/// and gracefully degrades on earlier versions.
struct SymbolEffectTransitionModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.contentTransition(.symbolEffect(.replace))
        } else {
            content
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ForEach(QuotaProvider.allCases) { provider in
            HStack {
                ProviderIcon(provider: provider, size: 32)
                Text(provider.displayName)
            }
        }
    }
    .padding()
}
