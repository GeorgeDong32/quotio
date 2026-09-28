//
//  RemoteConnectionScreen.swift
//  QuotioForkExtras — remote CLIProxyAPI connection settings
//

import SwiftUI

/// Fork remote-connection settings page: configure, test, and forget a
/// remote CLIProxyAPI instance. Ported from the fork's RemoteConnectionSheet
/// as a settings page (onboarding/dashboard integration was retired with the
/// upstream mode-selection UI).
public struct RemoteConnectionScreen: View {
    public init() {}

    @State private var manager = ForkRemoteConnectionManager()
    @State private var endpoint = ""
    @State private var displayName = ""
    @State private var managementKey = ""
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    public var body: some View {
        Form {
            connectionSection
            if let config = manager.config {
                Section("remote.savedConnection".localized()) {
                    LabeledContent("remote.endpoint", value: config.endpointURL)
                    if !config.displayName.isEmpty {
                        LabeledContent("remote.displayName", value: config.displayName)
                    }
                    if let last = config.lastConnected {
                        LabeledContent(
                            "remote.lastConnected",
                            value: last.formatted(date: .abbreviated, time: .shortened)
                        )
                    }
                    Button("remote.forget".localized(), role: .destructive) {
                        manager.clear()
                    }
                }
            }
            Section {
                Text("remote.modeNote".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("remote.title".localized())
        .alert("remote.saveError".localized(), isPresented: $showSaveError) {
            Button("action.ok".localized(), role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
        .onAppear {
            if let config = manager.config, endpoint.isEmpty {
                endpoint = config.endpointURL
                displayName = config.displayName
            }
        }
    }

    private var connectionSection: some View {
        Section {
            TextField("remote.endpointPlaceholder".localized(), text: $endpoint)
                .autocorrectionDisabled()
            TextField("remote.displayNamePlaceholder".localized(), text: $displayName)
            SecureField("remote.managementKeyPlaceholder".localized(), text: $managementKey)
            HStack {
                Button {
                    Task { await test() }
                } label: {
                    if manager.isTesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("remote.testConnection".localized())
                    }
                }
                .disabled(endpoint.isEmpty || managementKey.isEmpty || manager.isTesting)

                if let success = manager.lastTestSucceeded {
                    Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(success ? .green : .red)
                }

                Spacer()

                Button("action.save".localized()) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(endpoint.isEmpty || managementKey.isEmpty)
            }
        } header: {
            Text("remote.connection".localized())
        } footer: {
            Text("remote.connectionFooter".localized())
        }
    }

    private func test() async {
        await manager.testConnection(endpoint: endpoint, managementKey: managementKey)
        if manager.lastTestSucceeded == true {
            manager.markConnected()
        }
    }

    private func save() {
        guard let validated = RemoteURLValidator.validated(endpoint) else {
            saveErrorMessage = "remote.invalidEndpoint".localized()
            showSaveError = true
            return
        }
        let existing = manager.config
        let config = RemoteConnectionConfig(
            id: existing?.id ?? UUID(),
            endpointURL: validated,
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            verifySSL: existing?.verifySSL ?? true,
            timeoutSeconds: existing?.timeoutSeconds ?? 30,
            lastConnected: existing?.lastConnected
        )
        var key = managementKey
        if key.isEmpty, let existingID = existing?.id,
           let saved = Keychain.remoteManagementKeyStore.load(configID: existingID) {
            key = saved
        }
        guard !key.isEmpty else {
            saveErrorMessage = "remote.keyRequired".localized()
            showSaveError = true
            return
        }
        manager.save(config, managementKey: key)
    }
}
