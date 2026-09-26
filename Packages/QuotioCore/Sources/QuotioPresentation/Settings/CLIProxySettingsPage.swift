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
            if proxy.isBinaryInstalled {
                serverSection
                configurationSection
                versionSection
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("CLIProxyAPI", systemImage: "network")
                            .font(.headline)
                        Text("settings.proxy.optional".localized())
                            .foregroundStyle(.secondary)
                        Button("settings.proxy.installAndRun".localized()) {
                            run {
                                try await proxy.downloadAndInstallBinary()
                                try await proxy.start()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
            }
            if proxy.isDownloading {
                ProgressView(value: proxy.downloadProgress)
            } else if working {
                ProgressView().controlSize(.small)
            }
            if let errorMessage = errorMessage ?? proxy.lastError {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .disabled(working)
        .navigationTitle("CLIProxyAPI")
        .onAppear { portText = String(proxy.port) }
        .onChange(of: proxy.port) { _, port in portText = String(port) }
        .sheet(isPresented: $showVersions) { ProxyVersionManagerSheet() }
    }

    private var serverSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label((proxy.proxyStatus.running ? "status.running" : "status.stopped").localized(),
                          systemImage: proxy.proxyStatus.running ? "checkmark.circle.fill" : "stop.circle")
                        .font(.headline)
                        .foregroundStyle(proxy.proxyStatus.running ? Color.green : Color.secondary)
                    Spacer()
                    Button((proxy.proxyStatus.running ? "action.stop" : "action.start").localized(),
                           systemImage: proxy.proxyStatus.running ? "stop.fill" : "play.fill") {
                        run {
                            if proxy.proxyStatus.running { await proxy.stopAndWait() }
                            else { try await proxy.start() }
                        }
                    }
                    Button("action.restart".localized(), systemImage: "arrow.clockwise") {
                        run { try await proxy.restart() }
                    }
                    .disabled(!proxy.proxyStatus.running)
                }
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("settings.proxy.endpoint".localized())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(proxy.baseURL)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button("action.copy".localized(), systemImage: "doc.on.doc") {
                        pasteboard.copy(proxy.baseURL)
                    }
                    .labelStyle(.iconOnly)
                    .help("action.copy".localized())
                }
                Divider()
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { managementActions }
                    VStack(alignment: .leading, spacing: 8) { managementActions }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var managementActions: some View {
        Button("settings.proxy.openManagement".localized(), systemImage: "arrow.up.right.square") {
            if let url = proxy.managementPageURL { platform.open(url) }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!proxy.proxyStatus.running)
        Button("settings.proxy.copyKey".localized(), systemImage: "key") {
            pasteboard.copy(proxy.managementKey)
        }
        .disabled(proxy.managementKey.isEmpty)
    }

    private var configurationSection: some View {
        Section("settings.proxy.configuration".localized()) {
            LabeledContent("settings.proxy.port".localized()) {
                HStack(spacing: 8) {
                    TextField("settings.proxy.port".localized(), text: $portText)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .monospacedDigit()
                        .frame(width: 80)
                    Button("action.save".localized()) {
                        if let port = UInt16(portText), port > 0 { proxy.setPort(port) }
                    }
                    .disabled(UInt16(portText).map { $0 == 0 || $0 == proxy.port } ?? true)
                }
            }
            Toggle("settings.autoStartProxy".localized(), isOn: Binding(
                get: { settings.proxyPreferences.autoStartProxy },
                set: { settings.setAutoStartProxy($0) }
            ))
        }
    }

    private var versionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("settings.proxy.version".localized()).font(.headline)
                    Spacer()
                    Text(proxy.currentVersion ?? proxy.installedProxyVersion ?? "—")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { versionActions }
                    VStack(alignment: .leading, spacing: 8) { versionActions }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var versionActions: some View {
        if let version = proxy.availableUpgrade {
            Button(String(format: "settings.proxy.updateTo".localized(), version.version)) {
                run { try await proxy.performManagedUpgrade(to: version) }
            }
        } else {
            Button("action.checkUpdates".localized(), systemImage: "arrow.clockwise") {
                run { await proxy.checkForUpgrade() }
            }
        }
        Button("settings.proxy.manageVersions".localized()) { showVersions = true }
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
