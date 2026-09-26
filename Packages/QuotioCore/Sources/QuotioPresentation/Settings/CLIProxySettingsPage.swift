import QuotioDomain
import SwiftUI

struct CLIProxySettingsPage: View {
    @Environment(ProxyScreenModel.self) private var proxy
    @Environment(SettingsScreenModel.self) private var settings
    @Environment(PlatformActionScreenModel.self) private var platform
    @Environment(PasteboardScreenModel.self) private var pasteboard
    @State private var portText = ""
    @State private var showVersions = false
    @State private var working = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if !proxy.isBinaryInstalled {
                Section {
                    Text("settings.proxy.optional".localized())
                    Button("settings.proxy.installAndRun".localized()) {
                        run {
                            try await proxy.downloadAndInstallBinary()
                            try await proxy.start()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Section {
                    LabeledContent("settings.proxy.state".localized()) {
                        Label((proxy.proxyStatus.running ? "status.running" : "status.stopped").localized(),
                            systemImage: proxy.proxyStatus.running ? "checkmark.circle" : "stop.circle")
                    }
                    LabeledContent("settings.proxy.endpoint".localized()) {
                        Text(proxy.baseURL).textSelection(.enabled)
                        Button("action.copy".localized()) { pasteboard.copy(proxy.baseURL) }
                    }
                    HStack {
                        Button((proxy.proxyStatus.running ? "action.stop" : "action.start").localized()) {
                            run {
                                if proxy.proxyStatus.running { await proxy.stopAndWait() }
                                else { try await proxy.start() }
                            }
                        }
                        Button("action.restart".localized()) { run { try await proxy.restart() } }
                            .disabled(!proxy.proxyStatus.running)
                    }
                    HStack {
                        Button("settings.proxy.openManagement".localized()) {
                            if let url = proxy.managementPageURL { platform.open(url) }
                        }
                        .disabled(!proxy.proxyStatus.running)
                        Button("settings.proxy.copyKey".localized()) { pasteboard.copy(proxy.managementKey) }
                            .disabled(proxy.managementKey.isEmpty)
                    }
                }
                Section("settings.proxy.configuration".localized()) {
                    HStack {
                        TextField("settings.proxy.port".localized(), text: $portText)
                        Button("action.save".localized()) {
                            if let port = UInt16(portText), port > 0 { proxy.setPort(port) }
                        }
                        .disabled(UInt16(portText).map { $0 == 0 || $0 == proxy.port } ?? true)
                    }
                    Text("localhost:" + String(proxy.port)).font(.caption).foregroundStyle(.secondary)
                    Toggle("settings.autoStartProxy".localized(), isOn: Binding(
                        get: { settings.proxyPreferences.autoStartProxy }, set: { settings.setAutoStartProxy($0) }
                    ))
                }
                Section("settings.proxy.version".localized()) {
                    LabeledContent("settings.proxy.version".localized(), value: proxy.currentVersion ?? proxy.installedProxyVersion ?? "—")
                    if let version = proxy.availableUpgrade {
                        Button(String(format: "settings.proxy.updateTo".localized(), version.version)) {
                            run { try await proxy.performManagedUpgrade(to: version) }
                        }
                    } else {
                        Button("action.checkUpdates".localized()) { Task { await proxy.checkForUpgrade() } }
                    }
                    Button("settings.proxy.manageVersions".localized()) { showVersions = true }
                }
            }
            if proxy.isDownloading { ProgressView(value: proxy.downloadProgress) }
            if let errorMessage = errorMessage ?? proxy.lastError { Text(errorMessage).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .disabled(working)
        .navigationTitle("CLIProxyAPI")
        .onAppear { portText = String(proxy.port) }
        .onChange(of: proxy.port) { _, port in portText = String(port) }
        .sheet(isPresented: $showVersions) { ProxyVersionManagerSheet() }
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        working = true
        errorMessage = nil
        Task {
            defer { working = false }
            do { try await action() } catch { errorMessage = proxy.errorMessage(for: error) }
        }
    }
}
