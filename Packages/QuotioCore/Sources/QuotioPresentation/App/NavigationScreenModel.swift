import Observation
import QuotioDomain

@MainActor
@Observable
public final class NavigationScreenModel {
    public var currentPage: NavigationPage = .providers {
        didSet {
            if currentPage != .providers { selectedProvider = nil }
        }
    }
    public var selectedProvider: QuotaProvider?

    public func selectProvider(_ provider: QuotaProvider) {
        currentPage = .providers
        selectedProvider = provider
    }

    public func showProviders() {
        selectedProvider = nil
        currentPage = .providers
    }

    public init() {}
}
