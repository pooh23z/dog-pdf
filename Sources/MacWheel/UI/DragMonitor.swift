import AppKit
import ApplicationServices
import Foundation
import MacWheelCore

@MainActor
final class DragMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastDragChangeCount: Int = NSPasteboard(name: .drag).changeCount
    private var dragStartLocation: NSPoint?

    private let wheelController: WheelPanelController
    private let settingsProvider: () -> AppSettings

    init(wheelController: WheelPanelController, settingsProvider: @escaping () -> AppSettings) {
        self.wheelController = wheelController
        self.settingsProvider = settingsProvider
    }

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted() || CGPreflightListenEventAccess()
    }

    static func promptForAccessibility() {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let opts = [promptKey: kCFBooleanTrue as Any] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in
                self?.handleEvent(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleEvent(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        wheelController.hide()
    }

    private func handleEvent(_ event: NSEvent) {
        let settings = settingsProvider()
        guard settings.isEnabled else {
            wheelController.hide()
            return
        }

        switch event.type {
        case .leftMouseDown:
            dragStartLocation = NSEvent.mouseLocation
            lastDragChangeCount = NSPasteboard(name: .drag).changeCount

        case .leftMouseDragged:
            let triggerPressed = settings.trigger.matches(flags: event.modifierFlags)
            if triggerPressed {
                maybeShowWheel()
            } else if wheelController.isVisible {
                wheelController.hide()
            }

        case .flagsChanged:
            let leftButtonDown = (NSEvent.pressedMouseButtons & 1) != 0
            let triggerPressed = settings.trigger.matches(flags: event.modifierFlags)
            if leftButtonDown && triggerPressed {
                maybeShowWheel()
            } else if wheelController.isVisible && !triggerPressed {
                wheelController.hide()
            }

        case .leftMouseUp:
            dragStartLocation = nil
            // If cursor is currently outside the wheel drop view, dismiss immediately;
            // if inside, performDragOperation / draggingEnded will dismiss cleanly without racing.
            if wheelController.isVisible && !wheelController.isDraggingInside {
                wheelController.hide()
            } else if wheelController.isVisible {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    guard let self, self.wheelController.isVisible, !self.wheelController.isDraggingInside else { return }
                    self.wheelController.hide()
                }
            }

        default:
            break
        }
    }

    private func maybeShowWheel() {
        guard !wheelController.isVisible else { return }

        let currentPoint = NSEvent.mouseLocation
        let dragPB = NSPasteboard(name: .drag)
        let rawURLs = (dragPB.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let pbURLs = DragPasteboardNormalizer.normalize(rawURLs)
        let pbChanged = dragPB.changeCount != lastDragChangeCount

        let movedEnough: Bool
        if let start = dragStartLocation {
            movedEnough = hypot(currentPoint.x - start.x, currentPoint.y - start.y) >= 6
        } else {
            movedEnough = true
        }

        guard DragTriggerEvaluator.shouldSummonWheel(
            movedEnough: movedEnough,
            pasteboardChanged: pbChanged,
            hasFileURLs: !pbURLs.isEmpty
        ) else { return }
        wheelController.show(centeredAt: currentPoint, preloadedURLs: pbURLs)
    }
}
