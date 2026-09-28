public struct MonitoringSettings: Equatable, Sendable {
    public var revision: String
    public var enabledProviders: Set<String>
    public var disabledProviders: Set<String>
    public var automaticallyDiscoverLogins: Bool
    public var refreshInterval: Int

    public init(revision: String, enabledProviders: Set<String>, disabledProviders: Set<String>, automaticallyDiscoverLogins: Bool, refreshInterval: Int) {
        self.revision = revision
        self.enabledProviders = enabledProviders
        self.disabledProviders = disabledProviders
        self.automaticallyDiscoverLogins = automaticallyDiscoverLogins
        self.refreshInterval = refreshInterval
    }
}
