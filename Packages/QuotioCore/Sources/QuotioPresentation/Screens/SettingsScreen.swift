//
//  SettingsScreen.swift
//  Quotio
//

import AppKit
import QuotioApplication
import QuotioDomain
import SwiftUI

public struct SettingsScreen: View {
    public init() {}
    @Environment(ProxyManagementScreenModel.self) private var viewModel
    @Environment(OperatingModeManager.self) private var modeManager
    @Environment(LanguageManager.self) private var languageManager

    public var body: some View {
        TabView {
            Form {
                Section("settings.general".localized()) { LaunchAtLoginToggle() }
                Section("settings.language".localized()) {
                    Picker("settings.language".localized(), selection: Binding(
                        get: { languageManager.currentLanguage },
                        set: { languageManager.setLanguage($0) }
                    )) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                }
                AppearanceSettingsSection()
            }
            .tabItem { Label("settings.general".localized(), systemImage: "gearshape") }

            Form {
                RefreshCadenceSettingsSection()
                NotificationSettingsSection()
                QuotaDisplaySettingsSection()
                UsageDisplaySettingsSection()
            }
            .tabItem { Label("connections.monitor".localized(), systemImage: "chart.bar") }

            Form { MenuBarSettingsSection() }
                .tabItem { Label("connections.menuBar".localized(), systemImage: "menubar.rectangle") }

            Form {
                PrivacySettingsSection()
                CredentialMigrationSection()
            }
            .tabItem { Label("connections.privacy".localized(), systemImage: "lock") }

            Form {
                LocalProxyServerSection()
                ProxySettingsSection()
                LocalPathsSection()
            }
            .tabItem { Label("connections.gateway".localized(), systemImage: "network") }

            Form {
                Section("troubleshooting.title".localized()) {
                    Button("troubleshooting.applyWorkaround".localized()) { viewModel.applyBaseURLWorkaround() }
                    Button("troubleshooting.restoreOriginal".localized()) { viewModel.removeBaseURLWorkaround() }
                    Text("troubleshooting.description".localized()).foregroundStyle(.secondary)
                }
            }
            .tabItem { Label("connections.advanced".localized(), systemImage: "slider.horizontal.3") }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Proxy Settings Section
// Dispatches hot-reload settings through the screen model.

struct ProxySettingsSection: View {
    @Environment(ProxyManagementScreenModel.self) private var viewModel
    @Environment(SettingsScreenModel.self) private var settingsModel
    
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var isLoadingConfig = false  // Prevents onChange from firing during load
    
    @State private var proxyURL = ""
    @State private var routingStrategy = "round-robin"
    @State private var switchProject = true
    @State private var switchPreviewModel = true
    @State private var requestRetry = 3
    @State private var maxRetryInterval = 30
    @State private var loggingToFile = true
    @State private var requestLog = false
    @State private var debugMode = false
    
    @State private var proxyURLValidation: ProxyURLValidationResult = .empty
    
    private var isAPIAvailable: Bool {
        viewModel.proxy.proxyStatus.running && viewModel.isManagementAPIAvailable
    }
    
    var body: some View {
        if !isAPIAvailable {
            // Show placeholder when API is not available
            Section {
                HStack {
                    Image(systemName: "network.slash")
                        .foregroundStyle(.secondary)
                    Text("settings.proxy.startToConfigureAdvanced".localized())
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("settings.proxySettings".localized(), systemImage: "slider.horizontal.3")
            }
        } else if isLoading {
            Section {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("settings.proxy.loading".localized())
                        .foregroundStyle(.secondary)
                }
            } header: {
                Label("settings.proxySettings".localized(), systemImage: "slider.horizontal.3")
            }
            .onAppear {
                Task {
                    await loadConfig()
                }
            }
        } else if let error = loadError {
            Section {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("action.retry".localized()) {
                        Task {
                            await loadConfig()
                        }
                    }
                }
            } header: {
                Label("settings.proxySettings".localized(), systemImage: "slider.horizontal.3")
            }
        } else {
            upstreamProxySection
            routingStrategySection
            quotaExceededSection
            retryConfigurationSection
            loggingSection
        }
    }
    
    private var upstreamProxySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("settings.upstreamProxy".localized()) {
                    TextField("", text: $proxyURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .onChange(of: proxyURL) { _, newValue in
                            proxyURLValidation = ProxyURLValidator.validate(newValue)
                        }
                        .onSubmit {
                            Task { await saveProxyURL() }
                        }
                }
                
                if proxyURLValidation != .valid && proxyURLValidation != .empty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text((proxyURLValidation.localizationKey ?? "").localized())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("settings.upstreamProxy.placeholder".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("settings.upstreamProxy.title".localized(), systemImage: "network")
        }
    }
    
    private var routingStrategySection: some View {
        Section {
            Picker("settings.routingStrategy".localized(), selection: $routingStrategy) {
                Text("settings.roundRobin".localized()).tag("round-robin")
                Text("settings.fillFirst".localized()).tag("fill-first")
            }
            .pickerStyle(.segmented)
            .onChange(of: routingStrategy) { _, newValue in
                guard !isLoadingConfig else { return }
                Task { await saveRoutingStrategy(newValue) }
            }
        } header: {
            Label("settings.routingStrategy".localized(), systemImage: "arrow.triangle.branch")
        } footer: {
            Text(routingStrategy == "round-robin"
                 ? "settings.roundRobinDesc".localized()
                 : "settings.fillFirstDesc".localized())
            .font(.caption)
        }
    }
    
    private var quotaExceededSection: some View {
        Section {
            Toggle("settings.autoSwitchAccount".localized(), isOn: $switchProject)
                .onChange(of: switchProject) { _, newValue in
                    guard !isLoadingConfig else { return }
                    Task { await saveSwitchProject(newValue) }
                }
            Toggle("settings.autoSwitchPreview".localized(), isOn: $switchPreviewModel)
                .onChange(of: switchPreviewModel) { _, newValue in
                    guard !isLoadingConfig else { return }
                    Task { await saveSwitchPreviewModel(newValue) }
                }
        } header: {
            Label("settings.quotaExceededBehavior".localized(), systemImage: "exclamationmark.triangle")
        } footer: {
            Text("settings.quotaExceededHelp".localized())
                .font(.caption)
        }
    }
    
    private var retryConfigurationSection: some View {
        Section {
            Stepper("settings.maxRetries".localized() + ": \(requestRetry)", value: $requestRetry, in: 0...10)
                .onChange(of: requestRetry) { _, newValue in
                    guard !isLoadingConfig else { return }
                    Task { await saveRequestRetry(newValue) }
                }
            
            Stepper("settings.maxRetryInterval".localized() + ": \(maxRetryInterval)s", value: $maxRetryInterval, in: 5...300, step: 5)
                .onChange(of: maxRetryInterval) { _, newValue in
                    guard !isLoadingConfig else { return }
                    Task { await saveMaxRetryInterval(newValue) }
                }
        } header: {
            Label("settings.retryConfiguration".localized(), systemImage: "arrow.clockwise")
        } footer: {
            Text("settings.retryHelp".localized())
                .font(.caption)
        }
    }
    
    private var loggingSection: some View {
        Section {
            Toggle("settings.loggingToFile".localized(), isOn: $loggingToFile)
                .onChange(of: loggingToFile) { _, newValue in
                    guard !isLoadingConfig else { return }
                    Task { await saveLoggingToFile(newValue) }
                }
            
            Toggle("settings.requestLog".localized(), isOn: $requestLog)
                .onChange(of: requestLog) { _, newValue in
                    guard !isLoadingConfig else { return }
                    Task { await saveRequestLog(newValue) }
                }
            
            Toggle("settings.debugMode".localized(), isOn: $debugMode)
                .onChange(of: debugMode) { _, newValue in
                    guard !isLoadingConfig else { return }
                    Task { await saveDebugMode(newValue) }
                }
        } header: {
            Label("settings.logging".localized(), systemImage: "doc.text")
        } footer: {
            Text("settings.loggingHelp".localized())
                .font(.caption)
        }
    }
    
    private func loadConfig() async {
        isLoading = true
        isLoadingConfig = true
        loadError = nil
        
        guard viewModel.isManagementAPIAvailable else {
            loadError = "settings.proxy.startToConfigureAdvanced".localized()
            isLoading = false
            isLoadingConfig = false
            return
        }
        
        do {
            let (config, fetchedStrategy) = try await viewModel.loadManagementConfiguration()
            
            proxyURL = config.proxyURL ?? ""
            routingStrategy = fetchedStrategy
            requestRetry = config.requestRetry ?? 3
            maxRetryInterval = config.maxRetryInterval ?? 30
            loggingToFile = config.loggingToFile ?? true
            requestLog = config.requestLog ?? false
            debugMode = config.debug ?? false
            switchProject = config.quotaExceeded?.switchProject ?? true
            switchPreviewModel = config.quotaExceeded?.switchPreviewModel ?? true
            proxyURLValidation = ProxyURLValidator.validate(proxyURL)
            isLoading = false
            
            try? await Task.sleep(for: .milliseconds(100))
            isLoadingConfig = false
        } catch {
            loadError = error.localizedDescription
            isLoading = false
            isLoadingConfig = false
        }
    }
    
    /// Persists the upstream proxy URL to both app preferences and the running proxy instance.
    ///
    /// The URL is first saved to app preferences so it survives app restarts (used by
    /// the proxy lifecycle controller during startup), then sent to the
    /// proxy API to take effect immediately. Only valid or empty URLs are saved.
    private func saveProxyURL() async {
        if proxyURL.isEmpty {
            await settingsModel.setProxyURL("")
        } else if proxyURLValidation == .valid {
            await settingsModel.setProxyURL(ProxyURLValidator.sanitize(proxyURL))
        }

        do {
            if proxyURL.isEmpty {
                try await viewModel.setManagementProxyURL(nil)
            } else if proxyURLValidation == .valid {
                try await viewModel.setManagementProxyURL(ProxyURLValidator.sanitize(proxyURL))
            }
        } catch {
            NSLog("[ProxySettings] Failed to save proxy URL: \(error)")
        }
    }
    
    private func saveRoutingStrategy(_ strategy: String) async {
        do {
            try await viewModel.setManagementRoutingStrategy(strategy)
        } catch {
            NSLog("[ProxySettings] Failed to save routing strategy: \(error)")
        }
    }
    
    private func saveSwitchProject(_ enabled: Bool) async {
        do {
            try await viewModel.setManagementSwitchProject(enabled)
        } catch {
            NSLog("[ProxySettings] Failed to save switch project: \(error)")
        }
    }
    
    private func saveSwitchPreviewModel(_ enabled: Bool) async {
        do {
            try await viewModel.setManagementSwitchPreviewModel(enabled)
        } catch {
            NSLog("[ProxySettings] Failed to save switch preview model: \(error)")
        }
    }
    
    private func saveRequestRetry(_ count: Int) async {
        do {
            try await viewModel.setManagementRequestRetry(count)
        } catch {
            NSLog("[ProxySettings] Failed to save request retry: \(error)")
        }
    }
    
    private func saveMaxRetryInterval(_ seconds: Int) async {
        do {
            try await viewModel.setManagementMaxRetryInterval(seconds)
        } catch {
            NSLog("[ProxySettings] Failed to save max retry interval: \(error)")
        }
    }
    
    private func saveLoggingToFile(_ enabled: Bool) async {
        settingsModel.setLoggingToFile(enabled)
        do {
            try await viewModel.setManagementLoggingToFile(enabled)
        } catch {
            NSLog("[ProxySettings] Failed to save logging to file: \(error)")
        }
    }
    
    private func saveRequestLog(_ enabled: Bool) async {
        do {
            try await viewModel.setManagementRequestLog(enabled)
        } catch {
            NSLog("[ProxySettings] Failed to save request log: \(error)")
        }
    }
    
    private func saveDebugMode(_ enabled: Bool) async {
        do {
            try await viewModel.setManagementDebug(enabled)
        } catch {
            NSLog("[ProxySettings] Failed to save debug mode: \(error)")
        }
    }
}

// MARK: - Local Proxy Server Section

struct LocalProxyServerSection: View {
    @Environment(ProxyManagementScreenModel.self) private var viewModel
    @Environment(SettingsScreenModel.self) private var settingsModel
    @State private var portText: String = ""
    @State private var isLoadingConfig = false  // Prevents onChange from firing during initial load

    private var autoStartProxyBinding: Binding<Bool> {
        Binding(
            get: { settingsModel.proxyPreferences.autoStartProxy },
            set: { settingsModel.setAutoStartProxy($0) }
        )
    }

    private var autoStartTunnelBinding: Binding<Bool> {
        Binding(
            get: { settingsModel.tunnelPreferences.autoStartTunnel },
            set: { settingsModel.setAutoStartTunnel($0) }
        )
    }

    private var autoRestartTunnelBinding: Binding<Bool> {
        Binding(
            get: { settingsModel.tunnelPreferences.autoRestartTunnel },
            set: { settingsModel.setAutoRestartTunnel($0) }
        )
    }

    private var allowNetworkAccessBinding: Binding<Bool> {
        Binding(
            get: { settingsModel.proxyPreferences.allowNetworkAccess },
            set: { settingsModel.setAllowNetworkAccess($0) }
        )
    }
    
    var body: some View {
        Section {
            HStack {
                Text("settings.port".localized())
                Spacer()
                TextField("settings.port".localized(), text: $portText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .onChange(of: portText) { _, newValue in
                        guard !isLoadingConfig else { return }
                        if let port = UInt16(newValue), port > 0 {
                            viewModel.proxy.setPort(port)
                        }
                    }
            }
            
            LabeledContent("settings.status".localized()) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.proxy.proxyStatus.running ? .green : .gray)
                        .frame(width: 8, height: 8)
                    Text(viewModel.proxy.proxyStatus.running ? "status.running".localized() : "status.stopped".localized())
                }
            }
            
            LabeledContent("settings.endpoint".localized()) {
                Text(viewModel.proxy.proxyStatus.endpoint)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            
            ManagementKeyRow()
            
            Toggle("settings.autoStartProxy".localized(), isOn: autoStartProxyBinding)
            
            Toggle("settings.autoStartTunnel".localized(), isOn: autoStartTunnelBinding)
                .disabled(!viewModel.tunnel.installation.isInstalled)
            
            Toggle("settings.autoRestartTunnel".localized(), isOn: autoRestartTunnelBinding)
                .disabled(!viewModel.tunnel.installation.isInstalled)
                
            NetworkAccessSection(allowNetworkAccess: allowNetworkAccessBinding)
                

        } header: {
            Label("settings.proxyServer".localized(), systemImage: "server.rack")
        } footer: {
            Text("settings.restartProxy".localized())
                .font(.caption)
        }
        .onAppear {
            isLoadingConfig = true
            portText = String(viewModel.proxy.port)
            // Delay clearing the flag to allow onChange to be suppressed
            DispatchQueue.main.async {
                isLoadingConfig = false
            }
        }
    }
}

struct NetworkAccessSection: View {
    @Binding var allowNetworkAccess: Bool
    
