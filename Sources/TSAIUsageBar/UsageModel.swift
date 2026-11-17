import AppKit
import Combine
import Network
import UsageCore

/// State of one provider as shown in the UI.
struct ProviderStatus: Equatable {
    var snapshot: ProviderSnapshot?
    var isFetching = false
    var lastAttempt: Date?
    var lastError: CodexError?
    var consecutiveFailures = 0
}

enum ClaudeLinkState: Equatable {
    case linked
    case notLinked
    case replacedByUser
}

/// Holds both providers' values and keeps them fresh with as little work as possible:
/// Claude updates arrive as events from the statusLine relay; Codex is queried briefly
/// on a timer, when the popover opens, after a reset time, and after wake or reconnect.
@MainActor
final class UsageModel: ObservableObject {
    @Published private(set) var claude = ProviderStatus()
    @Published private(set) var codex = ProviderStatus()
    @Published private(set) var claudeLink: ClaudeLinkState = .notLinked
    @Published private(set) var claudeAuth: ClaudeAuth.Status = .unknown
    @Published private(set) var codexSigningIn = false
    /// Advances at reset times (and every 30 s while a popover is open) so derived text updates.
    @Published private(set) var now = Date()
    /// Providers with at least one item turned on. Others are not updated at all.
    @Published private(set) var activeProviders: Set<Provider> = Set(Provider.allCases)

    let paths = AppPaths()
    private let policy = FetchPolicy()
    private var codexTimer: Timer?
    private var tickTimer: Timer?
    private var popoverOpen = false
    private var sleeping = false
    private var pathMonitor: NWPathMonitor?
    private var networkWasDown = false
    private var observers: [NSObjectProtocol] = []
    var onSnapshotArrived: ((Provider, ProviderSnapshot) -> Void)?

    init() {
        claude.snapshot = SnapshotStore.load(paths.snapshotURL(.claude))
        codex.snapshot = SnapshotStore.load(paths.snapshotURL(.codex))
    }

    func start() {
        HookInstaller.installIfNeeded(paths: paths)
        refreshClaudeLink()
        observeClaudeUpdates()
        observeSystem()
        refreshCodex(force: true)
        scheduleTick()
    }

    func setActiveProviders(_ active: Set<Provider>) {
        // The relay's pause flag always follows the setting, including at launch.
        let paused = FileManager.default.fileExists(atPath: paths.claudePausedURL.path)
        if active.contains(.claude), paused {
            try? FileManager.default.removeItem(at: paths.claudePausedURL)
        } else if !active.contains(.claude), !paused {
            try? paths.ensureDirectory()
            FileManager.default.createFile(atPath: paths.claudePausedURL.path, contents: nil)
        }
        let old = activeProviders
        guard active != old else { return }
        activeProviders = active
        if active.contains(.claude), !old.contains(.claude) { reloadClaude() }
        if active.contains(.codex) {
            if !old.contains(.codex) { refreshCodex(force: true) }
        } else {
            codexTimer?.invalidate()
        }
    }

    func isActive(_ p: Provider) -> Bool { activeProviders.contains(p) }

    func status(_ p: Provider) -> ProviderStatus { p == .claude ? claude : codex }

    func display(_ id: ItemID) -> WindowDisplay {
        WindowDisplay.evaluate(status(id.provider).snapshot, id.window, now: now)
    }

    /// True when the last Codex attempt failed and the shown values are older.
    func isStale(_ p: Provider) -> Bool { p == .codex && codex.lastError != nil && codex.snapshot != nil }

    // MARK: Popover

    func popoverDidOpen(_ provider: Provider) {
        popoverOpen = true
        now = Date()
        switch provider {
        case .codex:
            if policy.shouldFetchOnDemand(now: Date(), lastAttempt: codex.lastAttempt,
                                          lastSuccess: codex.snapshot?.fetchedAt) {
                refreshCodex(force: false)
            } else {
                scheduleCodex()
            }
        case .claude:
            reloadClaude()
            refreshClaudeLink()
            if claude.snapshot == nil { Task { await refreshClaudeAuth() } }
        }
        scheduleTick()
    }

    func popoverDidClose() {
        popoverOpen = false
        scheduleCodex()
        scheduleTick()
    }

    func manualRefresh(_ provider: Provider?) {
        if provider == nil || provider == .codex { refreshCodex(force: true) }
        if provider == nil || provider == .claude {
            reloadClaude()
            refreshClaudeLink()
            Task { await refreshClaudeAuth() }
        }
        now = Date()
    }

    // MARK: Codex

    func refreshCodex(force: Bool) {
        guard isActive(.codex) else { return } // all Codex items off: no queries
        guard !codex.isFetching else { return } // merge overlapping requests
        if !force, let last = codex.lastAttempt, Date().timeIntervalSince(last) < policy.minimumGap {
            scheduleCodex()
            return
        }
        codex.isFetching = true
        codex.lastAttempt = Date()
        codexTimer?.invalidate()
        Task {
            let result = await Task.detached { await CodexClient.readRateLimits() }.value
            self.applyCodex(result)
        }
    }

    private func applyCodex(_ result: Result<ProviderSnapshot, CodexError>) {
        codex.isFetching = false
        switch result {
        case .success(let snap):
            codex.snapshot = snap
            codex.lastError = nil
            codex.consecutiveFailures = 0
            try? paths.ensureDirectory()
            try? SnapshotStore.save(snap, to: paths.snapshotURL(.codex))
            onSnapshotArrived?(.codex, snap)
        case .failure(let e):
            codex.lastError = e
            codex.consecutiveFailures += 1
        }
        now = Date()
        scheduleCodex()
        scheduleTick()
    }

