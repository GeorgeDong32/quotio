import Foundation
import XCTest
import QuotioDomain
@testable import QuotioInfrastructure

final class GitHubProxyReleaseRepositoryTests: XCTestCase {
    override func setUp() { ReleaseURLProtocol.reset() }

    private let digest = String(repeating: "a", count: 64)
    private let tag = "v1.2.3"
    #if arch(arm64)
    private let asset = "CLIProxyAPI_1.2.3_darwin_aarch64.tar.gz"
    #else
    private let asset = "CLIProxyAPI_1.2.3_darwin_amd64.tar.gz"
    #endif

    private func repository() -> GitHubProxyReleaseRepository {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReleaseURLProtocol.self]
        return GitHubProxyReleaseRepository(session: URLSession(configuration: config))
    }

    private func enqueueLimit() {
        ReleaseURLProtocol.enqueue(status: 403, headers: ["X-RateLimit-Remaining": "0"])
    }

    private func enqueueAssets(checksum: Bool = true) {
        ReleaseURLProtocol.enqueue(body: """
        <li><a href="/router-for-me/CLIProxyAPI/releases/download/\(tag)/checksums.txt">checksums</a>
        <span>sha256:\(String(repeating: "b", count: 64))</span></li>
        <li><a href="/router-for-me/CLIProxyAPI/releases/download/\(tag)/\(asset)">binary</a>
        <span>\(checksum ? "sha256:" + digest : "")</span></li>
        """)
    }

    func testLatestFallsBackOnRateLimitAndUsesMatchingAssetDigest() async throws {
        enqueueLimit()
        ReleaseURLProtocol.enqueue(body: "<include-fragment src=\"/router-for-me/CLIProxyAPI/releases/expanded_assets/\(tag)\"></include-fragment>")
        enqueueAssets()
        let release = try await repository().latestRelease()
        XCTAssertEqual(release.version, "1.2.3")
        XCTAssertEqual(release.sha256, digest)
        XCTAssertTrue(try XCTUnwrap(release.downloadURL).hasSuffix(asset))
        XCTAssertEqual(ReleaseURLProtocol.requests().count, 3)
    }

    func testTaggedReleaseFallsBackOnRateLimit() async throws {
        enqueueLimit()
        enqueueAssets()
        let release = try await repository().release(tag: tag)
        XCTAssertEqual(release.sha256, digest)
        XCTAssertEqual(ReleaseURLProtocol.requests().count, 2)
    }

    func testListFallsBackOn429AndDeduplicatesTags() async throws {
        ReleaseURLProtocol.enqueue(status: 429)
        let fragment = "<include-fragment src=\"/router-for-me/CLIProxyAPI/releases/expanded_assets/\(tag)\"></include-fragment>"
        ReleaseURLProtocol.enqueue(body: fragment + fragment)
        enqueueAssets()
        let releases = try await repository().releases(limit: 10)
        XCTAssertEqual(releases.count, 1)
        XCTAssertEqual(ReleaseURLProtocol.requests().count, 3)
    }

    func testFallbackRejectsMissingChecksumInsteadOfUsingAdjacentDigest() async throws {
        enqueueLimit()
        enqueueAssets(checksum: false)
        do {
            _ = try await repository().release(tag: tag)
            XCTFail("Expected checksum failure")
        } catch { XCTAssertEqual(error as? ProxyFailure, .checksumMissing) }
    }

    func testNonRateLimitHTTPFailureDoesNotFallBack() async throws {
        ReleaseURLProtocol.enqueue(status: 404)
        do {
            _ = try await repository().latestRelease()
            XCTFail("Expected HTTP failure")
        } catch {
            XCTAssertEqual(error as? ProxyFailure, .network("GitHub release request failed (HTTP 404)"))
        }
        XCTAssertEqual(ReleaseURLProtocol.requests().count, 1)
    }
}

private final class ReleaseURLProtocol: URLProtocol, @unchecked Sendable {
    private struct Stub { let data: Data; let status: Int; let error: Error?; let headers: [String: String] }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubs: [Stub] = []
    nonisolated(unsafe) private static var recorded: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let stub = Self.lock.withLock { () -> Stub in
            Self.recorded.append(request)
            return Self.stubs.removeFirst()
        }
        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: nil, headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func enqueue(body: String = "", status: Int = 200, headers: [String: String] = [:]) {
        lock.withLock { stubs.append(Stub(data: Data(body.utf8), status: status, error: nil, headers: headers)) }
    }

    static func enqueue(error: Error) {
        lock.withLock { stubs.append(Stub(data: Data(), status: 0, error: error, headers: [:])) }
    }

    static func requests() -> [URLRequest] { lock.withLock { recorded } }
    static func reset() { lock.withLock { stubs = []; recorded = [] } }
}
