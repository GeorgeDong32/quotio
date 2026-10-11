//
//  ProviderConfigScreen.swift
//  QuotioForkExtras — proxy config.yaml ownership settings
//

import AppKit
import QuotioPresentation
import SwiftUI

/// Fork settings page for config.yaml ownership: toggling manual provider
/// config mode stops Quotio from resetting the provider/model sections of
/// the proxy configuration on every (re)start, while the app keeps
/// managing the proxy process, port, and management key.
public struct ProviderConfigScreen: View {
    private let configPath: String
    private let store: ManualProviderConfigStore
    @State private var manualProvidersEnabled = false

    public init(
        configPath: String,
        store: ManualProviderConfigStore = ManualProviderConfigStore()
    ) {
        self.configPath = configPath
        self.store = store
    }

    public var body: some View {
        Form {
            Section {
                Toggle(
                    "proxyConfig.manualProviders".localized(),
                    isOn: $manualProvidersEnabled
                )
                .onChange(of: manualProvidersEnabled) { _, enabled in
                    store.isEnabled = enabled
                }
            } footer: {
                Text("proxyConfig.manualProviders.footer".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text(configPath)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Button("proxyConfig.showInFinder".localized()) {
                    NSWorkspace.shared.activateFileViewerSelecting([
                        URL(fileURLWithPath: configPath)
                    ])
                }
            } header: {
                Text("proxyConfig.configFile".localized())
            } footer: {
                Text("proxyConfig.configFile.footer".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("proxyConfig.title".localized())
        .onAppear { manualProvidersEnabled = store.isEnabled }
    }
}
