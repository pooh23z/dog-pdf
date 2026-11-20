import AppKit
import Foundation
import MacWheelCore
import SwiftUI
import UniformTypeIdentifiers

enum AppTab: String, CaseIterable, Identifiable {
    case workspace
    case characters
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace: return "แปลง / ลดขนาด"
        case .characters: return "ตัวละคร (10)"
        case .settings: return "ตั้งค่า"
        }
    }

    var icon: String {
        switch self {
        case .workspace: return "wand.and.stars"
        case .characters: return "pawprint.fill"
        case .settings: return "slider.horizontal.3"
        }
    }
}

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
    @Published var selectedTab: AppTab = .workspace
    @Published var previewRunning: Bool = false

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
            selectedTab = .workspace
        }
    }

    func runAction(urls: [URL], action: WheelAction) {
        guard !urls.isEmpty else { return }
        lastError = nil
        activeJobCount += 1
        let mascot = settings.mascot
        hud.showProgress(
            message: activeJobCount > 1 ? "[\(activeJobCount) งาน] \(action.label): \(urls[0].lastPathComponent)…" : "\(action.label): \(urls[0].lastPathComponent)…",
            character: mascot
        )

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
                        let prefix = self.activeJobCount > 1 ? "[\(self.activeJobCount) งาน] " : ""
                        self.hud.showProgress(message: prefix + message, character: self.settings.mascot)
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
                    self.hud.showSuccess(summary: result.summary, revealURLs: result.outputURLs, character: self.settings.mascot)
                } else {
                    self.hud.showProgress(message: "เสร็จไป 1 งาน — เหลืออีก \(self.activeJobCount) งาน…", character: self.settings.mascot)
                }
            } catch {
                self.activeJobCount = max(0, self.activeJobCount - 1)
                let message = error.localizedDescription
                self.lastError = message
                if self.activeJobCount == 0 {
                    self.hud.showError(message: message, character: self.settings.mascot)
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
            hud.showError(message: "ไม่พบไฟล์ setup-deps.sh", character: settings.mascot)
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

    func fileSizeLabel(for url: URL) -> String {
        guard let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value else {
            return ""
        }
        return formatReadableByteCount(bytes)
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
        popover.contentSize = NSSize(width: 390, height: 590)
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

        updateMascotIconAndScheduleNext()
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

    private func updateMascotIconAndScheduleNext() {
        animationTimer?.invalidate()
        let busyOrPreview = state.isBusy || state.previewRunning
        animationController.update(isBusy: busyOrPreview, isEnabled: state.settings.isEnabled)
        let pose = animationController.stepFrame()
        let character = state.settings.mascot

        if state.settings.animateMenuBarDog {
            statusItem.button?.image = DogSpriteRenderer.menuBarImage(for: pose, character: character)
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
            statusItem.button?.image = DogSpriteRenderer.menuBarImage(for: staticPose, character: character)
        }

        let interval = state.settings.animateMenuBarDog ? animationController.frameInterval : 0.45
        animationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.updateMascotIconAndScheduleNext()
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
        VStack(spacing: 0) {
            headerBar
            tabBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch state.selectedTab {
                    case .workspace:
                        workspaceTab
                    case .characters:
                        charactersTab
                    case .settings:
                        settingsTab
                    }
                }
                .padding(isWindowMode ? 18 : 14)
            }
        }
        .frame(minWidth: isWindowMode ? 420 : 390, maxWidth: isWindowMode ? .infinity : 390)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { state.refreshStatus() }
    }

    // MARK: - Top Header & Tab Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            AnimatedDogMascotView(
                character: state.settings.mascot,
                isBusy: state.isBusy || state.previewRunning,
                size: 44
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(AppBranding.displayName)
                        .font(.system(size: 16, weight: .bold))
                    Text("Offline")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.16), in: Capsule())
                        .foregroundStyle(.green)
                }
                Text("\(state.settings.mascot.emoji) \(state.settings.mascot.thaiName) • ลาก + \(state.settings.trigger.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isWindowMode, let onOpenMainWindow {
                Button(action: onOpenMainWindow) {
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
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("ปิดหน้าต่าง")
            }
        }
        .padding(.horizontal, isWindowMode ? 18 : 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var tabBar: some View {
        VStack(spacing: 5) {
            DogTabBarRunwayView(
                character: state.settings.mascot,
                activeTabIndex: AppTab.allCases.firstIndex(of: state.selectedTab) ?? 0,
                tabCount: AppTab.allCases.count,
                isRunningFast: state.isBusy || state.previewRunning
            )

            HStack(spacing: 6) {
                ForEach(AppTab.allCases) { tab in
                    let isSelected = (state.selectedTab == tab)
                    Button {
                        state.selectedTab = tab
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(tab.title)
                                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(isSelected ? Color.orange : Color.secondary.opacity(0.10))
                        )
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, isWindowMode ? 18 : 14)
        .padding(.bottom, 10)
    }

    // MARK: - Tab 1: Workspace (Drop Zone + Target File Size + Actions + Recent)

    private var workspaceTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            dropZoneCard
            targetFileSizeCard
            if !state.droppedURLs.isEmpty {
                actionCardsSection
            } else {
                quickTipBanner
            }
            if let err = state.lastError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if !state.recentJobs.isEmpty {
                recentJobsCard
            }
        }
    }

    private var dropZoneCard: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        state.isDropTargeted ? Color.orange : Color.orange.opacity(0.35),
                        style: StrokeStyle(lineWidth: state.isDropTargeted ? 2.5 : 1.5, dash: [7, 5])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.orange.opacity(state.isDropTargeted ? 0.18 : 0.08),
                                        Color.orange.opacity(state.isDropTargeted ? 0.08 : 0.03)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .frame(minHeight: isWindowMode ? 116 : 96)

                VStack(spacing: 8) {
                    Image(systemName: state.droppedURLs.isEmpty ? "tray.and.arrow.down.fill" : "doc.on.doc.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.orange)

                    if state.droppedURLs.isEmpty {
                        Text("ลากรูป / PDF / วิดีโอ / เอกสาร มาวางที่นี่")
                            .font(.system(size: 13, weight: .semibold))
                    } else {
                        Text("พร้อมจัดการ \(state.droppedURLs.count) ไฟล์ — เลือกคำสั่งด้านล่าง")
                            .font(.system(size: 13, weight: .semibold))
                    }

                    HStack(spacing: 10) {
                        Button {
                            state.pickFiles()
                        } label: {
                            Label("เลือกไฟล์จาก Finder…", systemImage: "folder.badge.plus")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.small)

                        if !state.droppedURLs.isEmpty {
                            Button("ล้างไฟล์") {
                                state.droppedURLs = []
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .onDrop(of: [.fileURL], isTargeted: $state.isDropTargeted) { providers in
                handleDropProviders(providers)
                return true
            }

            if !state.droppedURLs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(state.droppedURLs.prefix(4), id: \.path) { url in
                        HStack(spacing: 6) {
                            Image(systemName: "doc.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text(url.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(state.fileSizeLabel(for: url))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    if state.droppedURLs.count > 4 {
                        Text("และอีก \(state.droppedURLs.count - 4) ไฟล์…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var targetFileSizeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("ขนาดไฟล์เป้าหมายตอนลดขนาด (รูป & PDF)", systemImage: "arrow.down.right.and.arrow.up.left")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(state.settings.targetFileSize.displayName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], spacing: 6) {
                ForEach(TargetFileSize.allCases) { target in
                    let selected = (state.settings.targetFileSize == target)
                    Button {
                        state.settings.targetFileSize = target
                    } label: {
                        Text(target.displayName)
                            .font(.system(size: 11.5, weight: selected ? .bold : .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(selected ? Color.orange : Color.secondary.opacity(0.10))
                            )
                            .foregroundStyle(selected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var actionCardsSection: some View {
        let resolution = FileClassifier.resolveWheel(for: state.droppedURLs)
        return VStack(alignment: .leading, spacing: 8) {
            Text("เลือกคำสั่งที่ต้องการ")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            if resolution.hasSharedActions {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(resolution.slices) { action in
                        Button {
                            state.runAction(urls: state.droppedURLs, action: action)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: action.symbolName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(actionDisplayTitle(action))
                                        .font(.system(size: 12.5, weight: .bold))
                                        .lineLimit(1)
                                    Text(actionSubtitle(action))
                                        .font(.system(size: 10))
                                        .opacity(0.85)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(action == .compress || action == .mergePDF ? Color.orange : Color.accentColor.opacity(0.15))
                            )
                            .foregroundStyle(action == .compress || action == .mergePDF ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .disabled(state.isBusy)
                    }
                }
            } else {
                Text("ไฟล์ต่างประเภทปนกัน ไม่มีคำสั่งที่ใช้ร่วมกันได้ ลองเลือกไฟล์ประเภทเดียวกันหรือรูป+PDF ครับ")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var quickTipBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("เคล็ดลับใช้งานไวสุด")
                    .font(.caption.weight(.bold))
                Text("ใน Finder ลากไฟล์ค้างไว้ + กด \(state.settings.trigger.displayName) ค้าง วงล้อจะเด้งตรงเมาส์และใช้ขนาดไฟล์เป้าหมาย (\(state.settings.targetFileSize.displayName)) ที่เลือกไว้อัตโนมัติ!")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var recentJobsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("งานล่าสุด")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            ForEach(state.recentJobs.prefix(5)) { entry in
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(entry.outputURLs)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text(entry.title)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Tab 2: Characters (10 Animated Animals)

    private var charactersTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Hero stage for currently selected mascot
            HStack(spacing: 14) {
                AnimatedDogMascotView(
                    character: state.settings.mascot,
                    isBusy: state.isBusy || state.previewRunning,
                    size: 74
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(state.settings.mascot.emoji) \(state.settings.mascot.thaiName)")
                        .font(.system(size: 16, weight: .bold))
                    Text(state.previewRunning || state.isBusy ? "กำลังวิ่งทำงานดุ๊กดิ๊ก!" : "กำลังรอรับไฟล์บน Menu Bar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        state.previewRunning.toggle()
                    } label: {
                        Label(state.previewRunning ? "หยุดทดสอบท่าวิ่ง" : "ลองดูท่าวิ่งตอนทำงาน", systemImage: state.previewRunning ? "pause.fill" : "figure.run")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                }
                Spacer()
            }
            .padding(14)
            .background(
                LinearGradient(
                    colors: [Color.orange.opacity(0.12), Color.orange.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("เลือกสัตว์เลี้ยง 10 ตัว (เปลี่ยนทั้งบน Menu Bar และในแอปทันที)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(MascotCharacter.allCases) { character in
                        let isSelected = (state.settings.mascot == character)
                        Button {
                            state.settings.mascot = character
                        } label: {
                            HStack(spacing: 10) {
                                AnimatedDogMascotView(character: character, isBusy: isSelected && state.previewRunning, size: 42)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(character.thaiName)
                                        .font(.system(size: 12.5, weight: isSelected ? .bold : .medium))
                                        .lineLimit(1)
                                    Text(isSelected ? "กำลังใช้งาน" : "แตะเพื่อเลือก")
                                        .font(.caption2)
                                        .foregroundStyle(isSelected ? .orange : .secondary)
                                }
                                Spacer(minLength: 2)
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.orange)
                                }
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isSelected ? Color.orange.opacity(0.12) : Color.secondary.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(isSelected ? Color.orange : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Toggle("ให้น้องขยับดุ๊กดิ๊กบน Menu Bar", isOn: $state.settings.animateMenuBarDog)
                .font(.caption.weight(.semibold))
                .tint(.orange)
                .padding(12)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Tab 3: Settings & Offline Tools Status

    private var settingsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("การควบคุมและคุณภาพ")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                HStack {
                    Text("ปุ่มเรียกวงล้อใน Finder")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Picker("", selection: $state.settings.trigger) {
                        ForEach(ModifierTrigger.allCases) { trigger in
                            Text(trigger.displayName).tag(trigger)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }

                HStack {
                    Text("คุณภาพลดขนาด (โหมดอัตโนมัติ)")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Picker("", selection: $state.settings.compressionPreset) {
                        ForEach(CompressionPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
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
                    .frame(width: 140)
                }

                Toggle("เปิดหน้าต่างนี้เมื่อเริ่มแอป", isOn: $state.settings.showMainWindowOnLaunch)
                    .font(.caption.weight(.medium))
                    .tint(.orange)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("สถานะเครื่องมือออฟไลน์")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("รีเฟรช") {
                        state.refreshStatus()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }

                statusRow("สิทธิ์ Accessibility (จับลาก Finder)", ok: state.accessibilityTrusted, actionTitle: state.accessibilityTrusted ? nil : "ขอสิทธิ์") {
                    state.requestAccessibility()
                }
                statusRow("ffmpeg (วิดีโอ / เสียง / ลดขนาด)", ok: state.dependencyStatus.hasFFmpeg)
                statusRow("ImageMagick (WEBP / รูปภาพ)", ok: state.dependencyStatus.hasMagick)
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
            .padding(12)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack {
                Text("Dog PDF v1.1 • 100% Offline")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("ออกจากโปรแกรม") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Helpers

    private func actionDisplayTitle(_ action: WheelAction) -> String {
        switch action {
        case .compress:
            return state.settings.targetFileSize == .auto ? "ลดขนาดไฟล์" : "ลดขนาด (\(state.settings.targetFileSize.displayName))"
        case .mergePDF: return "รวมเป็น PDF"
        case .transcribe: return "ถอดเสียง"
        case .translateTH: return "แปล → ไทย"
        case .translateEN: return "แปล → อังกฤษ"
        default: return "แปลงเป็น \(action.label)"
        }
    }

    private func actionSubtitle(_ action: WheelAction) -> String {
        switch action {
        case .compress:
            return state.settings.targetFileSize == .auto ? "โหมด \(state.settings.compressionPreset.displayName)" : "บีบอัดตามเป้าหมาย"
        case .mergePDF: return "รวมทุกไฟล์เป็น 1 PDF"
        case .transcribe: return "ได้ทั้ง .txt + .srt"
        case .translateTH, .translateEN: return "ออฟไลน์ + OCR"
        default: return "บันทึกข้างไฟล์เดิม"
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

    private func handleDropProviders(_ providers: [NSItemProvider]) {
        Task {
            var collected: [URL] = []
            for provider in providers {
                if let url = await loadFileURL(from: provider) {
                    collected.append(url)
                }
            }
            let normalized = DragPasteboardNormalizer.normalize(collected)
            if !normalized.isEmpty {
                await MainActor.run {
                    self.state.droppedURLs = normalized
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
