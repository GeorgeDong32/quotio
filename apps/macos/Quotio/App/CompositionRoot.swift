import AppKit
import Foundation
import SwiftUI
import QuotioApplication
import QuotioDomain
import QuotioForkExtras
import QuotioInfrastructure
import QuotioPresentation

enum AppEnvironment {
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

@MainActor
enum CompositionRoot {
    static func makeProduction() -> AppRuntime {
        if !AppEnvironment.isRunningUnitTests {
            AppIdentity.migrateLegacyUserDefaults()
        }

        let customProviderRepository = UserDefaultsCustomProviderRepository()
        let customProviderTransport = URLSessionCustomProviderTransport()
        let customProviderService = QuotioApplication.CustomProviderService(
            repository: customProviderRepository,
            discovery: customProviderTransport,
            connectionTester: customProviderTransport,
            configurationSynchronizer: FileCustomProviderConfigurationSynchronizer()
        )
        let urlOpener = WorkspaceURLOpener()
        let applicationPlatform = AppKitApplicationPlatformAdapter()
        let pasteboard = PasteboardScreenModel(writer: MacOSPasteboardAdapter())
        let legacyYubiKey = LegacyYubiKeyCredentialReader()
        let languageManager = LanguageManager(
            repository: UserDefaultsLanguagePreferencesRepository()
        )
        let proxyPreferences = UserDefaultsProxyPreferencesRepository()
        let notificationController = NotificationController(
            repository: UserDefaultsNotificationPreferencesRepository(),
            delivery: UserNotificationCenterAdapter { [languageManager] key in
                languageManager.localized(key)
            }
        )
        let paths = FileProxyConfigurationRepository.defaultPaths()
        let configurationRepository = FileProxyConfigurationRepository(paths: paths)
        // Fork: bridge mode — the proxy binary binds the internal port while
        // ProxyBridge owns the user port and applies fallback routing.
        let proxyController = ProxyLifecycleController(
            paths: paths,
            processController: ProxyProcessController(),
            versionRepository: ForkProxyVersionRepository(
                upstreamRepository: FileProxyVersionRepository()
            ),
            releaseRepository: GitHubProxyReleaseRepository(),
            updateFeed: GitHubAtomProxyUpdateFeed(),
            configurationRepository: configurationRepository,
            binaryDownloader: URLSessionProxyBinaryDownloader(),
            checksumVerifier: SHA256ProxyChecksumVerifier(),
            managementChecker: LocalProxyManagementClient(),
            metadataRepository: BridgePortMetadataRepository(
                wrapping: UserDefaultsProxyRuntimeMetadataRepository(),
                offset: FallbackProxyLifecycleCoordinator.portOffset
            ),
            preferencesRepository: UserDefaultsProxyPreferencesRepository(),
            keyVault: ProxyManagementKeyVaultAdapter(
                dataStore: KeychainCredentialDataStore(
                    service: AppIdentity.keychainService(suffix: "local-management"),
                    legacyServices: AppIdentity.legacyKeychainServices(suffix: "local-management"),
                    canMigrateLegacy: AppIdentity.isProduction,
                    legacyProtectedStore: legacyYubiKey
                )
            ),
            configurationSupplement: CustomProviderConfigurationSupplement(
                service: customProviderService
            ),
            notificationDelivery: ProxyNotificationRelay(notifications: notificationController),
            sleeper: ContinuousSleeper(),
            dateProvider: SystemDateProvider(),
            installedVersionLimit: AppConstants.maxInstalledVersions
        )
        // Fork upgrade path: pre-port installs ran the bridge on 8080 (the
        // fork default) without persisting `proxyPort`. Seed it so upgraded
        // agents keep their endpoints; fresh installs have no config.yaml yet.
        if UserDefaults.standard.object(forKey: "proxyPort") == nil,
           FileManager.default.fileExists(atPath: paths.configPath) {
            UserDefaults.standard.set(8080, forKey: "proxyPort")
        }
        let userProxyPort = UserDefaultsProxyRuntimeMetadataRepository().loadPort()
        let proxyBridge = ProxyBridge()
        // Fork: request logging — bridge completions feed the fork tracker.
        proxyBridge.onRequestCompleted = { metadata in
            Task { @MainActor in
                RequestTracker.shared.addRequest(from: metadata)
            }
        }
        // Start the tracker with the app (the fork started it with the proxy;
        // without this, history only loads when the logs page first opens).
        RequestTracker.shared.start()
        let proxyCoordinator = FallbackProxyLifecycleCoordinator(
            controller: proxyController,
            bridge: proxyBridge,
            userPort: userProxyPort
        )
        let proxyScreenModel = ProxyScreenModel(
            controller: proxyCoordinator,
            initialState: ProxySnapshot(
                status: ProxyStatus(
                    port: userProxyPort
                ),
                paths: paths
            )
        )

        let authFileState = UserDefaultsManagedAuthFileStateRepository()
        let providerTrackingRepository = UserDefaultsProviderTrackingPreferencesRepository()
        let quotioBackend = QuotioCLIBackend(
            logger: OSApplicationLogger(subsystem: AppIdentity.bundleIdentifier, category: "NativeQuota"),
            localization: { (languageManager.bundle, languageManager.locale) }
        )
        let quotioServer = QuotioCLIServerProcess(
            proxyAuthDirectory: URL(fileURLWithPath: paths.authDirectoryPath, isDirectory: true),
            initialPreferences: {
                (providerTrackingRepository.load(), UserDefaultsRefreshPreferencesRepository().load(), authFileState.disabledAuthFileNames())
            },
            applicationSupportDirectoryName: AppIdentity.bundleIdentifier,
            accountVaultNamespace: AppIdentity.quotioCLIVaultNamespace()
        )
        let reconnectQuotioServer: @MainActor @Sendable () async -> Bool = {
            await quotioBackend.disconnect()
            guard let connection = try? await quotioServer.start() else { return false }
            await quotioBackend.connect(connection)
            return true
        }
        quotioServer.onUnexpectedTermination = {
            Task {
                for delay in [1, 2, 4] {
                    try? await Task.sleep(for: .seconds(delay))
                    if await reconnectQuotioServer() { return }
                }
            }
        }
        let accountsScreenModel = AccountsScreenModel(
            accountService: quotioBackend
        )

        let monitorAuthorizer = QuotioCLIOAuthAuthorizer(
            backend: quotioBackend,
            urlOpener: urlOpener
        )
        let modeManager = OperatingModeManager(
            repository: UserDefaultsOperatingModePreferencesRepository()
        )
        let oauthScreenModel = OAuthScreenModel(
            controller: OAuthFlowController(authorizer: monitorAuthorizer)
        )

        let quotaScreenModel = QuotaScreenModel(
            coordinator: quotioBackend
        )
        let menuBarSettings = MenuBarSettingsManager(
            repository: UserDefaultsMenuBarPreferencesRepository()
        )
        let quotaController = QuotaFeatureController(
            quota: quotaScreenModel,
            accounts: accountsScreenModel,
            oauth: oauthScreenModel,
            modeManager: modeManager,
            monitoringSettings: quotioBackend,
            menuBarSettings: menuBarSettings,
            notifications: notificationController
        )
        oauthScreenModel.setSuccessHandler { [weak quotaController] in
            await quotaController?.refreshAll(force: true)
        }

        let updatePreferences = UserDefaultsUpdatePreferencesRepository()
        // Fork: auto-update removed — no-op checker instead of Sparkle.
        let applicationUpdateController = ApplicationUpdateController(
            checker: NoOpApplicationUpdateChecker(),
            preferencesRepository: updatePreferences,
            icon: AppKitUpdaterIconAdapter()
        )
        let applicationUpdateModel = ApplicationUpdateScreenModel(
            controller: applicationUpdateController
        )
        let notificationSettingsModel = NotificationSettingsScreenModel(
            controller: notificationController
        )
        // Fork: telemetry removed — no-op tracker instead of PostHog.
        let telemetryController = TelemetryController(
            repository: UserDefaultsTelemetryPreferencesRepository(),
            tracker: NoOpTelemetryTracker(),
            contextProvider: BundleTelemetryRuntimeContextProvider(),
            updatePreferencesRepository: updatePreferences
        )
        let telemetryConsentModel = TelemetryConsentScreenModel(controller: telemetryController)
        let legacyMigration = QuotioCLILegacyAccountMigration(
            credentials: KeychainCredentialDataStore(
                service: AppIdentity.keychainService(suffix: "monitor-auth"),
                legacyServices: AppIdentity.legacyKeychainServices(suffix: "monitor-auth"),
                canMigrateLegacy: AppIdentity.isProduction,
                legacyProtectedStore: legacyYubiKey
            ),
            codexKeychain: ExternalKeychainCredentialReader(),
            importAccount: { account, credential, disabled in
                try await quotioBackend.importLegacyAccount(account, credential: credential, disabled: disabled)
            }
        )
        let credentialMigrationModel = CredentialMigrationScreenModel {
            let result = await legacyMigration.migrate()
            await accountsScreenModel.reloadAccounts()
            return result
        }
        let launchAtLoginController = LaunchAtLoginController(
            registration: ServiceManagementLaunchAtLoginAdapter(),
            urlOpener: urlOpener
        )
        let launchAtLoginModel = LaunchAtLoginScreenModel(
            controller: launchAtLoginController,
            failureMessage: { failure in
                switch failure {
                case .registrationFailed(let reason):
                    "launchAtLogin.error.registrationFailed".localized() + ": \(reason)"
                case .unregistrationFailed(let reason):
                    "launchAtLogin.error.unregistrationFailed".localized() + ": \(reason)"
                @unknown default:
                    "launchAtLogin.error.registrationFailed".localized()
                }
            }
        )
        let platformActions = PlatformActionScreenModel(urlOpener: urlOpener)
        let appearanceManager = AppearanceManager(
            repository: UserDefaultsAppearancePreferencesRepository(),
            platform: applicationPlatform
        )
        let settingsScreenModel = SettingsScreenModel(
            proxyRepository: proxyPreferences,
            tunnelRepository: UserDefaultsTunnelPreferencesRepository(),
            appShellRepository: UserDefaultsAppShellPreferencesRepository(),
            applyAutomaticUpdateChecks: { [applicationUpdateController] enabled in
                applicationUpdateController.automaticallyChecksForUpdates = enabled
            },
            applyDockVisibility: { [applicationPlatform] enabled in
                applicationPlatform.setDockVisibility(enabled)
            },
            reloadQuotaNetwork: { _ = await reconnectQuotioServer() }
        )
        let providerImageCache = ProviderImageCacheAdapter()
        let providerImageModel = ProviderImageScreenModel(
            loadImage: { [providerImageCache] name, size in
                providerImageCache.image(named: name, size: size)
            }
        )
        let statusBarManager = StatusBarManager()
        // Fork: fallback screen model + fork page registration.
        let fallbackScreenModel = FallbackScreenModel(
            baseURLProvider: { [weak proxyScreenModel] in proxyScreenModel?.baseURL ?? "" },
            configPathProvider: { paths.configPath }
        )
        ForkPageRegistry.providers[.fallback] = { AnyView(FallbackScreen()) }
        ForkPageRegistry.providers[.requestLogs] = { AnyView(RequestLogsScreen()) }
        ForkPageRegistry.providers[.remoteConnection] = { AnyView(RemoteConnectionScreen()) }
        // Shared management client source: local proxy first, then the
        // saved remote connection (used by the API Keys and Gemini pages).
        let managementAPIClient: @MainActor () -> (any ProxyManagementAPI)? = { [weak proxyScreenModel] in
            if let proxyScreenModel, proxyScreenModel.proxyStatus.running {
                return URLSessionProxyManagementAPI(connection: ProxyManagementConnection(
                    baseURL: proxyScreenModel.managementURL,
                    authKey: proxyScreenModel.managementKey
                ))
            }
            if let config = ForkRemoteConnectionManager.loadSavedConfig(),
               let key = ForkRemoteConnectionManager.savedManagementKey() {
                return URLSessionProxyManagementAPI(connection: ProxyManagementConnection(
                    baseURL: config.managementBaseURL,
                    authKey: key
                ))
            }
            return nil
        }
        let apiKeysScreenModel = APIKeysScreenModel(apiClientProvider: managementAPIClient)
        ForkPageRegistry.providers[.apiKeys] = { AnyView(APIKeysScreen().environment(apiKeysScreenModel)) }
        let services = ProductionAppRuntimeServices(
            quotaController: quotaController,
            proxyScreenModel: proxyScreenModel,
            fallbackScreenModel: fallbackScreenModel,
            quotaScreenModel: quotaScreenModel,
            accountsScreenModel: accountsScreenModel,
            navigationScreenModel: NavigationScreenModel(),
            pasteboard: pasteboard,
            providerImageModel: providerImageModel,
            platformActions: platformActions,
            settingsScreenModel: settingsScreenModel,
            modeManager: modeManager,
            appearanceManager: appearanceManager,
            statusBarManager: statusBarManager,
            menuBarSettings: menuBarSettings,
            languageManager: languageManager,
            launchAtLoginModel: launchAtLoginModel,
            notificationSettingsModel: notificationSettingsModel,
            telemetryConsentModel: telemetryConsentModel,
            applicationUpdateModel: applicationUpdateModel,
            credentialMigrationModel: credentialMigrationModel,
            notificationController: notificationController,
            telemetryController: telemetryController,
            applicationUpdateController: applicationUpdateController,
            applicationPlatform: applicationPlatform,
            quotioServer: quotioServer,
            quotioBackend: quotioBackend,
            reconnectQuotioServer: reconnectQuotioServer
        )
        return AppRuntime(services: services)
    }
}

private struct CustomProviderConfigurationSupplement: ProxyConfigurationSupplementing {
    private let service: QuotioApplication.CustomProviderService

