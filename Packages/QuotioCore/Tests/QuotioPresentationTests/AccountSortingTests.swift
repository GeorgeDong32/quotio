import QuotioDomain
import XCTest
@testable import QuotioPresentation

final class AccountSortingTests: XCTestCase {
    private struct Account: Equatable {
        let email: String
    }

    func testActiveAccountFloatsToTop() {
        let accounts = [
            Account(email: "alpha@example.com"),
            Account(email: "bravo@example.com"),
            Account(email: "charlie@example.com")
        ]

        let result = AccountSorting.prioritizingActive(accounts) {
            $0.email == "charlie@example.com"
        }

        XCTAssertEqual(result.map(\.email), [
            "charlie@example.com",
            "alpha@example.com",
            "bravo@example.com"
        ])
    }

    func testMultipleActiveAccountsKeepStableRelativeOrder() {
        let accounts = [
            Account(email: "alpha@example.com"),
            Account(email: "bravo@example.com"),
            Account(email: "charlie@example.com"),
            Account(email: "delta@example.com")
        ]

        let active: Set<String> = ["bravo@example.com", "delta@example.com"]
        let result = AccountSorting.prioritizingActive(accounts) {
            active.contains($0.email)
        }

        XCTAssertEqual(result.map(\.email), [
            "bravo@example.com",
            "delta@example.com",
            "alpha@example.com",
            "charlie@example.com"
        ])
    }

    func testNoActiveAccountLeavesOrderUnchanged() {
        let accounts = [
            Account(email: "charlie@example.com"),
            Account(email: "alpha@example.com"),
            Account(email: "bravo@example.com")
        ]

        let result = AccountSorting.prioritizingActive(accounts) { _ in false }

        XCTAssertEqual(result, accounts)
    }

    func testAllActiveAccountsLeaveOrderUnchanged() {
        let accounts = [
            Account(email: "charlie@example.com"),
            Account(email: "alpha@example.com")
        ]

        let result = AccountSorting.prioritizingActive(accounts) { _ in true }

        XCTAssertEqual(result, accounts)
    }

    func testEmptyListStaysEmpty() {
        let result = AccountSorting.prioritizingActive([Account]()) { _ in true }
        XCTAssertTrue(result.isEmpty)
    }

    func testMenuBarSortsHostNamesWithoutMergingDuplicateDisplayNames() {
        let quotas: [String: ProviderQuota] = [
            "source-b": ProviderQuota(accountDisplayName: "Zulu"),
            "source-a": ProviderQuota(accountDisplayName: "Alpha"),
            "source-c": ProviderQuota(accountDisplayName: "Alpha"),
        ]
        let ordered = StatusBarMenuSnapshotMapper.orderedAccounts(quotas)
        XCTAssertEqual(ordered.map(\.email), ["Alpha", "Alpha", "Zulu"])
        XCTAssertEqual(ordered.map(\.accountKey), ["source-a", "source-c", "source-b"])
    }

    func testMenuBarUsesOpaqueKeyOnlyWhenNoHostNameIsAvailable() {
        let ordered = StatusBarMenuSnapshotMapper.orderedAccounts(["source-id": ProviderQuota()])
        XCTAssertEqual(ordered.first?.email, "source-id")
        XCTAssertTrue(StatusBarMenuSnapshotMapper.orderedAccounts([:]).isEmpty)
    }
}
