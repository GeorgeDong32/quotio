import Foundation
import QuotioDomain

@MainActor
enum StatusBarCommand: Equatable {
    case refreshAll
    case refreshProvider(QuotaProvider)
    case refreshAccount(QuotaAccountID)
    case selectProvider(QuotaProvider?)
    case openApp
    case quit
}

@MainActor
public struct StatusBarCommandHandlers {
    fileprivate let refreshAll: @MainActor @Sendable () async -> Void
    fileprivate let refreshProvider: @MainActor @Sendable (QuotaProvider) async -> Void
    fileprivate let refreshAccount: @MainActor @Sendable (QuotaAccountID) async -> Void
    fileprivate let selectProvider: (QuotaProvider?) -> Void
    fileprivate let openApp: () -> Void
    fileprivate let quit: () -> Void
    fileprivate let menuNeedsRebuild: () -> Void

    public init(
        refreshAll: @escaping @MainActor @Sendable () async -> Void,
        refreshProvider: @escaping @MainActor @Sendable (QuotaProvider) async -> Void,
        refreshAccount: @escaping @MainActor @Sendable (QuotaAccountID) async -> Void,
        selectProvider: @escaping (QuotaProvider?) -> Void,
        openApp: @escaping () -> Void,
        quit: @escaping () -> Void,
        menuNeedsRebuild: @escaping () -> Void
    ) {
        self.refreshAll = refreshAll
        self.refreshProvider = refreshProvider
        self.refreshAccount = refreshAccount
        self.selectProvider = selectProvider
        self.openApp = openApp
        self.quit = quit
        self.menuNeedsRebuild = menuNeedsRebuild
    }
}

@MainActor
public final class StatusBarCommandDispatcher {
    private let handlers: StatusBarCommandHandlers

    public init(handlers: StatusBarCommandHandlers) {
        self.handlers = handlers
    }

    func dispatch(_ command: StatusBarCommand) {
        switch command {
        case .refreshAll:
            perform(handlers.refreshAll)
        case .refreshProvider(let provider):
            perform { [handlers] in await handlers.refreshProvider(provider) }
        case .refreshAccount(let account):
            perform { [handlers] in await handlers.refreshAccount(account) }
        case .selectProvider(let provider):
            handlers.selectProvider(provider)
        case .openApp:
            handlers.openApp()
        case .quit:
            handlers.quit()
        }
    }

    private func perform(_ action: @escaping @MainActor @Sendable () async -> Void) {
        Task { [handlers] in
            await action()
            handlers.menuNeedsRebuild()
        }
    }
}
