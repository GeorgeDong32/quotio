import Foundation
import XCTest

@testable import QuotioForkExtras

/// Error-classification table for the fallback engine.
final class FallbackFormatConverterTests: XCTestCase {
    private func httpResponse(_ status: String, body: String = "{}") -> Data {
        Data("HTTP/1.1 \(status)\r\nContent-Type: application/json\r\n\r\n\(body)".utf8)
    }

    func testFallbackStatusCodesTriggerFallback() {
        for code in [429, 503, 500, 400, 401, 403, 422] {
            let reason = FallbackFormatConverter.fallbackReason(responseData: httpResponse("\(code)"))
            XCTAssertEqual(reason, .httpStatus(code), "status \(code) should map to .httpStatus")
        }
    }

    func testSuccessAndNeutralStatusesDoNotTriggerFallback() {
        XCTAssertNil(FallbackFormatConverter.fallbackReason(responseData: httpResponse("200 OK", body: #"{"ok":true}"#)))
        XCTAssertNil(FallbackFormatConverter.fallbackReason(responseData: httpResponse("204 No Content")))
        XCTAssertNil(FallbackFormatConverter.fallbackReason(responseData: httpResponse("404 Not Found", body: #"{"error":"not found here"}"#)))
    }

    func testBodyPatternsTriggerFallbackRegardlessOfCase() {
        for pattern in ["quota exceeded", "rate limit", "no available account", "resource_exhausted", "too many requests"] {
            let upper = httpResponse("404 Not Found", body: #"{"error":{"message":"\#(pattern.uppercased())"}}"#)
            XCTAssertEqual(
                FallbackFormatConverter.fallbackReason(responseData: upper),
                .pattern(pattern),
                "pattern \(pattern) should be matched case-insensitively"
            )
        }
    }

    func testSuccessStatusNeverFallsThroughToBodyPatterns() {
        let response = httpResponse("200 OK", body: #"{"error":{"message":"rate limit reached"}}"#)
        XCTAssertNil(FallbackFormatConverter.fallbackReason(responseData: response))
    }

    func testThinkingSignatureErrorDetection() {
        let signature = httpResponse("400 Bad Request", body: #"{"error":{"message":"thinking signature must match the original request"}}"#)
        XCTAssertTrue(FallbackFormatConverter.isThinkingSignatureError(responseData: signature))

        let nested = httpResponse("400 Bad Request", body: #"{"error":{"upstream_error":{"error":{"message":"signature verification failed for thinking block"}}}}"#)
        XCTAssertTrue(FallbackFormatConverter.isThinkingSignatureError(responseData: nested))

        let unrelated = httpResponse("429 Too Many Requests", body: #"{"error":{"message":"rate limit hit"}}"#)
        XCTAssertFalse(FallbackFormatConverter.isThinkingSignatureError(responseData: unrelated))
    }
}

/// Route cache semantics (set/get/overwrite/miss) on the settings manager.
@MainActor
final class FallbackRouteCacheTests: XCTestCase {
    func testSetGetOverwriteAndMiss() {
        let manager = FallbackSettingsManager.shared
        let model = "cache-test-\(UUID().uuidString.prefix(6))"

        XCTAssertNil(manager.getCachedEntryId(for: model))

        let first = UUID()
        manager.setCachedEntryId(for: model, entryId: first)
        XCTAssertEqual(manager.getCachedEntryId(for: model), first)

        let second = UUID()
        manager.setCachedEntryId(for: model, entryId: second)
        XCTAssertEqual(manager.getCachedEntryId(for: model), second)
    }
}

/// Request-body rewriting used between fallback attempts.
@MainActor
final class ProxyBridgeBodyRewriteTests: XCTestCase {
    func testReplaceModelInBodySwapsOnlyTheModelField() throws {
        let bridge = ProxyBridge()
        let body = #"{"model":"quotio-virtual","max_tokens":128,"messages":[{"role":"user","content":"hi"}]}"#

        let rewritten = bridge.replaceModelInBody(body, with: "claude-sonnet-4")

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(rewritten.utf8)) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "claude-sonnet-4")
        XCTAssertEqual(json["max_tokens"] as? Int, 128)
        XCTAssertNotNil(json["messages"])
    }

    func testReplaceModelInBodyLeavesBodyWithoutModelFieldUntouched() {
        let bridge = ProxyBridge()
        let body = #"{"prompt":"no model field"}"#

        XCTAssertEqual(bridge.replaceModelInBody(body, with: "claude-sonnet-4"), body)
    }

    func testSanitizeThinkingBlocksStripsThinkingContent() throws {
        let bridge = ProxyBridge()
        let body = """
        {"model":"claude-sonnet-4","messages":[{"role":"user","content":[
            {"type":"thinking","thinking":"secret reasoning"},
            {"type":"redacted_thinking","data":"..."},
            {"type":"text","text":"actual question"}
        ]}]}
        """

        let sanitized = bridge.sanitizeThinkingBlocks(body, targetModelId: "claude-sonnet-4")

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(sanitized.utf8)) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        let types = content.compactMap { $0["type"] as? String }
        XCTAssertEqual(types, ["text"])
    }
}
