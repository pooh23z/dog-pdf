import AppKit
import Foundation
import MacWheelCore

@MainActor
final class WheelPanelController {
    private let panel: NSPanel
    private let dropView: WheelDropView
    private var isShowing = false

    var onDropAction: (([URL], WheelAction) -> Void)?
    var onCancel: (() -> Void)?

    init() {
        let size = NSSize(width: 284, height: 284)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false

        let dropView = WheelDropView(frame: NSRect(origin: .zero, size: size))
        panel.contentView = dropView

        self.panel = panel
        self.dropView = dropView

        dropView.onExecute = { [weak self] urls, action in
            self?.hide()
            self?.onDropAction?(urls, action)
        }
        dropView.onCancel = { [weak self] in
            self?.hide()
            self?.onCancel?()
        }
    }

    var isVisible: Bool { isShowing }
    var isDraggingInside: Bool { dropView.isDraggingInside }

    func show(centeredAt screenPoint: NSPoint, preloadedURLs: [URL] = []) {
        let size = panel.frame.size
        var origin = NSPoint(x: screenPoint.x - size.width / 2, y: screenPoint.y - size.height / 2)

        if let screen = NSScreen.screens.first(where: { NSMouseInRect(screenPoint, $0.frame, false) }) ?? NSScreen.main {
            let vf = screen.visibleFrame
            origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - size.width - 8)
            origin.y = min(max(origin.y, vf.minY + 8), vf.maxY - size.height - 8)
        }

        if !preloadedURLs.isEmpty {
            dropView.configure(urls: preloadedURLs)
        } else {
            dropView.resetToWaiting()
        }

        panel.setFrameOrigin(origin)
        if !isShowing {
            panel.alphaValue = 0.0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                panel.animator().alphaValue = 1.0
            }
            isShowing = true
        }
    }

    func hide() {
        guard isShowing else { return }
        isShowing = false
        panel.orderOut(nil)
        dropView.resetToWaiting()
    }
}

@MainActor
private final class WheelDropView: NSView {
    private let innerRadius: CGFloat = 44
    private let outerRadius: CGFloat = 128

    private var draggedURLs: [URL] = []
    private var resolution = WheelResolution(categorySummary: "Drop Files", slices: [], hasSharedActions: false)
    private var hoveredTarget: WheelHitTarget = .cancel
    private(set) var isDraggingInside: Bool = false

    var onExecute: (([URL], WheelAction) -> Void)?
    var onCancel: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func resetToWaiting() {
        draggedURLs = []
        resolution = WheelResolution(categorySummary: "Drop Here", slices: [], hasSharedActions: false)
        hoveredTarget = .cancel
        isDraggingInside = false
        needsDisplay = true
    }

    func configure(urls: [URL]) {
        draggedURLs = urls
        resolution = FileClassifier.resolveWheel(for: urls)
        hoveredTarget = .cancel
        needsDisplay = true
    }

    private func extractURLs(from sender: NSDraggingInfo) -> [URL] {
        let pb = sender.draggingPasteboard
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let objs = pb.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !objs.isEmpty {
            return DragPasteboardNormalizer.normalize(objs)
        }
        return draggedURLs
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDraggingInside = true
        let urls = extractURLs(from: sender)
        if !urls.isEmpty {
            configure(urls: urls)
        }
        updateHover(for: sender)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDraggingInside = true
        updateHover(for: sender)
        if case .slice = hoveredTarget {
            return .copy
        }
        return .generic
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDraggingInside = false
        hoveredTarget = .cancel
        needsDisplay = true
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isDraggingInside = false
        onCancel?()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDraggingInside = false
        let urls = extractURLs(from: sender)
        if !urls.isEmpty {
            configure(urls: urls)
        }
        updateHover(for: sender)

        guard case .slice(let index) = hoveredTarget,
              index >= 0, index < resolution.slices.count,
              !urls.isEmpty else {
            onCancel?()
            return false
        }

        let action = resolution.slices[index]
        onExecute?(urls, action)
        return true
    }

