public struct QuotioHostProviders: Decodable, Sendable {
    public struct Provider: Decodable, Sendable {
        public struct Capabilities: Decodable, Sendable {
            public struct Setting: Decodable, Sendable {
                public let name: String
                public let fieldPath: String
                public let required: Bool
                public let values: [String]?
            }
            public let settings: [Setting]
            public let operations: [String]
        }
        public let id: String
        public let displayName: String
        public let actions: [QuotioHostSnapshot.Action]
        public let capabilities: Capabilities
    }
    public let schemaVersion: Int
    public let providers: [Provider]
}
