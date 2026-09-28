import Foundation

public struct QuotioHostDiscovery: Decodable, Sendable {
    public struct Permission: Decodable, Sendable {
        public let provider: String
        public let kind: String
        public let location: String?
        public let keychainAccount: String?
    }
    public struct Scan: Decodable, Sendable {
        public let provider: String
        public let at: Date
    }
    public struct Failure: Decodable, Sendable {
        public let provider: String
        public let kind: String
        public let code: String
    }
    public let schemaVersion: Int
    public let scans: [Scan]
    public let permissions: [Permission]
    public let knownSources: [Permission]
    public let failures: [Failure]
    public let registered: Int
}
