import Foundation
import Network
import XCTest

@testable import QuotioForkExtras

/// End-to-end fallback routing through the real ProxyBridge:
/// client → bridge → fake upstream. A virtual model with two entries is
/// configured; the upstream rejects the first entry's model with HTTP 429
/// and accepts the second, and the test asserts the bridge retried and the
/// client saw the success.
@MainActor
final class FallbackRoutingIntegrationTests: XCTestCase {
    private var bridge: ProxyBridge?

    override func tearDown() async throws {
        bridge?.stop()
        bridge = nil
        try await Task.sleep(for: .milliseconds(150))
    }

    func testBridgeFallsOverOn429AndReturnsUpstreamSuccess() async throws {
        guard await FreePort.nwListeningAvailable() else {
            throw XCTSkip("NWListener cannot bind in this environment (sandboxed terminal); run in Xcode or CI")
        }

        let modelName = "e2e-virtual-\(Int.random(in: 1000...9999))"
        let upstream = try await FakeUpstream.start(rejectModel: "e2e-model-a")
        defer { upstream.cancel() }

        // Configure fallback: virtual model → [e2e-model-a (429), e2e-model-b (200)].
        let defaults = UserDefaults.standard
        let originalConfig = defaults.data(forKey: "fallbackConfiguration")
        let configuration = FallbackConfiguration(
            isEnabled: true,
            isRouteCachingEnabled: false,
            virtualModels: [
                VirtualModel(
                    name: modelName,
                    fallbackEntries: [
                        FallbackEntry(provider: .claude, modelId: "e2e-model-a", priority: 1),
                        FallbackEntry(provider: .gemini, modelId: "e2e-model-b", priority: 2),
                    ],
                    isEnabled: true
                )
            ]
        )
        defaults.set(try JSONEncoder().encode(configuration), forKey: "fallbackConfiguration")
        FallbackSettingsManager.shared.reloadForTesting()
        defer {
            if let originalConfig {
                defaults.set(originalConfig, forKey: "fallbackConfiguration")
            } else {
                defaults.removeObject(forKey: "fallbackConfiguration")
            }
            FallbackSettingsManager.shared.reloadForTesting()
        }

        // Bridge on a free user port, forwarding to the fake upstream.
        let bridge = ProxyBridge()
        self.bridge = bridge
        let userPort = try await FreePort.reserve()
        bridge.configure(listenPort: userPort, targetPort: upstream.port)
        bridge.start()
        try await Task.sleep(for: .milliseconds(200))

        let body = #"{"model":"\#(modelName)","messages":[{"role":"user","content":"hi"}]}"#
        let request = """
        POST /v1/chat/completions HTTP/1.1\r
        Host: 127.0.0.1:\(userPort)\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        \r
        \(body)
        """
        let client = RawHTTPClient()
        let response = try await client.send(request, to: userPort)

        XCTAssertTrue(
            response.hasPrefix("HTTP/1.1 200"),
            "client should see the retried success, got: \(response.prefix(60))"
        )
        XCTAssertEqual(
            upstream.receivedModels(),
            ["e2e-model-a", "e2e-model-b"],
            "bridge should advance to the next entry after a 429"
        )
    }
}

/// Reserves a free TCP port by briefly binding to an ephemeral one.
enum FreePort {
    /// Some terminal sandboxes reject NWListener binds with POSIX EINVAL
    /// while allowing raw BSD sockets; probe before running socket tests.
    static func nwListeningAvailable() async -> Bool {
        guard let listener = try? NWListener(using: .tcp, on: .any) else { return false }
        return await withCheckedContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.cancel()
                    continuation.resume(returning: true)
                case .failed:
                    continuation.resume(returning: false)
                default:
                    break
                }
            }
            listener.start(queue: .global())
        }
    }

    static func reserve() async throws -> UInt16 {
        let listener = try NWListener(using: .tcp, on: .any)
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let port = listener.port {
                        listener.cancel()
                        continuation.resume(returning: port.rawValue)
                    }
                case .failed(let error):
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: .global())
        }
    }
}

/// Sends one raw HTTP request and collects the full response. All mutable
/// state is confined to the serial `queue`.
final class RawHTTPClient: @unchecked Sendable {
    private let queue = DispatchQueue(label: "raw-http-client")
    private var data = Data()
    private var continuation: CheckedContinuation<String, Error>?
    private var connection: NWConnection?

