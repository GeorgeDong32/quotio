import QuotioApplication
import QuotioDomain
import SwiftUI

struct MonitorOverviewScreen: View {
    @Environment(DashboardScreenModel.self) private var dashboard
    @Environment(QuotaFeatureController.self) private var quotaController
    @Environment(NavigationScreenModel.self) private var navigation

    private var attentionProviders: [QuotaProvider] {
        let failed = dashboard.trackedAccounts.filter {
            let status = quotaController.monitorStatus(for: $0).status
            return status == "failed" || status == "partial" || status == "outdated"
        }.map(\.provider)
        return Set(failed).union(dashboard.accounts.nativeSourcePermissions.map(\.provider))
            .sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("connections.overviewHint".localized()).foregroundStyle(.secondary)
            GroupBox {
                VStack(spacing: 12) {
                    LabeledContent("connections.configured".localized(), value: String(dashboard.connectedProviderCount))
                    Divider()
                    LabeledContent("dashboard.lowestQuota".localized()) {
                        if let percent = dashboard.lowestQuotaPercentage {
                            Text(String(format: "%.0f%%", percent))
                        } else {
                            Text("empty.noQuotaData".localized()).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    LabeledContent("dashboard.lastRefresh".localized()) {
                        if let date = dashboard.lastRefreshTime {
                            Text(date, style: .relative)
                        } else {
                            Text("status.notRefreshed".localized())
                        }
                    }
                }
                .padding(8)
            }

            if !attentionProviders.isEmpty {
                GroupBox {
                    VStack(spacing: 0) {
                        ForEach(attentionProviders) { provider in
                            Button { navigation.selectProvider(provider) } label: {
                                HStack(spacing: 12) {
                                    ProviderIcon(provider: provider, size: 22)
                                    Text(provider.displayName)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                } label: {
                    Label("connections.attention".localized(), systemImage: "exclamationmark.triangle")
                }
            }

            HStack {
                Button("connections.all".localized()) { navigation.showProviders() }
                Button("connections.usage".localized()) { navigation.currentPage = .quota }
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
