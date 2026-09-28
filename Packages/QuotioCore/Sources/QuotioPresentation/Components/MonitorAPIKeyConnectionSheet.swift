import QuotioApplication
import QuotioDomain
import SwiftUI

struct MonitorAPIKeyConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let provider: QuotaProvider
    let account: Account?
    var inputs: [MonitoringProvider.Input] = []
    var providerName: String? = nil
    let onSave: (String, String, [String: String]) async throws -> Void

    @State private var label = ""
    @State private var apiKey = ""
    @State private var fields: [String: String] = [:]
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var isEditing: Bool { account != nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                ProviderIcon(provider: provider, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized(isEditing ? "connection.edit" : "connection.title"))
                        .font(.headline)
                    Text(localized("connection.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("settings.accountLabel".localized())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField(localized("label.placeholder"), text: $label)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isEditing)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(localized("apiKey.label"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        SecureField(localized("apiKey.placeholder"), text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                        Text(localized(isEditing ? "apiKey.rotateHint" : "apiKey.hint"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    ForEach(inputs) { input in
                        let title = input.required && !isEditing
                            ? String(format: "settings.input.required".localized(), input.name)
                            : input.name
                        let value = Binding(get: { fields[input.fieldPath] ?? "" }, set: { fields[input.fieldPath] = $0 })
                        if let values = input.values {
                            Picker(title, selection: value) {
                                Text("—").tag("")
                                ForEach(values, id: \.self) { Text($0).tag($0) }
                            }
                        } else {
                            TextField(title, text: value)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                }
                .padding(24)
            }

            Divider()

            HStack {
                Button("action.cancel".localized()) { dismiss() }
                Spacer()
                Button(isEditing ? "action.save".localized() : "action.connect".localized()) {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || (!isEditing && inputs.contains { $0.required && (fields[$0.fieldPath] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                    || isSaving)
            }
            .padding(20)
        }
        .frame(width: 450, height: min(700, 360 + CGFloat(inputs.count) * 64))
        .onAppear { label = account?.displayName ?? "" }
    }

    private func localized(_ suffix: String) -> String {
        String(format: ("settings.apiKey." + suffix).localized(), providerName ?? provider.displayName)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(label, apiKey, fields)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
