//
//  WelcomeStep.swift
//  Quotio - CLIProxyAPI GUI Wrapper
//

import AppKit
import SwiftUI

struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            VStack(spacing: 12) {
                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                }

                VStack(spacing: 6) {
                    Text("onboarding.welcome.title".localized())
                        .font(.title.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("onboarding.welcome.subtitle".localized())
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 380)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                OnboardingFeatureRow(
                    symbol: "person.crop.circle.badge.plus",
                    titleKey: "onboarding.welcome.connect.title",
                    detailKey: "onboarding.welcome.connect.detail"
                )
                OnboardingFeatureRow(
                    symbol: "lock.shield",
                    titleKey: "onboarding.welcome.access.title",
                    detailKey: "onboarding.welcome.access.detail"
                )
                OnboardingFeatureRow(
                    symbol: "menubar.rectangle",
                    titleKey: "onboarding.welcome.quota.title",
                    detailKey: "onboarding.welcome.quota.detail"
                )
            }
            .frame(maxWidth: 400, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 16)
    }
}

private struct OnboardingFeatureRow: View {
    let symbol: String
    let titleKey: String
    let detailKey: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey.localized())
                    .font(.headline)
                Text(detailKey.localized())
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
