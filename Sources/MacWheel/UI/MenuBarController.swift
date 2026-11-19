import AppKit
import Foundation
import MacWheelCore
import SwiftUI
import UniformTypeIdentifiers

struct RecentJobEntry: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let outputURLs: [URL]
    let timestamp: Date
}

@MainActor
final class AppState: ObservableObject {
    private static let settingsKey = "MacWheel.AppSettings.v1"

    @Published var settings: AppSettings {
        didSet { saveSettings() }
    }
    @Published var dependencyStatus: DependencyStatus
    @Published var accessibilityTrusted: Bool
    @Published var recentJobs: [RecentJobEntry] = []
    @Published var activeJobCount: Int = 0
    @Published var droppedURLs: [URL] = []
    @Published var isDropTargeted: Bool = false
    @Published var lastError: String?

    var isBusy: Bool { activeJobCount > 0 }

    private let executor = JobExecutor()
    let hud = ProgressHUDController()
    private var observers: [NSObjectProtocol] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
        }
        self.dependencyStatus = OutputPathResolver.discoverTools().dependencyStatus()
        self.accessibilityTrusted = DragMonitor.isAccessibilityTrusted

        let activeObs = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }
        let axObs = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                self?.refreshStatus()
            }
        }
        observers = [activeObs, axObs]
    }

    func refreshStatus() {
        dependencyStatus = OutputPathResolver.discoverTools().dependencyStatus()
        accessibilityTrusted = DragMonitor.isAccessibilityTrusted
    }

    func requestAccessibility() {
        DragMonitor.promptForAccessibility()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshStatus()
        }
    }

    func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "เลือกไฟล์"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            droppedURLs = panel.urls
        }
    }

    func runAction(urls: [URL], action: WheelAction) {
        guard !urls.isEmpty else { return }
        lastError = nil
        activeJobCount += 1
        hud.showProgress(message: activeJobCount > 1 ? "[\(activeJobCount) jobs] \(action.label): \(urls[0].lastPathComponent)…" : "\(action.label): \(urls[0].lastPathComponent)…")

        let currentSettings = settings
        let tools = OutputPathResolver.discoverTools()

        Task {
            do {
                let result = try await executor.execute(
                    urls: urls,
                    action: action,
                    settings: currentSettings,
                    toolPaths: tools
                ) { [weak self] message in
                    Task { @MainActor in
                        guard let self else { return }
                        let prefix = self.activeJobCount > 1 ? "[\(self.activeJobCount) jobs] " : ""
                        self.hud.showProgress(message: prefix + message)
                    }
                }
                self.activeJobCount = max(0, self.activeJobCount - 1)
                self.droppedURLs = []
                self.recentJobs.insert(
                    RecentJobEntry(title: result.summary, outputURLs: result.outputURLs, timestamp: Date()),
                    at: 0
                )
                if self.recentJobs.count > 8 {
                    self.recentJobs = Array(self.recentJobs.prefix(8))
                }
                NSSound(named: NSSound.Name("Glass"))?.play()
                if self.activeJobCount == 0 {
                    self.hud.showSuccess(summary: result.summary, revealURLs: result.outputURLs)
                } else {
                    self.hud.showProgress(message: "เสร็จไป 1 งาน (\(result.summary)) — เหลืออีก \(self.activeJobCount) งาน…")
                }
            } catch {
                self.activeJobCount = max(0, self.activeJobCount - 1)
                let message = error.localizedDescription
                self.lastError = message
                if self.activeJobCount == 0 {
                    self.hud.showError(message: message)
                }
            }
        }
    }

    func launchSetupDepsScript() {
        var scriptURL = Bundle.main.resourceURL?.appendingPathComponent("setup-deps.sh")
        if scriptURL == nil || !FileManager.default.fileExists(atPath: scriptURL!.path) {
            let localScript = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("scripts/setup-deps.sh")
            if FileManager.default.fileExists(atPath: localScript.path) {
                scriptURL = localScript
            }
        }
        guard let script = scriptURL, FileManager.default.fileExists(atPath: script.path) else {
            hud.showError(message: "setup-deps.sh not found.")
            return
        }

        let escaped = script.path.replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = """
        tell application "Terminal"
            activate
            do script "bash \\"\(escaped)\\""
        end tell
        """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", appleScript]
        try? proc.run()
    }

    func openTranslationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }
}

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let state: AppState
    private var animationController = DogAnimationController()
    private var animationTimer: Timer?

    init(state: AppState, onOpenMainWindow: @escaping () -> Void) {
        self.state = state
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.toolTip = "\(AppBranding.displayName) (Offline File Converter)"
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        popover.behavior = .applicationDefined
        popover.contentSize = NSSize(width: 340, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: AppControlView(
                state: state,
                isWindowMode: false,
                onOpenMainWindow: { [weak self] in
                    self?.popover.performClose(nil)
                    onOpenMainWindow()
                },
                onClose: { [weak self] in
                    self?.popover.performClose(nil)
                }
            )
        )

        updateDogIconAndScheduleNext()
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        state.refreshStatus()
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateDogIconAndScheduleNext() {
        animationTimer?.invalidate()
        animationController.update(isBusy: state.isBusy, isEnabled: state.settings.isEnabled)
        let pose = animationController.stepFrame()

        if state.settings.animateMenuBarDog {
            statusItem.button?.image = DogSpriteRenderer.menuBarImage(for: pose)
        } else {
            let staticPose = DogPose(
                mode: state.settings.isEnabled ? .idle : .paused,
                frameIndex: 0,
                headBobY: 0,
                tailAngleDeg: 10,
                earBounceDeg: 0,
                stridePhase: 0,
                isBlinking: !state.settings.isEnabled,
                showHeart: false
            )
            statusItem.button?.image = DogSpriteRenderer.menuBarImage(for: staticPose)
        }

        let interval = state.settings.animateMenuBarDog ? animationController.frameInterval : 0.6
        animationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.updateDogIconAndScheduleNext()
            }
        }
    }
}

