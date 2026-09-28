import XCTest
@testable import QuotioDomain

final class PreferenceValuesTests: XCTestCase {
    func testProviderTrackingDefaultsToEnabledAndCanBeRestored() {
        var preferences = ProviderTrackingPreferences()
        XCTAssertTrue(preferences.isEnabled(.claude))
        preferences.disabledProviders.insert(.claude)
        XCTAssertFalse(preferences.isEnabled(.claude))
        XCTAssertTrue(preferences.isEnabled(.codex))
        preferences.disabledProviders.remove(.claude)
        XCTAssertTrue(preferences.isEnabled(.claude))
    }

    func testLegacyOperatingModesMapToSupportedModes() {
        XCTAssertEqual(OperatingMode.fromLegacy(appModeRaw: nil, connectionModeRaw: nil), .monitor)
        XCTAssertEqual(OperatingMode.fromLegacy(appModeRaw: "quotaOnly", connectionModeRaw: nil), .monitor)
        XCTAssertEqual(OperatingMode.fromLegacy(appModeRaw: "full", connectionModeRaw: "remote"), .monitor)
        XCTAssertEqual(OperatingMode.fromLegacy(appModeRaw: "full", connectionModeRaw: "local"), .monitor)
        XCTAssertEqual(OperatingMode.fromLegacy(appModeRaw: "unknown", connectionModeRaw: "local"), .monitor)
    }

    func testPreferenceDefaultsMatchExistingApplicationBehavior() {
        XCTAssertEqual(OperatingModePreferences(), OperatingModePreferences(mode: .monitor))
        XCTAssertEqual(RefreshPreferences().cadence, .tenMinutes)
        XCTAssertEqual(AppearancePreferences().mode, .system)
        XCTAssertEqual(LanguagePreferences().language, .english)
        XCTAssertEqual(UpdatePreferences().channel, .stable)
        XCTAssertEqual(NotificationPreferences().quotaAlertThreshold, 20)
        XCTAssertTrue(NotificationPreferences().notificationsEnabled)
        XCTAssertTrue(AppShellPreferences().autoCheckUpdates)
        XCTAssertTrue(AppShellPreferences().showInDock)
        XCTAssertTrue(ProxyPreferences().loggingToFile)
        XCTAssertFalse(AppShellPreferences().hideGettingStarted)
    }

    func testQuotaDisplayModeClampsValuesAndPreservesUnavailableSentinel() {
        XCTAssertEqual(QuotaDisplayMode.used.displayValue(from: 25), 75)
        XCTAssertEqual(QuotaDisplayMode.remaining.displayValue(from: 125), 100)
        XCTAssertEqual(QuotaDisplayMode.remaining.displayValue(from: -1), -1)
    }
}
