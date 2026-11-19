import AppKit
import Foundation
import MacWheelCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState!
    private var menuBarController: MenuBarController!
    private var wheelPanelController: WheelPanelController!
    private var dragMonitor: DragMonitor!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        appState = AppState()
        menuBarController = MenuBarController(state: appState)
        wheelPanelController = WheelPanelController()

        wheelPanelController.onDropAction = { [weak self] urls, action in
            self?.appState.runAction(urls: urls, action: action)
        }

        dragMonitor = DragMonitor(wheelController: wheelPanelController) { [weak self] in
            self?.appState.settings ?? AppSettings()
        }
        dragMonitor.start()

        if !DragMonitor.isAccessibilityTrusted {
            DragMonitor.promptForAccessibility()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        dragMonitor?.stop()
    }
}

@main
struct MacWheelApplication {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
