import AppKit
import Combine
import Network
import UsageCore

/// Coordinates the services' sources. It decides which services are active, forwards
/// app-wide events (panel, sleep and wake, clock, network) to every source, and keeps a
/// display clock that advances only when something visible can change. How each service
/// is read lives in its source (`ClaudeSource`, `CodexSource`, `GitHubSource`).
@MainActor
final class UsageModel: ObservableObject {
    let paths: AppPaths
    let claude: ClaudeSource
    let codex: CodexSource
    let github: GitHubSource
    /// In `Provider.allCases` order.
    let sources: [any UsageSource]

    /// Advances at reset times (and every 30 s while a panel is open) so derived text updates.
    @Published private(set) var now = Date()
    /// Providers with at least one item turned on. Others are not updated at all.
    @Published private(set) var activeProviders: Set<Provider> = Set(Provider.allCases)
    var onSnapshotArrived: ((Provider, ProviderSnapshot) -> Void)?

    private var tickTimer: Timer?
    private var popoverOpen = false
    private var sleeping = false
    private var pathMonitor: NWPathMonitor?
    private var networkWasDown = false
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []

    init(paths: AppPaths = AppPaths(), claude: ClaudeSource? = nil, codex: CodexSource? = nil, github: GitHubSource? = nil) {
        self.paths = paths
        self.claude = claude ?? ClaudeSource(paths: paths)
        self.codex = codex ?? CodexSource(paths: paths)
        self.github = github ?? GitHubSource(paths: paths)
        sources = [self.claude, self.codex, self.github]
        for source in sources {
            // Views observe the model; a change in any source re-renders them.
            source.objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
            let provider = source.provider
            source.onUpdate = { [weak self] snapshot in self?.sourceDidUpdate(provider, snapshot) }
        }
    }

    func source(_ provider: Provider) -> any UsageSource {
        switch provider {
        case .claude: return claude
        case .codex: return codex
        case .github: return github
        }
    }

    func start() {
        sources.forEach { $0.start() }
        observeSystem()
        scheduleTick()
    }

    func setActiveProviders(_ active: Set<Provider>) {
        if activeProviders != active { activeProviders = active }
        for source in sources { source.setActive(active.contains(source.provider)) }
    }

    func isActive(_ p: Provider) -> Bool { activeProviders.contains(p) }
    func status(_ p: Provider) -> ProviderStatus { source(p).status }
    func display(_ id: ItemID) -> WindowDisplay { source(id.provider).display(id.window, now: now) }
    /// True when the last attempt failed and the shown values are older.
    func isStale(_ p: Provider) -> Bool { source(p).status.isStale }
    func dailyLog(_ p: Provider) -> DailyUsageLog? { source(p).dailyLog }

    private func sourceDidUpdate(_ provider: Provider, _ snapshot: ProviderSnapshot?) {
        now = Date()
        if let snapshot { onSnapshotArrived?(provider, snapshot) }
        scheduleTick()
    }

    // MARK: Panel

    func popoverDidOpen(_ provider: Provider) {
        popoverOpen = true
        now = Date()
        sources.forEach { $0.panelDidOpen(showing: provider) }
        scheduleTick()
    }

    func popoverDidClose() {
        popoverOpen = false
        sources.forEach { $0.panelDidClose() }
        scheduleTick()
    }

    func manualRefresh(_ provider: Provider?) {
        for source in sources where provider == nil || source.provider == provider { source.refreshNow() }
        now = Date()
    }

    // MARK: Display clock

    /// Wakes up only when something visible can change: the next reset time, or every
    /// 30 s while a panel shows relative times.
    private func scheduleTick() {
        tickTimer?.invalidate()
        guard !sleeping else { return }
        let current = Date()
        var next: TimeInterval = .infinity
        for source in sources {
            for w in source.status.snapshot?.windows.values ?? [:].values {
                if let r = w.resetsAt, r > current { next = min(next, r.timeIntervalSince(current) + 0.5) }
            }
        }
        if popoverOpen { next = min(next, 30) }
        guard next.isFinite else { return }
        tickTimer = scheduleTimer(after: max(1, next), tolerance: popoverOpen ? 2 : 1) { [weak self] in
            self?.now = Date()
            self?.scheduleTick()
        }
    }

    // MARK: Sleep, wake, clock, network

    private func observeSystem() {
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sleeping = true
                self.tickTimer?.invalidate()
                self.sources.forEach { $0.willSleep() }
            }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sleeping = false
                self.now = Date()
                self.sources.forEach { $0.didWake() }
                self.scheduleTick()
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.now = Date()
                self.scheduleTick()
                self.sources.forEach { $0.clockDidChange() }
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
                            self.sources.forEach { $0.networkDidReturn() }
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
