//
//  CompletionStep.swift
//  Quotio - CLIProxyAPI GUI Wrapper
//

import QuotioApplication
import QuotioDomain
import SwiftUI

struct CompletionStep: View {
    let overview: OnboardingProviderOverview
    @Environment(MenuBarSettingsManager.self) private var menuBar

    private var showQuotaBinding: Binding<Bool> {
        Binding(
            get: { menuBar.showMenuBarIcon && menuBar.showQuotaInMenuBar },
            set: { enabled in
                if enabled { menuBar.showMenuBarIcon = true }
                menuBar.showQuotaInMenuBar = enabled
            }
        )
    }

    var body: some View {
        Form {
            Section {
                if overview.found.isEmpty {
                    Text("onboarding.completion.empty".localized())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !overview.readyProviders.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityHidden(true)
                        Text(String.localizedStringWithFormat(
                            "onboarding.completion.readyCount".localized(), overview.readyProviders.count
                        ))
                        Spacer()
                        providerIcons(overview.readyProviders)
                    }
                    .accessibilityElement(children: .combine)
                }
                if !overview.loadingProviders.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(String.localizedStringWithFormat(
                            "onboarding.completion.loadingCount".localized(), overview.loadingProviders.count
                        ))
                        Spacer()
                        providerIcons(overview.loadingProviders)
                    }
                    .accessibilityElement(children: .combine)
                }
                ForEach(overview.attentionProviders) { provider in
                    OnboardingFoundProviderRow(provider: provider, includesQuotaIssues: true)
                }
            } header: {
                Text("onboarding.completion.connected".localized())
            } footer: {
                if !overview.attentionProviders.isEmpty {
                    Text("onboarding.completion.attentionHint".localized())
                }
            }

            Section {
                Toggle("settings.menubar.showQuota".localized(), isOn: showQuotaBinding)
            } footer: {
                Text("onboarding.completion.hint".localized())
            }
        }
        .formStyle(.grouped)
    }

    private func providerIcons(_ providers: [OnboardingProviderOverview.FoundProvider]) -> some View {
        HStack(spacing: 4) {
            ForEach(providers.prefix(6)) { ProviderIcon(provider: $0.id, size: 16) }
            if providers.count > 6 {
                Text("+" + String(providers.count - 6))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
    }
}