struct AppControlView: View {
    @ObservedObject var state: AppState
    let isWindowMode: Bool
    let onOpenMainWindow: (() -> Void)?
    let onClose: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerSection
                Divider()
                dropZoneSection
                Divider()
                settingsSection
                Divider()
                statusSection
                if !state.recentJobs.isEmpty {
                    Divider()
                    recentSection
                }
                Divider()
                footerSection
            }
            .padding(isWindowMode ? 18 : 14)
        }
        .frame(minWidth: isWindowMode ? 380 : 340, maxWidth: isWindowMode ? .infinity : 340)
        .onAppear { state.refreshStatus() }
    }

    private var headerSection: some View {
        HStack {
            AnimatedDogMascotView(isBusy: state.isBusy, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(AppBranding.displayName)
                    .font(.headline)
                Text("100% Offline • ลากไฟล์ + กด \(state.settings.trigger.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isWindowMode, let onOpenMainWindow {
                Button {
                    onOpenMainWindow()
                } label: {
                    Image(systemName: "macwindow")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("เปิดหน้าต่างแอปเต็ม")
            }
            Toggle("", isOn: $state.settings.isEnabled)
                .toggleStyle(.switch)
                .tint(.orange)
                .labelsHidden()
            if let onClose {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("ปิดหน้าต่าง")
            }
        }
    }

    private var dropZoneSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        state.isDropTargeted ? Color.orange : Color.secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(state.isDropTargeted ? Color.orange.opacity(0.12) : Color.secondary.opacity(0.06))
                    )
                    .frame(height: isWindowMode ? 96 : 68)

                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(isWindowMode ? .title2 : .body)
                        .foregroundStyle(.orange)
                    Text(state.droppedURLs.isEmpty ? "ลากไฟล์มาวางที่นี่ (Drop Zone)" : "เลือกไว้ \(state.droppedURLs.count) ไฟล์ — กดเลือกคำสั่งด้านล่าง")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("เลือกไฟล์จาก Finder…") {
                        state.pickFiles()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $state.isDropTargeted) { providers in
                handleDropProviders(providers)
                return true
            }

            if !state.droppedURLs.isEmpty {
                let resolution = FileClassifier.resolveWheel(for: state.droppedURLs)
                if resolution.hasSharedActions {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], spacing: 6) {
                        ForEach(resolution.slices) { action in
                            Button {
                                state.runAction(urls: state.droppedURLs, action: action)
                            } label: {
                                Label(action.label, systemImage: action.symbolName)
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .controlSize(.small)
                            .disabled(state.isBusy)
                        }
                    }
                } else {
                    Text("ไฟล์ต่างประเภทปนกัน ไม่มีคำสั่งที่ใช้ร่วมกันได้")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if let err = state.lastError {
                Text(err)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ปุ่มเรียกวงล้อ")
                    .font(.caption.weight(.medium))
                Spacer()
                Picker("", selection: $state.settings.trigger) {
                    ForEach(ModifierTrigger.allCases) { trigger in
                        Text(trigger.displayName).tag(trigger)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
            }

            HStack {
                Text("ระดับลดขนาด (Compress)")
                    .font(.caption.weight(.medium))
                Spacer()
                Picker("", selection: $state.settings.compressionPreset) {
                    ForEach(CompressionPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
            }

            HStack {
                Text("ภาษาถอดเสียง (Whisper)")
                    .font(.caption.weight(.medium))
                Spacer()
                Picker("", selection: $state.settings.whisperLanguage) {
                    Text("Auto").tag("auto")
                    Text("ไทย (th)").tag("th")
                    Text("English (en)").tag("en")
                }
                .labelsHidden()
                .frame(width: 130)
            }

            Toggle("เปิดหน้าต่างนี้เมื่อเริ่มแอป", isOn: $state.settings.showMainWindowOnLaunch)
                .font(.caption.weight(.medium))

            Toggle("น้องหมาดุ๊กดิ๊กบน Menu Bar", isOn: $state.settings.animateMenuBarDog)
                .font(.caption.weight(.medium))
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("สถานะเครื่องมือออฟไลน์")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            statusRow("สิทธิ์ Accessibility (จับลาก Finder)", ok: state.accessibilityTrusted, actionTitle: state.accessibilityTrusted ? nil : "ขอสิทธิ์") {
                state.requestAccessibility()
            }
            statusRow("ffmpeg (วิดีโอ/เสียง/ลดขนาด)", ok: state.dependencyStatus.hasFFmpeg)
            statusRow("ImageMagick (WEBP/รูปภาพ)", ok: state.dependencyStatus.hasMagick)
            statusRow(
                "Whisper (\(state.dependencyStatus.whisperModelName ?? "ยังไม่ติดตั้ง"))",
                ok: state.dependencyStatus.hasWhisperCLI && state.dependencyStatus.hasWhisperModel,
                actionTitle: (state.dependencyStatus.hasWhisperCLI && state.dependencyStatus.hasWhisperModel) ? nil : "ติดตั้ง"
            ) {
                state.launchSetupDepsScript()
            }

            HStack {
                Text("แปลภาษาออฟไลน์ (Apple Translation)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("ตั้งค่าภาษา") {
                    state.openTranslationSettings()
                }
                .buttonStyle(.link)
                .font(.caption2)
            }
        }
    }

    private func statusRow(_ label: String, ok: Bool, actionTitle: String? = nil, action: (() -> Void)? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
                .font(.caption)
            Text(label)
                .font(.caption2)
                .lineLimit(1)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ล่าสุด")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(state.recentJobs.prefix(4)) { entry in
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(entry.outputURLs)
                } label: {
                    HStack {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(.orange)
                            .font(.caption2)
                        Text(entry.title)
                            .font(.caption2)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "folder")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footerSection: some View {
        HStack {
            Button("รีเฟรชสถานะ") {
                state.refreshStatus()
            }
            .buttonStyle(.borderless)
            .font(.caption)
            Spacer()
            Button("ออกจากโปรแกรม") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.red)
        }
    }

    private func handleDropProviders(_ providers: [NSItemProvider]) {
        Task {
            var collected: [URL] = []
            for provider in providers {
                if let url = await loadFileURL(from: provider) {
                    collected.append(url)
                }
            }
            if !collected.isEmpty {
                await MainActor.run {
                    self.state.droppedURLs = collected
                }
            }
        }
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
