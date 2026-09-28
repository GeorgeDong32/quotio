import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
import QuotioHostClient

@MainActor
final class QuotioHostClientTests: XCTestCase {
    private func fixture() throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../").standardizedFileURL
        return try Data(contentsOf: root.appendingPathComponent("apps/cli/tests/fixtures/contracts/snapshot-v2.json"))
    }

    func testRustFixtureDecodesWithoutProviderRules() throws {
        let data = try fixture()
        let snapshot = try QuotioHostSnapshot.decode(data)
        XCTAssertEqual(snapshot.accounts.count, 2)
        XCTAssertEqual(snapshot.accounts[1].sources.count, 2)
        XCTAssertTrue(snapshot.usage[0].metrics.isEmpty)
        var changed = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var usage = try XCTUnwrap(changed["usage"] as? [[String: Any]])
        usage[0]["reset_credits"] = ["available_count": 2, "fetched_at": "2026-01-01T00:00:00Z", "earliest_expires_at": NSNull(), "source": "fixture"]
        usage[0]["subscription_status"] = "active"
        changed["usage"] = usage
        let supplemental = try QuotioHostSnapshot.decode(JSONSerialization.data(withJSONObject: changed))
        XCTAssertEqual(supplemental.usage[0].resetCredits?.availableCount, 2)
        XCTAssertEqual(supplemental.usage[0].subscriptionStatus, "active")
        changed["schema_version"] = 3
        XCTAssertThrowsError(try QuotioHostSnapshot.decode(JSONSerialization.data(withJSONObject: changed)))
    }

    func testInvalidRelationshipsAndDuplicateAnalyticsAreRejected() throws {
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture()) as? [String: Any])
        var redirect = original
        redirect["account_redirects"] = ["old-account": "missing-account"]
        XCTAssertThrowsError(try QuotioHostSnapshot.decode(JSONSerialization.data(withJSONObject: redirect)))
        var profile = original
        var usage = profile["usage"] as! [[String: Any]]
        usage[0]["codex_profile"] = [
            "daily_usage": [["date":"2026-09-24", "tokens":0], ["date":"2026-09-24", "tokens":1]],
            "latest_30_buckets_tokens":1, "fetched_at":"2026-09-24T00:00:00Z"
        ]
        profile["usage"] = usage
        XCTAssertThrowsError(try QuotioHostSnapshot.decode(JSONSerialization.data(withJSONObject: profile)))
        var missingTime = original
        var untimed = missingTime["usage"] as! [[String: Any]]
        untimed[0]["fetched_at"] = NSNull(); missingTime["usage"] = untimed
        XCTAssertThrowsError(try QuotioHostSnapshot.decode(JSONSerialization.data(withJSONObject: missingTime)))
        var disabled = original
        var accounts = disabled["accounts"] as! [[String: Any]]
        accounts[0]["enabled"] = false
        disabled["accounts"] = accounts
        XCTAssertThrowsError(try QuotioHostSnapshot.decode(JSONSerialization.data(withJSONObject: disabled)))
    }

    func testHostConnectionsKeepCredentialsSeparateAndRejectUnsafeTransport() async throws {
        Stub.state.reset(try fixture())
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Stub.self]
        let session = URLSession(configuration: config)
        for host in ["one.example.test", "two.example.test"] {
            let client = QuotioHostHTTPClient(connection: .init(baseURL: URL(string: "https://\(host)")!, token: host), session: session)
            _ = try await client.snapshot()
        }
        let requests = Stub.state.requests()
        XCTAssertEqual(requests.count, 2)
        for request in requests {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(request.url!.host!)")
            XCTAssertEqual(request.url?.path, "/v2/snapshot")
        }
        let unsafe = QuotioHostHTTPClient(connection: .init(baseURL: URL(string: "http://remote.example.test")!, token: "secret"), session: session)
        do { _ = try await unsafe.snapshot(); XCTFail("Plaintext remote credentials must not be sent") }
        catch QuotioHostClientError.incompatible {}
        XCTAssertEqual(Stub.state.requests().count, 2)
        let revoked = QuotioHostHTTPClient(connection: .init(baseURL: URL(string: "https://revoked.example.test")!, token: "revoked"), session: session)
        do { _ = try await revoked.snapshot(); XCTFail("Revoked token must fail") }
        catch QuotioHostClientError.response(let status, let code) { XCTAssertEqual(status, 401); XCTAssertEqual(code, "unauthorized") }
    }
}

private final class Stub: URLProtocol, @unchecked Sendable {
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var body = Data()
        private var captured: [URLRequest] = []
        func reset(_ data: Data) { lock.withLock { body = data; captured = [] } }
        func requests() -> [URLRequest] { lock.withLock { captured } }
        func receive(_ request: URLRequest) -> Data { lock.withLock { captured.append(request); return body } }
    }
    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = Self.state.receive(request)
        let revoked = request.url?.host == "revoked.example.test"
        let response = HTTPURLResponse(url: request.url!, statusCode: revoked ? 401 : 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: revoked ? Data(#"{"error":"unauthorized"}"#.utf8) : body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
