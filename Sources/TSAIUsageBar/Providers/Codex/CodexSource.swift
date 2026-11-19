import AppKit
import UsageCore

/// Codex: queried briefly through the official `codex app-server` on a timer, when a panel
/// opens, right after a reset time, after wake and when the network returns.
@MainActor
final class CodexSource: ObservableObject, UsageSource {
    typealias Reader = @Sendable (_ details: Bool) async -> Result<ProviderSnapshot, ProviderError>

    let provider = Provider.codex
    @Published private(set) var status = ProviderStatus()
    @Published private(set) var daily: DailyUsageLog
    @Published private(set) var signingIn = false
    var onUpdate: ((ProviderSnapshot?) -> Void)?
    /// Called with the remaining count when limit-reset credits arrive and notifying is on.
    var onResetCreditArrived: ((Int) -> Void)?
    /// From Settings: notify when Codex reset credits arrive.
    var notifyResetCredits = false

    var dailyLog: DailyUsageLog? { daily }

    private let paths: AppPaths
    private let read: Reader
    private let credits: ResetCreditTracker
    private let policy = FetchPolicy()
    private var timer: Timer?
    private var active = true
    private var panelOpen = false
    private var sleeping = false

    init(paths: AppPaths, defaults: UserDefaults = .standard,
         read: @escaping Reader = { await CodexClient.readRateLimits(details: $0) }) {
        self.paths = paths
        self.read = read
        credits = ResetCreditTracker(defaults: defaults)
        daily = DailyUsageStore.load(.codex, paths: paths)
        status.snapshot = SnapshotStore.load(paths.snapshotURL(.codex))
    }

    func start() { refresh(force: true) }

    func setActive(_ active: Bool) {
        guard active != self.active else { return }
        self.active = active
        if active { refresh(force: true) } else { timer?.invalidate() }
    }

    func refreshNow() { refresh(force: true) }

    func panelDidOpen(showing: Provider) {
        panelOpen = true
        guard showing == .codex else { return }
        if policy.shouldFetchOnDemand(now: Date(), lastAttempt: status.lastAttempt, lastSuccess: status.snapshot?.fetchedAt) {
            refresh(force: false)
        } else {
            schedule()
        }
    }

    func panelDidClose() {
        panelOpen = false
        schedule()
    }

    func willSleep() {
        sleeping = true
        timer?.invalidate()
    }

    func didWake() {
        sleeping = false
        // Give the network a moment to come back before asking Codex.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            MainActor.assumeIsolated { self.refresh(force: true) }
        }
    }

    func clockDidChange() { schedule() }

    func networkDidReturn() { refresh(force: true) }

    // MARK: Reading

    func refresh(force: Bool) {
        guard active else { return } // all Codex items off: no queries
        guard !status.isFetching else { return } // merge overlapping requests
        if !force, let last = status.lastAttempt, Date().timeIntervalSince(last) < policy.minimumGap {
            schedule()
            return
        }
        status.begin(at: Date())
        timer?.invalidate()
        let details = panelOpen
        let read = read
        Task {
            let result = await Task.detached { await read(details) }.value
            self.apply(result)
        }
    }

    private func apply(_ result: Result<ProviderSnapshot, ProviderError>) {
        switch result {
        case .success(var snap):
            snap.resetCredits = snap.resetCredits?.keepingExpiry(from: status.snapshot?.resetCredits)
            if credits.observe(snap.resetCredits) != nil, notifyResetCredits, let c = snap.resetCredits {
                onResetCreditArrived?(c.available)
            }
            status.succeed(snap)
            try? paths.ensureDirectory()
            try? SnapshotStore.save(snap, to: paths.snapshotURL(.codex))
            DailyUsageStore.record(snap[.sevenDay], for: .codex, paths: paths)
            daily = DailyUsageStore.load(.codex, paths: paths)
            onUpdate?(snap)
        case .failure(let e):
            status.fail(e)
            onUpdate?(nil)
        }
        schedule()
    }

    private func schedule() {
        timer?.invalidate()
        guard !sleeping, !status.isFetching, active else { return }
        // Without the codex command or a sign-in there is nothing to poll until the person acts.
        if status.lastError == .notInstalled || status.lastError == .notSignedIn {
            if !panelOpen { return }
        }
        let resets = status.snapshot?.windows.values.compactMap(\.resetsAt) ?? []
        let delay = policy.nextDelay(now: Date(), lastAttempt: status.lastAttempt,
                                     consecutiveFailures: status.consecutiveFailures,
                                     popoverOpen: panelOpen, resetTimes: resets)
        timer = scheduleTimer(after: delay, tolerance: min(10, delay * 0.1)) { [weak self] in
            self?.refresh(force: false)
        }
    }

    // MARK: Sign-in

    /// Official ChatGPT sign-in in the browser, then reads again.
    func signIn() {
        guard !signingIn else { return }
        signingIn = true
        Task {
            let r = await Task.detached {
                await CodexClient.signIn { url in DispatchQueue.main.async { NSWorkspace.shared.open(url) } }
            }.value
            self.signingIn = false
            if case .success = r { self.refresh(force: true) }
        }
    }
}
