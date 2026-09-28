import QuotioApplication
import QuotioDomain
import SwiftUI

/// Pause and remove actions for one login source, when the helper allows them.
struct LoginSourceMenu: View {
    let provider: QuotaProvider
    let source: AccountLoginSource
    @Environment(AccountsScreenModel.self) private var accounts
    @Environment(QuotaFeatureController.self) private var controller
    @Environment(AccountsSettingsScreenModel.self) private var model

    var body: some View {
        if source.actions?.isEmpty == false {
            Menu {
                if source.actions?.contains("set_source_enabled") == true {
                    Toggle("settings.sources.pause".localized(), isOn: Binding(
                        get: { source.enabled == false },
                        set: { paused in
                            Task {
                                do {
                                    try await accounts.setSourceEnabled(!paused, sourceID: source.accountID)
                                    await controller.refresh(provider: provider)
                                } catch { model.actionFailed = true }
                            }
                        }
                    ))
                }
                if source.actions?.contains("remove_source") == true {
                    Button("action.remove".localized() + "…", role: .destructive) {
                        model.removingSource = .init(provider: provider, source: source)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("settings.sources.actions".localized())
            .accessibilityLabel(Text("settings.sources.actions".localized() + ": " + source.title))
        }
    }
}
