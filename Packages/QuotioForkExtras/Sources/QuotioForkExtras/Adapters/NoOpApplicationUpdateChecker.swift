import Foundation
import QuotioApplication

/// Fork: auto-update is removed. This checker satisfies the
/// `ApplicationUpdateChecking` port without Sparkle, reporting no
/// update capability so update UI and background cycles stay inert.
public final class NoOpApplicationUpdateChecker: ApplicationUpdateChecking {
    public var isInitialized: Bool { false }
    public var isChecking: Bool { false }
    public var canCheck: Bool { false }
    public var lastCheckDate: Date? { nil }
    public var automaticallyChecksForUpdates: Bool {
        get { false }
        set {}
    }

    public init() {}

    public func setAllowsPrereleaseUpdates(_ allowed: Bool) {}
    public func initializeIfNeeded() {}
    public func checkForUpdates() {}
    public func checkForUpdatesInBackground() {}
    public func resetUpdateCycle() {}
    public func setDidChangeHandler(_ handler: (@MainActor () -> Void)?) {}
}