    init(service: QuotioApplication.CustomProviderService) {
        self.service = service
    }

    func synchronize(configurationPath: String) async {
        try? service.synchronizeConfiguration(at: configurationPath)
    }
}

@MainActor
private final class ProductionAppRuntimeServices: AppRuntimeServices {
    let quotaController: QuotaFeatureController
    let proxyScreenModel: ProxyScreenModel
    let fallbackScreenModel: FallbackScreenModel
    let quotaScreenModel: QuotaScreenModel
    let accountsScreenModel: AccountsScreenModel
    let navigationScreenModel: NavigationScreenModel
    let pasteboard: PasteboardScreenModel
    let providerImageModel: ProviderImageScreenModel
    let platformActions: PlatformActionScreenModel
    let settingsScreenModel: SettingsScreenModel
    let modeManager: OperatingModeManager
    let appearanceManager: AppearanceManager
    let statusBarManager: StatusBarManager
    let menuBarSettings: MenuBarSettingsManager
    let languageManager: LanguageManager
    let launchAtLoginModel: LaunchAtLoginScreenModel
    let notificationSettingsModel: NotificationSettingsScreenModel
    let telemetryConsentModel: TelemetryConsentScreenModel
    let applicationUpdateModel: ApplicationUpdateScreenModel
    let credentialMigrationModel: CredentialMigrationScreenModel

