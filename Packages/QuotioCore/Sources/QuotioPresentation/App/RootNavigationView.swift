import QuotioApplication
import QuotioDomain
import SwiftUI

public struct RootNavigationView: View {
    public init() {}

    @Environment(NavigationScreenModel.self) private var navigation
    @Environment(AccountsScreenModel.self) private var accounts
    @Environment(QuotaScreenModel.self) private var quota
    @Environment(QuotaFeatureController.self) private var controller
    @State private var search = ""
    @State private var showUnconnected = false
    @State private var showDisabled = false

    private enum Selection: Hashable {
        case page(NavigationPage)
        case provider(QuotaProvider)
    }

    private var selection: Binding<Selection?> {
        Binding {
            navigation.selectedProvider.map(Selection.provider) ?? .page(navigation.currentPage)
        } set: { value in
            switch value {
            case .provider(let provider): navigation.selectProvider(provider)
            case .page(let page): navigation.currentPage = page
            case nil: break
            }
        }
    }

    private var providers: [ProviderSettingsState] {
        controller.providers.filter {
            search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search)
        }.map { descriptor in
            let provider = descriptor.id
            return ProviderSettingsState(provider: provider, accounts: accounts.accounts,
                permissions: accounts.nativeSourcePermissions, quota: quota.state,
                tracking: controller.trackingPreferences)
        }.sorted {
            if $0.needsAttention != $1.needsAttention { return $0.needsAttention }
            return $0.provider.displayName.localizedStandardCompare($1.provider.displayName) == .orderedAscending
        }
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section("nav.providers".localized()) {
                    ForEach(providers.filter { $0.connection != .disabled && !$0.isUnconnected }, id: \.provider) { state in
                        providerRow(state)
                    }
                }
                let unconnected = providers.filter { $0.connection != .disabled && $0.isUnconnected }
                Section(isExpanded: Binding(get: { showUnconnected || !search.isEmpty }, set: { showUnconnected = $0 })) {
                    ForEach(unconnected, id: \.provider) { providerRow($0) }
                } header: {
                    Text(String(format: "settings.unconnectedCount".localized(), unconnected.count))
                }
                let disabled = providers.filter { $0.connection == .disabled }
                Section(isExpanded: Binding(get: { showDisabled || !search.isEmpty }, set: { showDisabled = $0 })) {
                    ForEach(disabled, id: \.provider) { providerRow($0) }
                } header: {
                    Text(String(format: "settings.disabledCount".localized(), disabled.count))
                }
                Section("settings.application".localized()) {
                    ForEach(NavigationPage.settingsPages.filter {
                        search.isEmpty || $0.settingsTitle.localizedCaseInsensitiveContains(search)
                    }) { page in
                        Label(page.settingsTitle, systemImage: page.icon).tag(Selection.page(page))
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $search, placement: .sidebar, prompt: "settings.search".localized())
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            if let provider = navigation.selectedProvider {
                ProviderSettingsScreen(provider: provider).id(provider)
            } else {
                AppSettingsPage(page: navigation.currentPage)
            }
        }
        .frame(minWidth: 680, minHeight: 480)
    }

    private func providerRow(_ state: ProviderSettingsState) -> some View {
        HStack {
            ProviderIcon(provider: state.provider, size: 18)
            Text(controller.providers.first { $0.id == state.provider }?.displayName ?? state.provider.displayName)
            Spacer()
            Image(systemName: state.needsAttention ? "exclamationmark.triangle" : state.connection.symbol)
                .foregroundStyle(state.needsAttention ? Color.orange : state.connection.color)
                .accessibilityLabel(state.needsAttention ? "connections.attention".localized() : state.connection.title)
        }
        .tag(Selection.provider(state.provider))
    }
}

extension NavigationPage {
    static let settingsPages: [Self] = [.general, .menuBar, .notifications, .privacy, .proxy, .updates]

    @MainActor var settingsTitle: String {
        switch self {
        case .general, .settings: "settings.general".localized()
        case .menuBar: "connections.menuBar".localized()
        case .notifications: "settings.notifications.title".localized()
        case .privacy: "connections.privacy".localized()
        case .proxy: "CLIProxyAPI"
        case .updates, .about: "settings.aboutUpdates".localized()
        default: "settings.general".localized()
        }
    }
}
