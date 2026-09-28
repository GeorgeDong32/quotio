public struct ProviderTrackingPreferences: Equatable, Sendable {
    public var disabledProviders: Set<QuotaProvider>
    public var automaticallyDiscoverLogins: Bool

    public init(disabledProviders: Set<QuotaProvider> = [], automaticallyDiscoverLogins: Bool = true) {
        self.disabledProviders = disabledProviders
        self.automaticallyDiscoverLogins = automaticallyDiscoverLogins
    }

    public func isEnabled(_ provider: QuotaProvider) -> Bool {
        !disabledProviders.contains(provider)
    }
}