    private let notificationController: NotificationController
    private let telemetryController: TelemetryController
    private let applicationUpdateController: ApplicationUpdateController
    private let applicationPlatform: AppKitApplicationPlatformAdapter
    private let quotioServer: QuotioCLIServerProcess
    private let quotioBackend: QuotioCLIBackend
    private let reconnectQuotioServer: @MainActor @Sendable () async -> Bool

    var hasCompletedOnboarding: Bool { modeManager.hasCompletedOnboarding }
    var showInDock: Bool { settingsScreenModel.appShellPreferences.showInDock }
    var canCheckForUpdates: Bool { applicationUpdateModel.snapshot.canCheck }

    init(
        quotaController: QuotaFeatureController,
        proxyScreenModel: ProxyScreenModel,
        fallbackScreenModel: FallbackScreenModel,
        quotaScreenModel: QuotaScreenModel,
        accountsScreenModel: AccountsScreenModel,
        navigationScreenModel: NavigationScreenModel,
        pasteboard: PasteboardScreenModel,
        providerImageModel: ProviderImageScreenModel,
        platformActions: PlatformActionScreenModel,
        settingsScreenModel: SettingsScreenModel,
        modeManager: OperatingModeManager,
        appearanceManager: AppearanceManager,
        statusBarManager: StatusBarManager,
        menuBarSettings: MenuBarSettingsManager,
        languageManager: LanguageManager,
        launchAtLoginModel: LaunchAtLoginScreenModel,
        notificationSettingsModel: NotificationSettingsScreenModel,
        telemetryConsentModel: TelemetryConsentScreenModel,
        applicationUpdateModel: ApplicationUpdateScreenModel,
        credentialMigrationModel: CredentialMigrationScreenModel,
        notificationController: NotificationController,
        telemetryController: TelemetryController,
        applicationUpdateController: ApplicationUpdateController,
        applicationPlatform: AppKitApplicationPlatformAdapter,
        quotioServer: QuotioCLIServerProcess,
        quotioBackend: QuotioCLIBackend,
        reconnectQuotioServer: @escaping @MainActor @Sendable () async -> Bool
    ) {
        self.quotaController = quotaController
        self.proxyScreenModel = proxyScreenModel
        self.fallbackScreenModel = fallbackScreenModel
        self.quotaScreenModel = quotaScreenModel
        self.accountsScreenModel = accountsScreenModel
        self.navigationScreenModel = navigationScreenModel
        self.pasteboard = pasteboard
        self.providerImageModel = providerImageModel
        self.platformActions = platformActions
        self.settingsScreenModel = settingsScreenModel
        self.modeManager = modeManager
        self.appearanceManager = appearanceManager
        self.statusBarManager = statusBarManager
        self.menuBarSettings = menuBarSettings
        self.languageManager = languageManager
        self.launchAtLoginModel = launchAtLoginModel
        self.notificationSettingsModel = notificationSettingsModel
        self.telemetryConsentModel = telemetryConsentModel
        self.applicationUpdateModel = applicationUpdateModel
        self.credentialMigrationModel = credentialMigrationModel
        self.notificationController = notificationController
        self.telemetryController = telemetryController
        self.applicationUpdateController = applicationUpdateController
        self.applicationPlatform = applicationPlatform
        self.quotioServer = quotioServer
        self.quotioBackend = quotioBackend
        self.reconnectQuotioServer = reconnectQuotioServer
    }

