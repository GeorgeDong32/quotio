import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct QuotioHostConnection: Sendable, Equatable {
    public let baseURL: URL
    public let token: String

    public init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }
}

public enum QuotioHostClientError: Error, Equatable, Sendable {
    case disconnected
    case incompatible
    case response(Int, String)
    case timeout
}

private final class QuotioCLINoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public struct QuotioHostHTTPClient: Sendable {
    private struct Failure: Decodable { let error: String }

    let connection: QuotioHostConnection
    let session: URLSession

    public init(connection: QuotioHostConnection, session: URLSession? = nil) {
        self.connection = connection
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        self.session = session ?? URLSession(
            configuration: configuration,
            delegate: QuotioCLINoRedirectDelegate(),
            delegateQueue: nil
        )
    }

    public func request<T: Decodable & Sendable>(
        _ path: String,
        method: String = "GET",
        body: Data? = nil,
        idempotencyKey: String? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> T {
        let endpoint = connection.baseURL
        let loopback = ["127.0.0.1", "::1", "[::1]"].contains(endpoint.host ?? "")
        guard endpoint.scheme == "https" || (endpoint.scheme == "http" && loopback),
              endpoint.host != nil, endpoint.user == nil, endpoint.password == nil,
              endpoint.query == nil, endpoint.fragment == nil,
              !connection.token.isEmpty,
              connection.token.unicodeScalars.allSatisfy({ !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0) }) else {
            throw QuotioHostClientError.incompatible
        }
        var request = URLRequest(url: connection.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = body
        if let timeout { request.timeoutInterval = timeout }
        request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw QuotioHostClientError.disconnected
        }
        guard http.url == request.url else {
            throw QuotioHostClientError.incompatible
        }
        guard (200..<300).contains(http.statusCode) else {
            let code = (try? JSONDecoder().decode(Failure.self, from: data).error) ?? "request_failed"
            throw QuotioHostClientError.response(http.statusCode, code)
        }
        return try makeQuotioHostDecoder().decode(T.self, from: data)
    }

    public func snapshot() async throws -> QuotioHostSnapshot {
        let value: QuotioHostSnapshot = try await request("v2/snapshot")
        try value.validate()
        return value
    }
}


public func makeQuotioHostDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .custom { decoder in
        let value = try decoder.singleValueContainer().decode(String.self)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid RFC3339 timestamp")
            )
        }
        return date
    }
    return decoder
}