    private func updateHover(for sender: NSDraggingInfo) {
        let localPoint = convert(sender.draggingLocation, from: nil)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let target = WheelGeometry.hitTest(
            point: localPoint,
            center: center,
            innerRadius: innerRadius,
            outerRadius: outerRadius,
            sliceCount: resolution.slices.count
        )
        if target != hoveredTarget {
            hoveredTarget = target
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let sliceCount = resolution.slices.count

        // Base circular translucent warm-amber disk
        let outerOval = NSRect(
            x: center.x - outerRadius,
            y: center.y - outerRadius,
            width: outerRadius * 2,
            height: outerRadius * 2
        )
        let baseCircle = NSBezierPath(ovalIn: outerOval)
        NSColor(calibratedRed: 0.98, green: 0.87, blue: 0.72, alpha: 0.90).setFill()
        baseCircle.fill()

        NSColor(calibratedWhite: 1.0, alpha: 0.65).setStroke()
        baseCircle.lineWidth = 1.5
        baseCircle.stroke()

        if sliceCount > 0 {
            for (index, action) in resolution.slices.enumerated() {
                let (startDeg, endDeg, midRad) = WheelGeometry.sliceDegrees(index: index, sliceCount: sliceCount)
                let path = NSBezierPath()
                path.appendArc(withCenter: center, radius: outerRadius, startAngle: startDeg, endAngle: endDeg, clockwise: true)
                path.appendArc(withCenter: center, radius: innerRadius, startAngle: endDeg, endAngle: startDeg, clockwise: false)
                path.close()

                let isHovered = hoveredTarget == .slice(index)
                if isHovered {
                    NSColor(calibratedRed: 0.95, green: 0.41, blue: 0.11, alpha: 0.96).setFill()
                    path.fill()
                }

                NSColor(calibratedRed: 0.82, green: 0.66, blue: 0.48, alpha: 0.45).setStroke()
                path.lineWidth = 1.0
                path.stroke()

                // Draw icon + label at midpoint of the slice
                let labelRadius = (innerRadius + outerRadius) * 0.54
                let px = center.x + cos(midRad) * labelRadius
                let py = center.y + sin(midRad) * labelRadius

                let textColor: NSColor = isHovered ? .white : NSColor(calibratedRed: 0.24, green: 0.16, blue: 0.10, alpha: 0.95)
                if let symbol = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: action.label) {
                    let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
                    let tinted = symbol.withSymbolConfiguration(config) ?? symbol
                    let iconRect = NSRect(x: px - 9, y: py + 1, width: 18, height: 18)
                    tinted.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: isHovered ? 1.0 : 0.85)
                }

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: action.label.count > 7 ? 10 : 11.5, weight: .bold),
                    .foregroundColor: textColor
                ]
                let labelStr = NSString(string: action.label)
                let textSize = labelStr.size(withAttributes: attrs)
                labelStr.draw(
                    at: NSPoint(x: px - textSize.width / 2, y: py - textSize.height - 1),
                    withAttributes: attrs
                )
            }
        }

        // Center hub (Cancel / Status)
        let innerOval = NSRect(
            x: center.x - innerRadius,
            y: center.y - innerRadius,
            width: innerRadius * 2,
            height: innerRadius * 2
        )
        let centerPath = NSBezierPath(ovalIn: innerOval)
        NSColor(calibratedWhite: 1.0, alpha: 0.94).setFill()
        centerPath.fill()
        NSColor(calibratedRed: 0.92, green: 0.50, blue: 0.20, alpha: 0.55).setStroke()
        centerPath.lineWidth = 1.5
        centerPath.stroke()

        let title: String
        let subtitle: String
        if !draggedURLs.isEmpty && !resolution.hasSharedActions {
            title = "Mixed"
            subtitle = "No shared"
        } else if case .slice(let idx) = hoveredTarget, idx < resolution.slices.count {
            title = resolution.slices[idx].label
            subtitle = resolution.categorySummary
        } else {
            title = resolution.categorySummary
            subtitle = "Cancel"
        }

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .bold),
            .foregroundColor: NSColor(calibratedRed: 0.20, green: 0.14, blue: 0.09, alpha: 1.0)
        ]
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let tStr = NSString(string: title)
        let tSize = tStr.size(withAttributes: titleAttrs)
        tStr.draw(at: NSPoint(x: center.x - tSize.width / 2, y: center.y + 1), withAttributes: titleAttrs)

        let sStr = NSString(string: subtitle)
        let sSize = sStr.size(withAttributes: subAttrs)
        sStr.draw(at: NSPoint(x: center.x - sSize.width / 2, y: center.y - sSize.height - 2), withAttributes: subAttrs)
    }
}