    func prepareForLaunch() {
        telemetryController.prepareForLaunch()
        Task { [notificationController] in
            await notificationController.requestAuthorization()
        }
    }

    func applyAppearance() {
        appearanceManager.applyAppearance()
    }

    func connectStatusBar() {
        let windowPresenter = AppKitWindowPresenter()
        let dispatcher = StatusBarCommandDispatcher(
            handlers: StatusBarCommandHandlers(
                refreshAll: { [quotaController] in
                    await quotaController.refreshAll(force: true)
                },
                refreshProvider: { [quotaController] provider in
                    await quotaController.refresh(provider: provider)
                },
                refreshAccount: { [quotaController] account in
                    await quotaController.refresh(account: account)
                },
                selectProvider: { [menuBarSettings] provider in
                    menuBarSettings.selectProvider(provider)
                },
                openApp: { [weak statusBarManager, settingsScreenModel, windowPresenter, navigationScreenModel] in
                    if settingsScreenModel.appShellPreferences.showInDock {
                        statusBarManager?.closeMenu()
                    }
                    navigationScreenModel.currentPage = .general
                    windowPresenter.showMainWindow()
                },
                quit: { [applicationPlatform] in
                    applicationPlatform.terminate()
                },
                menuNeedsRebuild: { [weak statusBarManager] in
                    statusBarManager?.rebuildMenuInPlace()
                }
            )
        )
        statusBarManager.configureMenu(
            snapshotProvider: { [weak self] in
                guard let self else {
                    preconditionFailure("Status bar outlived application services")
                }
                return self.statusBarMenuSnapshot
            },
            commandDispatcher: dispatcher
        )
    }

