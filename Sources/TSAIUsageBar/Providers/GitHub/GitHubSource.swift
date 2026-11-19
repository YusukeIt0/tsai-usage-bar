import AppKit
import UsageCore

/// GitHub Actions: this month's included usage for private repositories, read about hourly
/// from GitHub's billing summary, plus per-day usage for the chart.
@MainActor
final class GitHubSource: ObservableObject, UsageSource {
    typealias UsageReader = @Sendable () async -> Result<ProviderSnapshot, ProviderError>
    typealias DailyReader = @Sendable ([String]) async -> Result<GitHubDailyClient.Result, ProviderError>

    let provider = Provider.github
    /// GitHub's "Budgets and alerts" page for the signed-in personal account.
    static let budgetsURL = URL(string: "https://github.com/settings/billing/budgets")!
    @Published private(set) var status = ProviderStatus()
    @Published private(set) var login: String?
    /// Shown while connecting: the code the person enters in the browser.
    @Published private(set) var deviceCode: String?
    @Published private(set) var connectError: GitHubAuth.AuthError?
    /// Per-day private Actions usage read from GitHub for the chart.
    @Published private(set) var daily: GitHubDailyCache
    @Published private(set) var dailyLoading = false
    @Published private(set) var dailyFailed = false
    /// Monthly Actions budget from Settings; changes the percent without reading again.
    @Published var budgetUSD: Double? {
        didSet {
            // Values saved by 0.1.6 have no amounts; read again so the budget can apply.
            let w = status.snapshot?.windows[.month]
            if budgetUSD != nil, w?.usedAmount == nil || w?.chargedAmount == nil { refresh(force: true) }
        }
    }
    var onUpdate: ((ProviderSnapshot?) -> Void)?

    private let paths: AppPaths
    private let readUsage: UsageReader
    private let readDays: DailyReader
    private let hasToken: () -> Bool
    private let forgetToken: () -> Void
    private let policy = GitHubFetchPolicy()
    private var timer: Timer?
    private var connectTask: Task<Void, Never>?
    private var active = true
    private var sleeping = false

    init(paths: AppPaths,
         readUsage: @escaping UsageReader = { await GitHubClient.readUsage() },
         readDays: @escaping DailyReader = { await GitHubDailyClient.read(days: $0) },
         hasToken: @escaping () -> Bool = { GitHubAuth.load() != nil },
         forgetToken: @escaping () -> Void = { GitHubAuth.remove() },
         login: String? = GitHubAuth.load()?.login) {
        self.paths = paths
        self.readUsage = readUsage
        self.readDays = readDays
        self.hasToken = hasToken
        self.forgetToken = forgetToken
        self.login = login
        daily = GitHubDailyStore.load(paths: paths)
        status.snapshot = SnapshotStore.load(paths.snapshotURL(.github))
    }

    /// The month window measured against free usage plus the budget, when one is set.
    func display(_ window: WindowKind, now: Date) -> WindowDisplay {
        var snapshot = status.snapshot
        if var s = snapshot, let w = s.windows[.month] {
            s.windows[.month] = GitHubActionsUsage.applyingBudget(w, budgetUSD: budgetUSD)
            snapshot = s
        }
        return WindowDisplay.evaluate(snapshot, window, now: now)
    }

    func start() { refresh(force: false) }

    func setActive(_ active: Bool) {
        guard active != self.active else { return }
        self.active = active
        if active { refresh(force: true) } else { timer?.invalidate() }
    }

    func refreshNow() { refresh(force: true) }

    func panelDidOpen(showing: Provider) {
        guard showing == .github else { return }
        if policy.shouldFetchOnPanelOpen(now: Date(), lastAttempt: status.lastAttempt) { refresh(force: true) }
    }

    func willSleep() { sleeping = true }

    func didWake() {
        sleeping = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            MainActor.assumeIsolated { self.refresh(force: false) }
        }
    }

    // MARK: Reading

    func refresh(force: Bool) {
        guard active, !status.isFetching, !sleeping else { return }
        guard hasToken() else {
            status.lastError = .notSignedIn
            return
        }
        guard policy.shouldFetch(force: force, now: Date(), lastAttempt: status.lastAttempt) else {
            schedule()
            return
        }
        status.begin(at: Date())
        timer?.invalidate()
        let readUsage = readUsage
        Task {
            let result = await readUsage()
            switch result {
            case .success(let snap):
                self.status.succeed(snap)
                try? self.paths.ensureDirectory()
                try? SnapshotStore.save(snap, to: self.paths.snapshotURL(.github))
                self.onUpdate?(snap)
            case .failure(let e):
                self.status.fail(e)
                if e == .notSignedIn { self.login = nil }
                self.onUpdate?(nil)
            }
            self.schedule()
        }
    }

    private func schedule() {
        timer?.invalidate()
        guard !sleeping, active, hasToken() else { return }
        timer = scheduleTimer(after: policy.nextDelay(consecutiveFailures: status.consecutiveFailures), tolerance: 300) { [weak self] in
            self?.refresh(force: true)
        }
    }

    /// Reads the shown days that are missing or recent. One read at a time.
    func loadDays(_ keys: [String]) {
        guard login != nil, !dailyLoading else { return }
        let needed = daily.needsRead(keys, now: Date())
        guard !needed.isEmpty else { return }
        dailyLoading = true
        let readDays = readDays
        Task {
            let result = await readDays(needed)
            self.dailyLoading = false
            switch result {
            case .success(let r):
                var cache = self.daily
                cache.apply(amounts: r.amounts, included: r.included, now: Date())
                self.daily = cache
                self.dailyFailed = false
                try? GitHubDailyStore.save(cache, paths: self.paths)
            case .failure:
                self.dailyFailed = true
            }
        }
    }

    // MARK: Connection

    /// Device flow: copies the code, opens the browser, waits for approval.
    func connect() {
        guard connectTask == nil else { return }
        connectError = nil
        connectTask = Task {
            defer {
                self.deviceCode = nil
                self.connectTask = nil
            }
            do {
                let code = try await GitHubAuth.startDeviceFlow()
                self.deviceCode = code.userCode
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code.userCode, forType: .string)
                NSWorkspace.shared.open(code.verificationURL)
                let tokens = try await GitHubAuth.waitForApproval(code)
                self.login = tokens.login
                self.status.lastError = nil
                self.refresh(force: true)
            } catch is CancellationError {
                return
            } catch let e as GitHubAuth.AuthError {
                self.connectError = e
            } catch {
                self.connectError = .network
            }
        }
    }

    func cancelConnect() {
        connectTask?.cancel()
        connectTask = nil
        deviceCode = nil
    }

    /// Forgets the token on this Mac. The authorization itself can be revoked on GitHub.
    func disconnect() {
        forgetToken()
        timer?.invalidate()
        login = nil
        status = ProviderStatus(lastError: .notSignedIn)
        daily = GitHubDailyCache()
        GitHubDailyStore.remove(paths: paths)
        try? FileManager.default.removeItem(at: paths.snapshotURL(.github))
    }
}
