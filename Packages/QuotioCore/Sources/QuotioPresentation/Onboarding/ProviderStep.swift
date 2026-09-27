//
//  ProviderStep.swift
//  Quotio - CLIProxyAPI GUI Wrapper
//

import QuotioApplication
import QuotioDomain
import SwiftUI

struct ProviderStep: View {
    let overview: OnboardingProviderOverview
    @Environment(AccountsScreenModel.self) private var accounts
    @Environment(QuotaFeatureController.self) private var controller
    @State private var oauthProvider: QuotaProvider?
    @State private var apiKeyProvider: OnboardingProviderOverview.ConnectableProvider?

    private var isScanning: Bool { accounts.isScanningAll || accounts.discoveringProvider != nil }

    var body: some View {
        Form {
            Section {
                if overview.found.isEmpty {
                    Text("onboarding.providers.noneFound".localized())
                        .foregroundStyle(.secondary)
                }
                ForEach(overview.found) { provider in
                    OnboardingFoundProviderRow(provider: provider)
                }
            } header: {
                HStack(spacing: 8) {
                    Text("onboarding.providers.found".localized())
                    Spacer()
                    if isScanning {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("onboarding.providers.scanning".localized())
                    }
                    Button("settings.rescan".localized()) {
                        Task {
                            await accounts.scanAllNativeAccounts()
                            await controller.refreshAll(force: true)
                        }
                    }
                    .controlSize(.small)
                    .disabled(!controller.canDiscoverNative || isScanning)
                }
            } footer: {
                if !accounts.failedDiscoveryProviders.isEmpty {
                    Text("settings.discoveryFailed".localized())
                        .foregroundStyle(.orange)
                }
            }

            if !overview.connectable.isEmpty {
                Section {
                    ForEach(overview.connectable) { provider in
                        HStack(spacing: 10) {
                            ProviderIcon(provider: provider.provider, size: 20)
                            Text(provider.name)
                            Spacer()
                            connectControl(for: provider)
                        }
                    }
                } header: {
                    Text("onboarding.providers.signIn".localized())
                } footer: {
                    Text("onboarding.providers.signInFooter".localized())
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $oauthProvider) { provider in
            OAuthSheet(provider: provider) { oauthProvider = nil }
        }
        .sheet(item: $apiKeyProvider) { provider in
            MonitorAPIKeyConnectionSheet(
                provider: provider.provider,
                account: nil,
                inputs: provider.inputs,
                providerName: provider.name
            ) { label, key, fields in
                try await controller.saveAPIKey(provider: provider.provider, label: label, apiKey: key, fields: fields)
            }
        }
    }

    @ViewBuilder
    private func connectControl(for provider: OnboardingProviderOverview.ConnectableProvider) -> some View {
        if provider.supportsBrowserSignIn && provider.supportsAPIKey {
            Menu("action.connect".localized()) {
                Button("action.login".localized()) { oauthProvider = provider.provider }
                Button("settings.addAPIKey".localized()) { apiKeyProvider = provider }
            }
            .fixedSize()
            .accessibilityLabel("action.connect".localized() + ": " + provider.name)
        } else if provider.supportsBrowserSignIn {
            Button("action.login".localized()) { oauthProvider = provider.provider }
                .accessibilityLabel("action.login".localized() + " " + provider.name)
        } else {
            Button("settings.addAPIKey".localized()) { apiKeyProvider = provider }
                .accessibilityLabel("settings.addAPIKey".localized() + " " + provider.name)
        }
    }
}

struct OnboardingFoundProviderRow: View {
    let provider: OnboardingProviderOverview.FoundProvider
    var includesQuotaIssues = false

    private var issue: OnboardingProviderOverview.FoundProvider.Issue? {
        includesQuotaIssues ? provider.issue : provider.connectionIssue
    }

    var body: some View {
        HStack(spacing: 10) {
            ProviderIcon(provider: provider.id, size: 20)
            Text(provider.name)
            Spacer()
            if let issue {
                Label(issue.title, systemImage: issue.symbol)
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else {
                Text(String.localizedStringWithFormat("onboarding.accountCount".localized(), provider.accountCount))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension OnboardingProviderOverview.FoundProvider.Issue {
    @MainActor var title: String {
        switch self {
        case .permissionRequired: ConnectionState.permissionRequired.title
        case .signInRequired: ConnectionState.reauthenticationRequired.title
        case .quotaFailed: QuotaRefreshState.failed(nil).title
        }
    }

    var symbol: String {
        switch self {
        case .permissionRequired: "lock"
        case .signInRequired, .quotaFailed: "exclamationmark.triangle"
        }
    }
}
