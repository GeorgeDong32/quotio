import SwiftUI

/// Registry that lets the app target render fork-added `NavigationPage`s
/// without QuotioPresentation depending on fork packages.
///
/// The app target registers view factories at startup (CompositionRoot);
/// `AppSettingsPage` consults the registry for fork pages and falls back to
/// an empty view when nothing is registered.
public enum ForkPageRegistry {
    /// Registered at app startup (main actor) before any fork page renders.
    @MainActor public static var providers: [NavigationPage: @MainActor () -> AnyView] = [:]

    @MainActor
    public static func provider(for page: NavigationPage) -> (@MainActor () -> AnyView)? {
        providers[page]
    }
}
