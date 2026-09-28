public struct MonitoringProvider: Identifiable, Equatable, Sendable {
    public struct Input: Identifiable, Equatable, Sendable {
        public var id: String { fieldPath }
        public let name: String
        public let fieldPath: String
        public let required: Bool
        public let values: [String]?

        public init(name: String, fieldPath: String, required: Bool, values: [String]?) {
            self.name = name
            self.fieldPath = fieldPath
            self.required = required
            self.values = values
        }
    }
    public let id: QuotaProvider
    public let displayName: String
    public let actions: Set<String>
    public let inputs: [Input]

    public init(id: QuotaProvider, displayName: String, actions: Set<String>, inputs: [Input]) {
        self.id = id
        self.displayName = displayName
        self.actions = actions
        self.inputs = inputs
    }
}