    func send(_ raw: String, to port: UInt16) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.queue.async {
                guard self.continuation == nil else {
                    continuation.resume(throwing: NSError(domain: "RawHTTPClient", code: 2))
                    return
                }
                self.continuation = continuation
                let connection = NWConnection(
                    host: "127.0.0.1",
                    port: NWEndpoint.Port(rawValue: port)!,
                    using: .tcp
                )
                self.connection = connection
                connection.stateUpdateHandler = { [weak self] state in
                    self?.queue.async { self?.handle(state) }
                }
                connection.start(queue: self.queue)
                connection.send(content: Data(raw.utf8), completion: .contentProcessed { [weak self] _ in
                    self?.queue.async { self?.receiveLoop() }
                })
            }
        }
    }

    private func handle(_ state: NWConnection.State) {
        if case .failed = state {
            finish()
        }
    }

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            self.queue.async {
                if let content { self.data.append(content) }
                if error != nil || isComplete || self.responseComplete() {
                    self.connection?.cancel()
                    self.finish()
                } else {
                    self.receiveLoop()
                }
            }
        }
    }

    private func responseComplete() -> Bool {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return false }
        let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) ?? ""
        guard
            let lengthLine = head.components(separatedBy: "\r\n")
                .first(where: { $0.lowercased().hasPrefix("content-length:") }),
            let length = Int(lengthLine.split(separator: ":")[1].trimmingCharacters(in: .whitespaces))
        else { return false }
        return data.count - headerEnd.upperBound >= length
    }

    private func finish() {
        connection?.cancel()
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
    }
}

/// Minimal raw-TCP HTTP upstream: answers HTTP 429 for `rejectModel`,
/// HTTP 200 for anything else, recording every request's model field.
final class FakeUpstream: @unchecked Sendable {
    let port: UInt16
    private let rejectModel: String
    private let queue = DispatchQueue(label: "fake-upstream")
    private var listener: NWListener?
    private let lock = NSLock()
    private var models: [String] = []

    static func start(rejectModel: String) async throws -> FakeUpstream {
        let listener = try NWListener(using: .tcp, on: .any)
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let port = listener.port {
                        continuation.resume(returning: port.rawValue)
                    }
                case .failed(let error):
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: .global())
        }
        let upstream = FakeUpstream(rejectModel: rejectModel, listener: listener, port: port)
        listener.newConnectionHandler = { [weak upstream] connection in
            upstream?.serve(connection)
        }
        return upstream
    }

    private init(rejectModel: String, listener: NWListener, port: UInt16) {
        self.rejectModel = rejectModel
        self.listener = listener
        self.port = port
    }

    func receivedModels() -> [String] {
        lock.withLock { models }
    }

    func cancel() {
        listener?.cancel()
        listener = nil
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(connection, buffer: Data())
    }

    private func receiveRequest(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { content, _, isComplete, error in
            var data = buffer
            if let content { data.append(content) }
            if error != nil {
                connection.cancel()
                return
            }
            if !Self.requestComplete(data) && !isComplete {
                self.receiveRequest(connection, buffer: data)
                return
            }
            let model = Self.extractModel(from: data)
            self.lock.withLock { self.models.append(model) }
            let status = model == self.rejectModel ? "429 Too Many Requests" : "200 OK"
            let body = #"{"ok":true}"#
            let response = """
            HTTP/1.1 \(status)\r
            Content-Type: application/json\r
            Content-Length: \(body.utf8.count)\r
            Connection: close\r
            \r
            \(body)
            """
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private static func requestComplete(_ data: Data) -> Bool {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return false }
        let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) ?? ""
        guard
            let lengthLine = head.components(separatedBy: "\r\n")
                .first(where: { $0.lowercased().hasPrefix("content-length:") }),
            let length = Int(lengthLine.split(separator: ":")[1].trimmingCharacters(in: .whitespaces))
        else { return false }
        return data.count - headerEnd.upperBound >= length
    }

    private static func extractModel(from data: Data) -> String {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return "" }
        let body = data[headerEnd.upperBound...]
        if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let model = json["model"] as? String {
            return model
        }
        return ""
    }
}
