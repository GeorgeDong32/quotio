import QuotioApplication
import QuotioDomain
import SwiftUI

struct NativePermissionSheet: View {
    let source: NativeSourcePermission
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountsScreenModel.self) private var accounts
    @Environment(QuotaFeatureController.self) private var controller
    @State private var failed = false
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("settings.authorize".localized()).font(.title2)
            Text(String(format: "settings.permissionExplanation".localized(), source.keychainItemName, source.provider.displayName))
                .fixedSize(horizontal: false, vertical: true)
            if let account = source.keychainAccount {
                LabeledContent("settings.keychainAccount".localized(), value: account)
            }
            if failed { Text((accounts.nativeAuthorizationFailure ?? .unknown).message).foregroundStyle(.red) }
            if isSubmitting {
                ProgressView("settings.authorization.pending".localized())
                    .controlSize(.small)
            }
            HStack {
                Spacer()
                Button((isSubmitting ? "action.close" : "action.cancel").localized()) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("onboarding.button.continue".localized()) {
                    isSubmitting = true
                    failed = false
                    Task {
                        defer { isSubmitting = false }
                        do {
                            try await accounts.authorizeNativeSource(source)
                            await controller.refresh(provider: source.provider)
                            dismiss()
                        } catch { failed = true }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting || accounts.authorizingNativeSourceID != nil)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