    func setStatusBarStateChangeHandler(_ handler: (@MainActor () -> Void)?) {
        quotaController.setDidChangeHandler(handler)
        quotaScreenModel.setDidChangeHandler { _ in handler?() }
        menuBarSettings.setDidChangeHandler { _ in handler?() }
        modeManager.setDidChangeHandler { _ in handler?() }
        appearanceManager.setDidChangeHandler { _ in handler?() }
        languageManager.setDidChangeHandler { _ in handler?() }
    }

    func updateStatusBar() {
        statusBarManager.updateStatusBar(
            items: quotaItems,
            colorMode: menuBarSettings.colorMode,
            quotaDisplayMode: menuBarSettings.quotaDisplayMode,
            isRunning: !quotaScreenModel.providerQuotas.isEmpty,
            showMenuBarIcon: menuBarSettings.showMenuBarIcon,
            showQuota: menuBarSettings.showQuotaInMenuBar,
            appearanceMode: appearanceManager.appearanceMode,
            language: languageManager.currentLanguage
        )
    }

    func rebuildStatusBar() {
        statusBarManager.rebuildMenuInPlace()
    }

    func initializeFeatures() async {
        await proxyScreenModel.initialize(autoStart: settingsScreenModel.proxyPreferences.autoStartProxy)
        if await reconnectQuotioServer() {
            await credentialMigrationModel.migrate()
        }
        await quotaController.initialize()
    }

