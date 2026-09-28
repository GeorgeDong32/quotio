import AppKit

@MainActor
final class AppKitWindowPresenter {
    func showMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        guard let window = NSApplication.shared.windows.first(where: { $0.title == "Quotio" }) else {
            return
        }
        window.makeKeyAndOrderFront(nil)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.orderFrontRegardless()
    }
}
