import AppKit
import MacWheelCore
import SwiftUI

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private var hasCenteredOnce = false

    init(state: AppState) {
        let contentView = AppControlView(state: state, isWindowMode: true, onOpenMainWindow: nil, onClose: nil)
        let hosting = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppBranding.displayName
        window.titlebarAppearsTransparent = false
        window.minSize = NSSize(width: 380, height: 500)
        window.isReleasedWhenClosed = false
        window.contentViewController = hosting

        self.window = window
        super.init()
        window.delegate = self
    }

    func showAndFocus() {
        if !hasCenteredOnce {
            window.center()
            hasCenteredOnce = true
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide window instead of quitting so Menu Bar icon and Finder Shift+Drag keep working.
        sender.orderOut(nil)
        return false
    }
}
