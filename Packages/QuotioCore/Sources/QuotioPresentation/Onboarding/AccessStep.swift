//
//  AccessStep.swift
//  Quotio - CLIProxyAPI GUI Wrapper
//

import QuotioApplication
import QuotioDomain
import SwiftUI

struct AccessStep: View {
    let overview: OnboardingProviderOverview
    @Environment(AccountsScreenModel.self) private var accounts
    @State private var permission: NativeSourcePermission?

    var body: some View {
        Form {
            AccountStorageAccessSection()

            if !overview.pendingPermissions.isEmpty {
                Section {
                    ForEach(overview.pendingPermissions) { source in
                        HStack(alignment: .top, spacing: 10) {
                            ProviderIcon(provider: source.provider, size: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(overview.name(for: source.provider))
                                Text(source.explanationLocalizationKey.localized())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            if accounts.authorizingNativeSourceID == source.id {
                                ProgressView().controlSize(.small)
                            }
                            Button("settings.authorize".localized()) { permission = source }
                                .disabled(!overview.canAuthorize(source) || accounts.authorizingNativeSourceID != nil)
                                .accessibilityLabel("settings.authorize".localized() + " " + overview.name(for: source.provider))
                        }
                    }
                } header: {
                    Text("onboarding.access.pending".localized())
                }
            }

            if !overview.needsAccess {
                Section {
                    Label {
                        Text("onboarding.access.done".localized())
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
            }

            Section {
                Label {
                    Text("onboarding.access.hint".localized())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $permission) { source in
            NativePermissionSheet(source: source)
        }
    }
}
