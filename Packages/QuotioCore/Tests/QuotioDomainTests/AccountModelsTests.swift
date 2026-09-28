import Foundation
import XCTest
@testable import QuotioDomain

final class AccountModelsTests: XCTestCase {
    func testIdentityPreservesExistingStableMonitorID() {
        let identity = AccountIdentity.make(
            providerID: AccountProviderID(rawValue: "codex"),
            accountKey: " Person@Example.com "
        )

        XCTAssertEqual(identity.id, "monitor-a8110b8da0533693c274")
        XCTAssertEqual(identity.accountKey, "Person@Example.com")
    }

    func testAccountCodingPreservesVersionOneMetadataShape() throws {
        let account = Account.make(
            providerID: AccountProviderID(rawValue: "claude"),
            accountKey: "person@example.com",
            source: .quotioKeychain,
            credentialReference: "keychain",
            capabilities: [.disable, .delete],
            status: .disabled,
            credentialMetadata: RedactedCredentialMetadata(
                kind: .oauth,
                hasRefreshToken: true,
                hasAccountIdentifier: true
            )
        )

        let data = try JSONEncoder().encode(account)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["provider"] as? String, "claude")
        XCTAssertEqual(object["canDelete"] as? Bool, true)
        XCTAssertEqual(object["isDisabled"] as? Bool, true)
        XCTAssertNil(object["credentialMetadata"])
        XCTAssertNil(object["capabilities"])
        let decoded = try JSONDecoder().decode(Account.self, from: data)
        XCTAssertEqual(decoded.identity, account.identity)
        XCTAssertEqual(decoded.source, account.source)
        XCTAssertEqual(decoded.capabilities, account.capabilities)
        XCTAssertEqual(decoded.status, account.status)
        XCTAssertNil(decoded.credentialMetadata)
    }


    func testAmpNativeAndNamedAccountsHaveDistinctIdentities() {
        let providerID = AccountProviderID(rawValue: QuotaProvider.amp.rawValue)
        let native = Account.make(
            providerID: providerID,
            accountKey: ProviderAccountKey.ampNative,
            displayName: "Amp",
            source: .nativeCredential
        )
        let named = Account.make(
            providerID: providerID,
            accountKey: "Amp",
            source: .quotioKeychain
        )

        XCTAssertNotEqual(native.id, named.id)
        XCTAssertEqual(native.displayName, "Amp")
        XCTAssertNotEqual(native.accountKey, named.accountKey)
    }



}
