import AppKit
import Foundation
import MacWheelCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState!
    private var menuBarController: MenuBarController!
    private var mainWindowController: MainWindowController!
    private var wheelPanelController: WheelPanelController!
    private var dragMonitor: DragMonitor!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        appState = AppState()
        mainWindowController = MainWindowController(state: appState)
        menuBarController = MenuBarController(state: appState) { [weak self] in
            self?.mainWindowController.showAndFocus()
        }
        wheelPanelController = WheelPanelController()

        wheelPanelController.onDropAction = { [weak self] urls, action in
            self?.appState.runAction(urls: urls, action: action)
        }

        dragMonitor = DragMonitor(wheelController: wheelPanelController) { [weak self] in
            self?.appState.settings ?? AppSettings()
        }
        dragMonitor.start()

        if appState.settings.showMainWindowOnLaunch {
            mainWindowController.showAndFocus()
        }

        if !DragMonitor.isAccessibilityTrusted {
            DragMonitor.promptForAccessibility()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindowController.showAndFocus()
        return true
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
