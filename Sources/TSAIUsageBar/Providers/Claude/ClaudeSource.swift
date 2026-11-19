import Foundation
import UsageCore

enum ClaudeLinkState: Equatable {
    case linked
    case notLinked
    case replacedByUser
}

/// Claude Code: values arrive as events. The statusLine relay stores them and posts a
/// Darwin notification; this source then reloads the stored file. Nothing is polled.
@MainActor
final class ClaudeSource: ObservableObject, UsageSource {
    let provider = Provider.claude
    @Published private(set) var status = ProviderStatus()
    /// Per-day usage of the 7-day window, recorded by the relay.
    @Published private(set) var daily: DailyUsageLog
    @Published private(set) var linkState: ClaudeLinkState = .notLinked
    @Published private(set) var auth: ClaudeAuth.Status = .unknown
    var onUpdate: ((ProviderSnapshot?) -> Void)?

    var dailyLog: DailyUsageLog? { daily }

    let paths: AppPaths
    private var active = true
    private var observing = false

    init(paths: AppPaths) {
        self.paths = paths
        daily = DailyUsageStore.load(.claude, paths: paths)
        status.snapshot = SnapshotStore.load(paths.snapshotURL(.claude))
    }

    /// Only Claude Code returns to full after a reset (owner decision, 2026-11-18).
    func display(_ window: WindowKind, now: Date) -> WindowDisplay {
        WindowDisplay.evaluate(status.snapshot, window, now: now, fullAfterReset: true)
    }

    func start() {
        HookInstaller.installIfNeeded(paths: paths)
        refreshLink()
        observeUpdates()
    }

    func setActive(_ active: Bool) {
        // The relay's pause flag always follows the setting, including at launch.
        let paused = FileManager.default.fileExists(atPath: paths.claudePausedURL.path)
        if active, paused {
            try? FileManager.default.removeItem(at: paths.claudePausedURL)
        } else if !active, !paused {
            try? paths.ensureDirectory()
            FileManager.default.createFile(atPath: paths.claudePausedURL.path, contents: nil)
        }
        guard active != self.active else { return }
        self.active = active
        if active { reload() }
    }

    func refreshNow() {
        reload()
        refreshLink()
        Task { await refreshAuth() }
    }

    func panelDidOpen(showing: Provider) {
        guard showing == .claude else { return }
        reload()
        refreshLink()
        if status.snapshot == nil { Task { await refreshAuth() } }
    }

    func didWake() { reload() }

    // MARK: Values

    func reload() {
        guard active else { return }
        let log = DailyUsageStore.load(.claude, paths: paths)
        if daily != log { daily = log }
        let snap = SnapshotStore.load(paths.snapshotURL(.claude))
        guard snap != status.snapshot else { return }
        status.snapshot = snap
        onUpdate?(snap)
    }

    private func observeUpdates() {
        guard !observing else { return }
        observing = true
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(center, observer, { _, observer, _, _, _ in
            guard let observer else { return }
            let source = Unmanaged<ClaudeSource>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { source.reload() } }
        }, NotifyName.claudeUpdated as CFString, nil, .deliverImmediately)
    }

    // MARK: Connection

    func refreshLink() {
        switch StatusLineLink(paths: paths).state() {
        case .linked: linkState = .linked
        case .notLinked: linkState = .notLinked
        case .replacedByUser: linkState = .replacedByUser
        }
    }

    func refreshAuth() async {
        auth = await ClaudeAuth.status()
    }

    func link() throws {
        HookInstaller.installIfNeeded(paths: paths)
        try StatusLineLink(paths: paths).link()
        refreshLink()
    }

    func unlink() throws {
        try StatusLineLink(paths: paths).unlink()
        refreshLink()
    }
}