    func checkForUpdatesInBackground() {
        applicationUpdateController.checkForUpdatesInBackground()
    }

    func checkForUpdates() {
        applicationUpdateController.checkForUpdates()
    }

    func shutdownOAuth() async {
        await proxyScreenModel.shutdown()
        await quotaController.shutdown()
        await quotioBackend.disconnect()
        await quotioServer.stop()
    }

    private var statusBarMenuSnapshot: StatusBarMenuSnapshot {
        StatusBarMenuSnapshotMapper.makeSnapshot(
            monitorAccounts: accountsScreenModel.accounts,
            quota: quotaScreenModel.state,
            menuBarPreferences: menuBarSettings.preferences,
            appearanceMode: appearanceManager.appearanceMode,
            language: languageManager.currentLanguage,
            trackingPreferences: quotaController.trackingPreferences
        )
    }

    private var quotaItems: [MenuBarQuotaDisplayItem] {
        guard menuBarSettings.showQuotaInMenuBar else { return [] }

        return menuBarSettings.selectedItems.compactMap { selectedItem in
            guard selectedItem.hostID == quotaScreenModel.state.hostID,
                  let provider = selectedItem.aiProvider,
                  quotaController.trackingPreferences.isEnabled(provider) else { return nil }

            var displayPercent: Double = -1
            var isForbidden = false
            var quotaPair: MenuBarQuotaPair?

            let account = accountsScreenModel.accounts.first {
                $0.providerID.rawValue == provider.rawValue && $0.accountKey == selectedItem.accountKey
            }
            let quotaData = quotaScreenModel.providerQuotas[provider]?[selectedItem.accountKey]
            guard account?.isDisabled != true, account != nil || quotaData != nil else { return nil }
            if let quotaData {
                isForbidden = quotaData.isForbidden
                if !quotaData.models.isEmpty {
                    displayPercent = menuBarSettings.totalUsagePercent(summary: quotaData.summary)
                    if menuBarSettings.stackPairedQuotaMetrics {
                        quotaPair = MenuBarQuotaPair.resolve(from: quotaData.summary)
                    }
                }
            }

            return MenuBarQuotaDisplayItem(
                id: selectedItem.id,
                providerSymbol: provider.menuBarSymbol,
                accountShort: selectedItem.accountKey,
                percentage: displayPercent,
                provider: provider,
                isForbidden: isForbidden,
                quotaPair: quotaPair
            )
        }
    }
}
