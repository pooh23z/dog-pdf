import AppKit
import MacWheelCore
import SwiftUI

@MainActor
final class ProgressHUDController {
    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    func showProgress(message: String, character: MascotCharacter = .shiba) {
        dismissWorkItem?.cancel()
        present(view: HUDView(state: .working(message), character: character, onReveal: nil, onDismiss: { [weak self] in self?.hide() }))
    }

    func showSuccess(summary: String, revealURLs: [URL], character: MascotCharacter = .shiba) {
        dismissWorkItem?.cancel()
        present(view: HUDView(
            state: .success(summary),
            character: character,
            onReveal: revealURLs.isEmpty ? nil : {
                NSWorkspace.shared.activateFileViewerSelecting(revealURLs)
            },
            onDismiss: { [weak self] in self?.hide() }
        ))
        scheduleAutoHide(after: 4.5)
    }

    func showError(message: String, character: MascotCharacter = .shiba) {
        dismissWorkItem?.cancel()
        present(view: HUDView(state: .error(message), character: character, onReveal: nil, onDismiss: { [weak self] in self?.hide() }))
        scheduleAutoHide(after: 6.0)
    }

    func hide() {
        dismissWorkItem?.cancel()
        panel?.orderOut(nil)
    }

    private func present<V: View>(view: V) {
        let hosting = NSHostingView(rootView: view)
        let fitting = hosting.fittingSize
        let width = max(280, min(420, fitting.width))
        let height = max(56, fitting.height)

        let hudPanel: NSPanel
        if let existing = panel {
            hudPanel = existing
        } else {
            hudPanel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            hudPanel.isOpaque = false
            hudPanel.backgroundColor = .clear
            hudPanel.level = .floating
            hudPanel.hasShadow = true
            hudPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = hudPanel
        }

        hudPanel.contentView = hosting
        hudPanel.setContentSize(NSSize(width: width, height: height))

        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            let x = vf.maxX - width - 20
            let y = vf.maxY - height - 20
            hudPanel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        hudPanel.orderFrontRegardless()
    }

    private func scheduleAutoHide(after seconds: TimeInterval) {
        let item = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        dismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }
}

private enum HUDState {
    case working(String)
    case success(String)
    case error(String)
}

private struct HUDView: View {
    let state: HUDState
    let character: MascotCharacter
    let onReveal: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            switch state {
            case .working:
                AnimatedDogMascotView(character: character, isBusy: true, size: 34)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 18))
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 18))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(AppBranding.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(messageText)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if let onReveal {
                Button("Finder") {
                    onReveal()
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
        )
    }

    private var messageText: String {
        switch state {
        case .working(let msg), .success(let msg), .error(let msg):
            return msg
        }
    }
}