    var body: some View {
        Section {
            Toggle("settings.allowNetworkAccess".localized(), isOn: $allowNetworkAccess)
            
            LabeledContent("settings.bindAddress".localized()) {
                Text(allowNetworkAccess ? "0.0.0.0 (All Interfaces)" : "127.0.0.1 (Localhost)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(allowNetworkAccess ? .orange : .secondary)
            }
            
            if allowNetworkAccess {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("settings.networkAccessWarning".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Label("settings.networkAccess".localized(), systemImage: "network")
        } footer: {
            Text("settings.networkAccessFooter".localized())
                .font(.caption)
        }
    }
}

// MARK: - Local Paths Section

struct LocalPathsSection: View {
    @Environment(ProxyManagementScreenModel.self) private var viewModel
    
    var body: some View {
        Section {
            LabeledContent("settings.binary".localized()) {
                PathLabel(path: viewModel.proxy.effectiveBinaryPath)
            }
            
            LabeledContent("settings.config".localized()) {
                PathLabel(path: viewModel.proxy.configPath)
            }
            
            LabeledContent("settings.authDir".localized()) {
                PathLabel(path: viewModel.proxy.authDir)
            }
        } header: {
            Label("settings.paths".localized(), systemImage: "folder")
        }
    }
}

// MARK: - Path Label

struct PathLabel: View {
    let path: String
    @Environment(PasteboardScreenModel.self) private var pasteboard
    
    var body: some View {
        HStack {
            Text(path)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            
            Button {
                pasteboard.copy(path)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
    }
}

struct NotificationSettingsSection: View {
    @Environment(NotificationSettingsScreenModel.self) private var notificationModel
    
    var body: some View {
        let preferences = notificationModel.snapshot.preferences
        
        Section {
            Toggle("settings.notifications.enabled".localized(), isOn: Binding(
                get: { preferences.notificationsEnabled },
                set: { enabled in
                    notificationModel.update { $0.notificationsEnabled = enabled }
                }
            ))
            
            if preferences.notificationsEnabled {
                Toggle("settings.notifications.quotaLow".localized(), isOn: Binding(
                    get: { preferences.notifyOnQuotaLow },
                    set: { enabled in notificationModel.update { $0.notifyOnQuotaLow = enabled } }
                ))
                
                Toggle("settings.notifications.cooling".localized(), isOn: Binding(
                    get: { preferences.notifyOnCooling },
                    set: { enabled in notificationModel.update { $0.notifyOnCooling = enabled } }
                ))
                
                Toggle("settings.notifications.proxyCrash".localized(), isOn: Binding(
                    get: { preferences.notifyOnProxyCrash },
                    set: { enabled in notificationModel.update { $0.notifyOnProxyCrash = enabled } }
                ))
                
                Toggle("settings.notifications.upgradeAvailable".localized(), isOn: Binding(
                    get: { preferences.notifyOnUpgradeAvailable },
                    set: { enabled in
                        notificationModel.update { $0.notifyOnUpgradeAvailable = enabled }
                    }
                ))
                
                HStack {
                    Text("settings.notifications.threshold".localized())
                    Spacer()
                    Picker("", selection: Binding(
                        get: { Int(preferences.quotaAlertThreshold) },
                        set: { threshold in
                            notificationModel.update { $0.quotaAlertThreshold = Double(threshold) }
                        }
                    )) {
                        Text("10%").tag(10)
                        Text("20%").tag(20)
                        Text("30%").tag(30)
                        Text("50%").tag(50)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 80)
                }
            }
            
            if notificationModel.snapshot.authorizationStatus != .authorized {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("settings.notifications.notAuthorized".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("settings.notifications".localized(), systemImage: "bell")
        } footer: {
            Text("settings.notifications.help".localized())
                .font(.caption)
        }
        .task {
            await notificationModel.refreshAuthorizationStatus()
        }
    }
}

// MARK: - Quota Display Settings Section

struct QuotaDisplaySettingsSection: View {
    @Environment(MenuBarSettingsManager.self) private var settings
    
    private var displayModeBinding: Binding<QuotaDisplayMode> {
        Binding(
            get: { settings.quotaDisplayMode },
            set: { settings.quotaDisplayMode = $0 }
        )
    }
    
    private var displayStyleBinding: Binding<QuotaDisplayStyle> {
        Binding(
            get: { settings.quotaDisplayStyle },
            set: { settings.quotaDisplayStyle = $0 }
        )
    }
    
    var body: some View {
        Section {
            Picker("settings.quota.displayMode".localized(), selection: displayModeBinding) {
                Text("settings.quota.displayMode.used".localized()).tag(QuotaDisplayMode.used)
                Text("settings.quota.displayMode.remaining".localized()).tag(QuotaDisplayMode.remaining)
            }
            .pickerStyle(.segmented)
            
            Picker("settings.quota.displayStyle".localized(), selection: displayStyleBinding) {
                ForEach(QuotaDisplayStyle.allCases) { style in
                    Text(style.localizationKey.localized()).tag(style)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Label("settings.quota.display".localized(), systemImage: "percent")
        } footer: {
            Text("settings.quota.display.help".localized())
                .font(.caption)
        }
    }
}

// MARK: - Refresh Cadence Settings Section

struct RefreshCadenceSettingsSection: View {
    @Environment(QuotaFeatureController.self) private var viewModel
    private var cadenceBinding: Binding<Int> {
        Binding(
            get: { viewModel.monitoringSettings?.refreshInterval ?? 0 },
            set: { value in Task { await viewModel.setRefreshInterval(value) } }
        )
    }

    var body: some View {
        Section {
            Picker("settings.refresh.cadence".localized(), selection: cadenceBinding) {
                if let seconds = viewModel.monitoringSettings?.refreshInterval,
                   !RefreshCadence.allCases.contains(where: { Int($0.intervalSeconds ?? 0) == seconds }) {
                    Text(Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds]))).tag(seconds)
                }
                ForEach(RefreshCadence.allCases) { cadence in
                    Text(cadence.localizationKey.localized()).tag(Int(cadence.intervalSeconds ?? 0))
                }
            }
            
            .disabled(!viewModel.canManageSettings || viewModel.monitoringSettings == nil || viewModel.isUpdatingSettings)
            if let error = viewModel.settingsError { Text(error).foregroundStyle(.red) }
            if viewModel.monitoringSettings?.refreshInterval == 0 {
                Button {
                    Task {
                        await viewModel.refreshAll(force: true)
                    }
                } label: {
                    Label("settings.refresh.now".localized(), systemImage: "arrow.clockwise")
                }
            }
        } header: {
            Label("settings.refresh".localized(), systemImage: "clock.arrow.2.circlepath")
        } footer: {
            Text("settings.refresh.help".localized())
                .font(.caption)
        }
    }
}

// MARK: - Update Settings Section

struct UpdateSettingsSection: View {
    @Environment(SettingsScreenModel.self) private var settingsModel
    @Environment(ApplicationUpdateScreenModel.self) private var updateModel

    private var autoCheckUpdatesBinding: Binding<Bool> {
        Binding(
            get: { settingsModel.appShellPreferences.autoCheckUpdates },
            set: { settingsModel.setAutomaticUpdateChecks($0) }
        )
    }
    
    var body: some View {
        Section {
            Toggle("settings.autoCheckUpdates".localized(), isOn: autoCheckUpdatesBinding)
            
            HStack {
                Text("settings.lastChecked".localized())
                Spacer()
                if let date = updateModel.snapshot.lastCheckDate {
                    Text(date, style: .relative)
                        .foregroundStyle(.secondary)
                } else {
                    Text("settings.never".localized())
                        .foregroundStyle(.secondary)
                }
            }
            
            Button("settings.checkNow".localized()) {
                updateModel.checkForUpdates()
            }
            .disabled(!updateModel.snapshot.canCheck)
        } header: {
            Label("settings.updates".localized(), systemImage: "arrow.down.circle")
        }
    }
}

// MARK: - Proxy Update Settings Section

struct ProxyUpdateSettingsSection: View {
    @Environment(ProxyManagementScreenModel.self) private var viewModel
    @State private var isCheckingForUpdate = false
    @State private var isUpgrading = false
    @State private var upgradeError: String?
    @State private var showAdvancedSheet = false

    private var proxyManager: ProxyScreenModel {
        viewModel.proxy
    }

    var body: some View {
        Section {
            // Current version
            LabeledContent("settings.proxyUpdate.currentVersion".localized()) {
                if let version = proxyManager.currentVersion ?? proxyManager.installedProxyVersion {
                    Text("v\(version)")
                        .font(.system(.body, design: .monospaced))
                } else {
                    Text("settings.proxyUpdate.unknown".localized())
                        .foregroundStyle(.secondary)
                }
            }
            
            // Upgrade status
            if proxyManager.upgradeAvailable, let upgrade = proxyManager.availableUpgrade {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label {
                            Text("settings.proxyUpdate.available".localized())
                        } icon: {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundStyle(.green)
                        }
                        
                        Text("v\(upgrade.version)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button {
                        performUpgrade(to: upgrade)
                    } label: {
                        ZStack {
                            Text("action.update".localized())
                                .opacity(isUpgrading ? 0 : 1)
                            
                            if isUpgrading {
                                SmallProgressView()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isUpgrading)
                }
            } else {
                HStack {
                    Label {
                        Text("settings.proxyUpdate.upToDate".localized())
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    
                    Spacer()

                    Button {
                        checkForUpdate()
                    } label: {
                        ZStack {
                            Text("settings.proxyUpdate.checkNow".localized())
                                .opacity(isCheckingForUpdate ? 0 : 1)

                            if isCheckingForUpdate {
                                SmallProgressView()
                            }
                        }
                    }
                    .disabled(isCheckingForUpdate)
                }

                // Last checked time
                if let lastCheck = proxyManager.lastProxyUpdateCheckDate {
                    HStack {
                        Text("Last checked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(lastCheck, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Last checked time
            HStack {
                Text("settings.lastChecked".localized())
                Spacer()
                if let date = proxyManager.lastProxyUpdateCheckDate {
                    Text(date, style: .relative)
                        .foregroundStyle(.secondary)
                } else {
                    Text("settings.never".localized())
                        .foregroundStyle(.secondary)
                }
            }
            
            // Error message
            if let error = upgradeError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Advanced button
            Button {
                showAdvancedSheet = true
            } label: {
                HStack {
                    Label("settings.proxyUpdate.advanced".localized(), systemImage: "gearshape.2")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Label("settings.proxyUpdate".localized(), systemImage: "shippingbox.and.arrow.backward")
        } footer: {
            Text("settings.proxyUpdate.help".localized())
                .font(.caption)
        }
        .sheet(isPresented: $showAdvancedSheet) {
            ProxyVersionManagerSheet()
                .environment(viewModel)
        }
    }
    
    private func checkForUpdate() {
        isCheckingForUpdate = true
        upgradeError = nil

        Task { @MainActor in
            defer {
                // Always reset loading state
                isCheckingForUpdate = false
            }

            await proxyManager.checkForUpgrade()
        }
    }
    
    private func performUpgrade(to version: ProxyVersionInfo) {
        isUpgrading = true
        upgradeError = nil
        
        Task { @MainActor in
            do {
                try await proxyManager.performManagedUpgrade(to: version)
                isUpgrading = false
            } catch {
                upgradeError = proxyManager.errorMessage(for: error)
                isUpgrading = false
            }
        }
    }
}

// MARK: - Proxy Version Manager Sheet

struct ProxyVersionManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProxyScreenModel.self) private var proxyManager
    
    @State private var availableVersions: [ProxyVersionInfo] = []
    @State private var installedVersions: [InstalledProxyVersion] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var installingVersion: String?
    @State private var installError: String?
    
    // State for deletion warning
    @State private var showDeleteWarning = false
    @State private var pendingInstallVersion: ProxyVersionInfo?
    @State private var versionsToDelete: [String] = []
    
    private var installedVersionItems: [NamespacedInstalledVersionItem] {
        installedVersions.map { version in
            NamespacedInstalledVersionItem(id: "installed-\(version.id)", version: version)
        }
    }

    private var availableVersionItems: [NamespacedAvailableVersionItem] {
        availableVersions.map { versionInfo in
            NamespacedAvailableVersionItem(id: "available-\(versionInfo.id)", versionInfo: versionInfo)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("settings.proxyUpdate.advanced.title".localized())
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("settings.proxyUpdate.advanced.description".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Content
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("settings.proxyUpdate.advanced.loading".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text("settings.proxyUpdate.advanced.fetchError".localized())
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("action.refresh".localized()) {
                        Task { await loadReleases() }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Installed Versions Section
                if !installedVersions.isEmpty {
                            sectionHeader("settings.proxyUpdate.advanced.installedVersions".localized())
                            
                            ForEach(installedVersionItems) { item in
                                InstalledVersionRow(
                                    version: item.version,
                                    onActivate: { activateVersion(item.version.version) },
                                    onDelete: { deleteVersion(item.version.version) }
                                )
                                Divider().padding(.leading, 16)
                            }
                        }
                        
                        // Available Versions Section
                        sectionHeader("settings.proxyUpdate.advanced.availableVersions".localized())
                        
                        if availableVersions.isEmpty {
                            HStack {
                                Text("settings.proxyUpdate.advanced.noReleases".localized())
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else {
                            ForEach(availableVersionItems) { item in
                                AvailableVersionRow(
                                    versionInfo: item.versionInfo,
                                    isInstalled: isVersionInstalled(item.versionInfo.version),
                                    isInstalling: installingVersion == item.versionInfo.version,
                                    onInstall: { installVersion(item.versionInfo) }
                                )
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .padding(.bottom)
                }
            }
            
            // Error footer
            if let error = installError {
                Divider()
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        installError = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
            }
        }
        .frame(width: 500, height: 500)
        .task {
            await loadReleases()
        }
        .alert("settings.proxyUpdate.deleteWarning.title".localized(), isPresented: $showDeleteWarning) {
            Button("action.cancel".localized(), role: .cancel) {
                pendingInstallVersion = nil
                versionsToDelete = []
            }
            Button("settings.proxyUpdate.deleteWarning.confirm".localized(), role: .destructive) {
                if let versionInfo = pendingInstallVersion {
                    performInstall(versionInfo)
                }
                pendingInstallVersion = nil
                versionsToDelete = []
            }
        } message: {
            Text(String(format: "settings.proxyUpdate.deleteWarning.message".localized(), AppConstants.maxInstalledVersions, versionsToDelete.joined(separator: ", ")))
        }
    }
    
    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }
    
    private func isVersionInstalled(_ version: String) -> Bool {
        installedVersions.contains { $0.version == version }
    }
    
    private func refreshInstalledVersions() {
        installedVersions = proxyManager.installedVersions
    }
    
    private func loadReleases() async {
        isLoading = true
        loadError = nil
        
        do {
            availableVersions = try await proxyManager.fetchAvailableVersions(limit: 15)
            refreshInstalledVersions()
            isLoading = false
        } catch {
            loadError = proxyManager.errorMessage(for: error)
            isLoading = false
        }
    }
    
    private func installVersion(_ versionInfo: ProxyVersionInfo) {
        Task { @MainActor in
            let toDelete = await proxyManager.versionsToBeDeleted(
                keeping: AppConstants.maxInstalledVersions
            )
            if !toDelete.isEmpty {
                versionsToDelete = toDelete
                pendingInstallVersion = versionInfo
                showDeleteWarning = true
                return
            }

            performInstall(versionInfo)
        }
    }
    
    private func performInstall(_ versionInfo: ProxyVersionInfo) {
        installingVersion = versionInfo.version
        installError = nil
        
        Task { @MainActor in
            do {
                try await proxyManager.performManagedUpgrade(to: versionInfo)
                installingVersion = nil
                refreshInstalledVersions()
            } catch {
                installError = proxyManager.errorMessage(for: error)
                installingVersion = nil
            }
        }
    }
    
    private func activateVersion(_ version: String) {
        Task { @MainActor in
            do {
                try await proxyManager.activateVersion(version)
                refreshInstalledVersions()
            } catch {
                installError = proxyManager.errorMessage(for: error)
            }
        }
    }
    
    private func deleteVersion(_ version: String) {
        Task { @MainActor in
            do {
                try await proxyManager.deleteVersion(version)
                refreshInstalledVersions()
            } catch {
                installError = proxyManager.errorMessage(for: error)
            }
        }
    }
}

private struct NamespacedInstalledVersionItem: Identifiable {
    let id: String
    let version: InstalledProxyVersion
}

private struct NamespacedAvailableVersionItem: Identifiable {
    let id: String
    let versionInfo: ProxyVersionInfo
}

// MARK: - Installed Version Row

private struct InstalledVersionRow: View {
    let version: InstalledProxyVersion
    let onActivate: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Version info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("v\(version.version)")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                    
                    if version.isCurrent {
                        Text("settings.proxyUpdate.advanced.current".localized())
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .clipShape(Capsule())
                    }
                }
                
                Text(version.installedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Actions
            if !version.isCurrent {
                Button("settings.proxyUpdate.advanced.activate".localized()) {
                    onActivate()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Available Version Row

private struct AvailableVersionRow: View {
    let versionInfo: ProxyVersionInfo
    let isInstalled: Bool
    let isInstalling: Bool
    let onInstall: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Version info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("v\(versionInfo.version)")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                    
                    if versionInfo.version.contains("-rc") {
                        Text("settings.proxyUpdate.advanced.prerelease".localized())
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    
                    if isInstalled {
                        Text("settings.proxyUpdate.advanced.installed".localized())
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                
            }
            
            Spacer()
            
            // Install button
            if !isInstalled {
                Button {
                    onInstall()
                } label: {
                    if isInstalling {
                        SmallProgressView()
                    } else {
                        Text("settings.proxyUpdate.advanced.install".localized())
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isInstalling)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Menu Bar Settings Section

struct MenuBarSettingsSection: View {
    @Environment(QuotaFeatureController.self) private var viewModel
    @Environment(MenuBarSettingsManager.self) private var settings
    @Environment(SettingsScreenModel.self) private var settingsModel
    @State private var showTruncationAlert = false
    @State private var pendingMaxItems: Int?
    
    private var showMenuBarIconBinding: Binding<Bool> {
        Binding(
            get: { settings.showMenuBarIcon },
            set: { newValue in
                // Prevent disabling both dock and menu bar icon (user would have no way to access app)
                if !newValue && !settingsModel.appShellPreferences.showInDock {
                    // Re-enable dock if user tries to disable menu bar icon while dock is already disabled
                    settingsModel.setShowInDock(true)
                }
                settings.showMenuBarIcon = newValue
            }
        )
    }

    private var showQuotaBinding: Binding<Bool> {
        Binding(
            get: { settings.showQuotaInMenuBar },
            set: { settings.showQuotaInMenuBar = $0 }
        )
    }
    
    private var colorModeBinding: Binding<MenuBarColorMode> {
        Binding(
            get: { settings.colorMode },
            set: { settings.colorMode = $0 }
        )
    }

    private var stackPairedQuotaMetricsBinding: Binding<Bool> {
        Binding(
            get: { settings.stackPairedQuotaMetrics },
            set: { settings.stackPairedQuotaMetrics = $0 }
        )
    }
    
    private var maxItemsBinding: Binding<Int> {
        Binding(
            get: { settings.menuBarMaxItems },
            set: { newValue in
                let clamped = min(max(newValue, MenuBarSettingsManager.minMenuBarItems), MenuBarSettingsManager.maxMenuBarItems)

                // Check if reducing max items would truncate current selection
                if clamped < settings.menuBarMaxItems && settings.currentItems.count > clamped {
                    pendingMaxItems = clamped
                    showTruncationAlert = true
                } else {
                    settings.menuBarMaxItems = clamped
                    viewModel.synchronizeMenuBarSelection()
                }
            }
        )
    }
    
    var body: some View {
        Section {
            Toggle("settings.menubar.showIcon".localized(), isOn: showMenuBarIconBinding)
            
            if settings.showMenuBarIcon {
                Toggle("settings.menubar.showQuota".localized(), isOn: showQuotaBinding)
                
                if settings.showQuotaInMenuBar {
                    Toggle(
                        "settings.menubar.stackPairedQuotaMetrics".localized(),
                        isOn: stackPairedQuotaMetricsBinding
                    )

                    HStack {
                        Text("settings.menubar.maxItems".localized())
                        Spacer()
                        Text("\(settings.menuBarMaxItems)")
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                        Stepper(
                            "",
                            value: maxItemsBinding,
                            in: MenuBarSettingsManager.minMenuBarItems...MenuBarSettingsManager.maxMenuBarItems,
                            step: 1
                        )
                        .labelsHidden()
                    }
                    
                    Picker("settings.menubar.colorMode".localized(), selection: colorModeBinding) {
                        Text("settings.menubar.colored".localized()).tag(MenuBarColorMode.colored)
                        Text("settings.menubar.monochrome".localized()).tag(MenuBarColorMode.monochrome)
                    }
                    .pickerStyle(.segmented)
                }
            }
        } header: {
            Label("settings.menubar".localized(), systemImage: "menubar.rectangle")
        } footer: {
            Text(String(
                format: "settings.menubar.help".localized(),
                settings.menuBarMaxItems
            ))
            .font(.caption)
        }
        .alert("menubar.truncation.title".localized(), isPresented: $showTruncationAlert) {
            Button("action.cancel".localized(), role: .cancel) {
                pendingMaxItems = nil
            }
            Button("action.ok".localized(), role: .destructive) {
                if let newMax = pendingMaxItems {
                    settings.menuBarMaxItems = newMax
                    viewModel.synchronizeMenuBarSelection()
                    pendingMaxItems = nil
                }
            }
        } message: {
            if let newMax = pendingMaxItems {
                Text(String(
                    format: "menubar.truncation.message".localized(),
                    settings.currentItems.count,
                    newMax
                ))
            }
        }
    }
}

// MARK: - Appearance Settings Section

struct AppearanceSettingsSection: View {
    @Environment(AppearanceManager.self) private var appearanceManager
    
    private var appearanceModeBinding: Binding<AppearanceMode> {
        Binding(
            get: { appearanceManager.appearanceMode },
            set: { appearanceManager.appearanceMode = $0 }
        )
    }
    
    var body: some View {
        Section {
            Picker("settings.appearance.mode".localized(), selection: appearanceModeBinding) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.localizationKey.localized(), systemImage: mode.icon)
                        .tag(mode)
                }
            }
        } header: {
            Label("settings.appearance.title".localized(), systemImage: "paintbrush")
        } footer: {
            Text("settings.appearance.help".localized())
                .font(.caption)
        }
    }
}

// MARK: - Privacy Settings Section

struct PrivacySettingsSection: View {
    @Environment(MenuBarSettingsManager.self) private var settings
    @Environment(TelemetryConsentScreenModel.self) private var telemetryModel
    
    private var hideSensitiveBinding: Binding<Bool> {
        Binding(
            get: { settings.hideSensitiveInfo },
            set: { settings.hideSensitiveInfo = $0 }
        )
    }

    private var shareAnonymousUsageBinding: Binding<Bool> {
        Binding(
            get: { telemetryModel.preferences.shareAnonymousUsage },
            set: { telemetryModel.setConsent($0) }
        )
    }
    
    var body: some View {
        Section {
            Toggle("settings.privacy.hideSensitive".localized(), isOn: hideSensitiveBinding)
            Toggle("settings.privacy.shareAnonymousUsage".localized(), isOn: shareAnonymousUsageBinding)
        } header: {
            Label("settings.privacy".localized(), systemImage: "eye.slash")
        } footer: {
            Text("settings.privacy.help".localized())
                .font(.caption)
        }
    }
}

struct GeneralSettingsTab: View {
    @Environment(SettingsScreenModel.self) private var settingsModel
    @Environment(LanguageManager.self) private var languageManager

    private var autoStartProxyBinding: Binding<Bool> {
        Binding(
            get: { settingsModel.proxyPreferences.autoStartProxy },
            set: { settingsModel.setAutoStartProxy($0) }
        )
    }
    
    var body: some View {
        @Bindable var lang = languageManager
        
        Form {
            Section {
                LaunchAtLoginToggle()
                
                Toggle("settings.autoStartProxy".localized(), isOn: autoStartProxyBinding)
            } header: {
                Label("settings.startup".localized(), systemImage: "power")
            }
            
            Section {
                Picker(selection: Binding(
                    get: { lang.currentLanguage },
                    set: { lang.setLanguage($0) }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        HStack {
                            Text(language.flag)
                            Text(language.displayName)
                        }
                        .tag(language)
                    }
                } label: {
                    Label("settings.language".localized(), systemImage: "globe")
                }
            } header: {
                Label("settings.language".localized(), systemImage: "globe")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            
            Text("Quotio")
                .font(.title)
                .fontWeight(.bold)
            
            Text("CLIProxyAPI GUI Wrapper")
                .foregroundStyle(.secondary)
            
            Text("Version 1.0")
                .font(.caption)
                .foregroundStyle(.tertiary)
            
            Link("GitHub: CLIProxyAPI", destination: URL(string: "https://github.com/router-for-me/CLIProxyAPI")!)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - About Screen (New Full-Page Version)

struct ManagementKeyRow: View {
    @Environment(ProxyManagementScreenModel.self) private var viewModel
    @Environment(MenuBarSettingsManager.self) private var settings
    @Environment(PasteboardScreenModel.self) private var pasteboard
    @State private var regenerateError: String?
    @State private var showRegenerateConfirmation = false
    @State private var showCopyConfirmation = false
    
    private var displayKey: String {
        if settings.hideSensitiveInfo {
            let key = viewModel.proxy.managementKey
            return String(repeating: "•", count: 8) + "..." + key.suffix(4)
        }
        return viewModel.proxy.managementKey
    }
    
    var body: some View {
        LabeledContent("settings.managementKey".localized()) {
            HStack(spacing: 8) {
                Text(displayKey)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                
                Button {
                    pasteboard.copy(viewModel.proxy.managementKey)
                    showCopyConfirmation = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        showCopyConfirmation = false
                    }
                } label: {
                    Image(systemName: showCopyConfirmation ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .frame(width: 14, height: 14)
                        .foregroundStyle(showCopyConfirmation ? .green : .primary)
                        .modifier(SymbolEffectTransitionModifier())
                }
                .buttonStyle(.borderless)
                .help("action.copy".localized())
                
                Button {
                    showRegenerateConfirmation = true
                } label: {
                    if viewModel.proxy.isRegeneratingKey {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.proxy.isRegeneratingKey)
                .help("settings.managementKey.regenerate".localized())
            }
        }
        .confirmationDialog(
            "settings.managementKey.regenerate.title".localized(),
            isPresented: $showRegenerateConfirmation,
            titleVisibility: .visible
        ) {
            Button("settings.managementKey.regenerate.confirm".localized(), role: .destructive) {
                Task {
                    regenerateError = nil
                    do {
                        try await viewModel.proxy.regenerateManagementKey()
                    } catch {
                        regenerateError = viewModel.proxy.errorMessage(for: error)
                    }
                }
            }
            Button("action.cancel".localized(), role: .cancel) {}
        } message: {
            Text("settings.managementKey.regenerate.warning".localized())
        }
        .alert("Error".localized(), isPresented: .init(
            get: { regenerateError != nil },
            set: { if !$0 { regenerateError = nil } }
        )) {
            Button("OK".localized()) { regenerateError = nil }
        } message: {
            Text(regenerateError ?? "")
        }
    }
}

// MARK: - Launch at Login Toggle

/// Reusable toggle component for Launch at Login functionality
struct LaunchAtLoginToggle: View {
    @Environment(LaunchAtLoginScreenModel.self) private var launchModel
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showLocationWarning = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("settings.launchAtLogin".localized(), isOn: Binding(
                get: { launchModel.snapshot.status.isEnabled },
                set: { newValue in
                    if !launchModel.setEnabled(newValue) {
                        errorMessage = launchModel.errorMessage ?? ""
                        showError = true
                    }
                    showLocationWarning = newValue && !launchModel.snapshot.isInApplicationsFolder
                }
            ))
            
            // Show location warning inline
            if showLocationWarning {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text("launchAtLogin.warning.notInApplications".localized())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 2)
            }
        }
        .onAppear {
            // Refresh status when view appears to sync with System Settings
            launchModel.refresh()
        }
        .alert("launchAtLogin.error.title".localized(), isPresented: $showError) {
            Button("OK".localized()) { showError = false }
            Button("launchAtLogin.openSystemSettings".localized()) {
                launchModel.openSystemSettings()
                showError = false
            }
        } message: {
            Text(errorMessage)
        }
    }
}

// MARK: - Usage Display Settings Section

struct UsageDisplaySettingsSection: View {
    @Environment(MenuBarSettingsManager.self) private var settings
    
    private var totalUsageModeBinding: Binding<TotalUsageMode> {
        Binding(
            get: { settings.totalUsageMode },
            set: { settings.totalUsageMode = $0 }
        )
    }
    
    private var modelAggregationModeBinding: Binding<ModelAggregationMode> {
        Binding(
            get: { settings.modelAggregationMode },
            set: { settings.modelAggregationMode = $0 }
        )
    }
    
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("settings.usageDisplay.totalMode.title".localized())
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Picker("", selection: totalUsageModeBinding) {
                    ForEach(TotalUsageMode.allCases) { mode in
                        Text(mode.localizationKey.localized()).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                
                Text("settings.usageDisplay.totalMode.description".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("settings.usageDisplay.modelAggregation.title".localized())
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Picker("", selection: modelAggregationModeBinding) {
                    ForEach(ModelAggregationMode.allCases) { mode in
                        Text(mode.localizationKey.localized()).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                
                Text("settings.usageDisplay.modelAggregation.description".localized())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Label("settings.usageDisplay.title".localized(), systemImage: "chart.bar.doc.horizontal")
        } footer: {
            Text("settings.usageDisplay.description".localized())
                .font(.caption)
        }
    }
}