    private func scheduleCodex() {
        codexTimer?.invalidate()
        guard !sleeping, !codex.isFetching, isActive(.codex) else { return }
        // Without the codex command there is nothing to poll until the person acts.
        if codex.lastError == .notFound || codex.lastError == .notSignedIn {
            if !popoverOpen { return }
        }
        let resets = codex.snapshot?.windows.values.compactMap(\.resetsAt) ?? []
        let delay = policy.nextDelay(now: Date(), lastAttempt: codex.lastAttempt,
                                     consecutiveFailures: codex.consecutiveFailures,
                                     popoverOpen: popoverOpen, resetTimes: resets)
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refreshCodex(force: false) }
        }
        t.tolerance = min(10, delay * 0.1)
        RunLoop.main.add(t, forMode: .common)
        codexTimer = t
    }

    func signInCodex() {
        guard !codexSigningIn else { return }
        codexSigningIn = true
        Task {
            let r = await Task.detached {
                await CodexClient.signIn { url in DispatchQueue.main.async { NSWorkspace.shared.open(url) } }
            }.value
            self.codexSigningIn = false
            if case .success = r { self.refreshCodex(force: true) }
        }
    }

    // MARK: Claude

    private func observeClaudeUpdates() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(center, observer, { _, observer, _, _, _ in
            guard let observer else { return }
            let model = Unmanaged<UsageModel>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { model.reloadClaude() } }
        }, NotifyName.claudeUpdated as CFString, nil, .deliverImmediately)
    }

    func reloadClaude() {
        guard isActive(.claude) else { return }
        let snap = SnapshotStore.load(paths.snapshotURL(.claude))
        guard snap != claude.snapshot else { return }
        claude.snapshot = snap
        now = Date()
        if let snap { onSnapshotArrived?(.claude, snap) }
        scheduleTick()
    }

    func refreshClaudeLink() {
        let state = StatusLineLink(paths: paths).state()
        switch state {
        case .linked: claudeLink = .linked
        case .notLinked: claudeLink = .notLinked
        case .replacedByUser: claudeLink = .replacedByUser
        }
    }

    func refreshClaudeAuth() async {
        claudeAuth = await ClaudeAuth.status()
    }

    func linkClaude() throws {
        HookInstaller.installIfNeeded(paths: paths)
        try StatusLineLink(paths: paths).link()
        refreshClaudeLink()
    }

    func unlinkClaude() throws {
        try StatusLineLink(paths: paths).unlink()
        refreshClaudeLink()
    }

    // MARK: Display clock

    /// Wakes up only when something visible can change: the next reset time, or every
    /// 30 s while a popover shows relative times.
    private func scheduleTick() {
        tickTimer?.invalidate()
        guard !sleeping else { return }
        let current = Date()
        var next: TimeInterval = .infinity
        for s in [claude.snapshot, codex.snapshot] {
            for w in s?.windows.values ?? [:].values {
                if let r = w.resetsAt, r > current { next = min(next, r.timeIntervalSince(current) + 0.5) }
            }
        }
        if popoverOpen { next = min(next, 30) }
        guard next.isFinite else { return }
        let t = Timer(timeInterval: max(1, next), repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.now = Date()
                self?.scheduleTick()
            }
        }
        t.tolerance = popoverOpen ? 2 : 1
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t
    }

    // MARK: Sleep, wake, clock, network

    private func observeSystem() {
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sleeping = true
                self?.codexTimer?.invalidate()
                self?.tickTimer?.invalidate()
            }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sleeping = false
                self.now = Date()
                self.reloadClaude()
                self.scheduleTick()
                // Give the network a moment to come back before asking Codex.
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    MainActor.assumeIsolated { self.refreshCodex(force: true) }
                }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.now = Date()
                self?.scheduleTick()
                self?.scheduleCodex()
            }
        })
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if path.status == .satisfied {
                        if self.networkWasDown {
                            self.networkWasDown = false
                            self.refreshCodex(force: true)
                        }
                    } else {
                        self.networkWasDown = true
                    }
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "network.monitor"))
        pathMonitor = monitor
    }
}

/// Copies the statusLine relay to a stable location so Claude Code keeps working even
/// if the app bundle is moved or replaced during an update.
enum HookInstaller {
    static func installIfNeeded(paths: AppPaths) {
        guard let source = Bundle.main.url(forAuxiliaryExecutable: "tsai-usagebar-hook") else { return }
        let dest = paths.installedHookURL
        let fm = FileManager.default
        if let a = try? Data(contentsOf: source), let b = try? Data(contentsOf: dest), a == b { return }
        do {
            try paths.ensureDirectory()
            try fm.createDirectory(at: paths.hookDirectory, withIntermediateDirectories: true)
            let tmp = paths.hookDirectory.appendingPathComponent(".hook.tmp")
            try? fm.removeItem(at: tmp)
            try fm.copyItem(at: source, to: tmp)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
            if fm.fileExists(atPath: dest.path) {
                _ = try fm.replaceItemAt(dest, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: dest)
            }
        } catch {
            NSLog("TSAI UsageBar: hook install failed: \(error.localizedDescription)")
        }
    }
}
