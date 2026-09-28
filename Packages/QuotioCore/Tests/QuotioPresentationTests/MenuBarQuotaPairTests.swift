import AppKit
import QuotioDomain
import SwiftUI
import XCTest
@testable import QuotioPresentation

final class MenuBarQuotaPairTests: XCTestCase {
    @MainActor
    func testPlanNamePreservesTheHostLabel() {
        for name in ["Pro 20x", "Pro 5x", "Custom CBP Plan", "Standard"] {
            XCTAssertEqual(ProviderQuota(planType: name).planDisplayName, name)
        }
    }

    func testPairRendersHostValuesAndPreservesUnknown() throws {
        let summary = QuotaSummary(sessionOnly: .init(lowest: 42, average: 65), combined: .init(lowest: 80, average: 90), pair: [
            .init(displayName: "Host session", remainingPercent: 42),
            .init(displayName: "Host weekly", remainingPercent: nil),
        ])
        let pair = try XCTUnwrap(MenuBarQuotaPair.resolve(from: summary))
        XCTAssertEqual(pair.top.labelKey, "Host session")
        XCTAssertEqual(pair.top.remainingPercentage, 42)
        XCTAssertEqual(pair.bottom.remainingPercentage, -1)
        XCTAssertNil(MenuBarQuotaPair.resolve(from: nil))
    }

    @MainActor
    func testAccessibilityUsesDisplayModeAndLocalizedUnknownValue() {
        let known = MenuBarQuotaMetric(labelKey: "quota.metric.weekly", remainingPercentage: 25)
        let unknown = MenuBarQuotaMetric(labelKey: "quota.metric.weekly", remainingPercentage: -1)

        XCTAssertEqual(
            StatusBarQuotaItemView.accessibilityValue(for: known, displayMode: .remaining),
            String(format: "%lld percent".localized(), Int64(25))
        )
        XCTAssertEqual(
            StatusBarQuotaItemView.accessibilityValue(for: known, displayMode: .used),
            String(format: "%lld percent".localized(), Int64(75))
        )
        XCTAssertEqual(
            StatusBarQuotaItemView.accessibilityValue(for: unknown, displayMode: .used),
            "quota.noDataYet".localized()
        )
    }

    @MainActor
    func testCompactQuotaPairViewFitsMenuBarHeight() {
        let item = MenuBarQuotaDisplayItem(
            id: "codex-test",
            providerSymbol: "O",
            accountShort: "test",
            percentage: 63,
            provider: .codex,
            quotaPair: MenuBarQuotaPair(
                top: MenuBarQuotaMetric(labelKey: "quota.metric.session", remainingPercentage: 81),
                bottom: MenuBarQuotaMetric(labelKey: "quota.metric.weekly", remainingPercentage: 63)
            )
        )
        let hostingView = NSHostingView(
            rootView: StatusBarQuotaItemView(item: item, colorMode: .monochrome)
        )

        hostingView.layoutSubtreeIfNeeded()

        XCTAssertLessThanOrEqual(hostingView.fittingSize.height, 22)
        XCTAssertLessThan(hostingView.fittingSize.width, 40)
    }
}
