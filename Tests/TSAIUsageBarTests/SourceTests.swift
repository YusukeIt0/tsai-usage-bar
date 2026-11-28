import XCTest
@testable import TSAIUsageBar
import UsageCore

/// A value shared with the replaced network calls, which run off the main actor.
final class Shared<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

/// Temporary support folder and defaults, removed after each test.
@MainActor
class SourceTestCase: XCTestCase {
    var dir: URL!
    var paths: AppPaths!
    var defaults: UserDefaults!
    private var suite = ""

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        paths = AppPaths(supportDirectory: dir)
        suite = "tsai-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
        defaults.removePersistentDomain(forName: suite)
    }

    /// Whole seconds, as stored files keep them.
    var now: Date { Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)) }

    func snapshot(used: Double = 40, credits: Int? = nil, amounts: (used: Double, included: Double, charged: Double)? = nil) -> ProviderSnapshot {
        var w = UsageWindow(usedPercent: used, resetsAt: now.addingTimeInterval(86_400))
        var kind = WindowKind.sevenDay
        if let amounts {
            kind = .month
            w.usedAmount = amounts.used
            w.includedAmount = amounts.included
            w.chargedAmount = amounts.charged
        }
        var s = ProviderSnapshot(windows: [kind: w], fetchedAt: now)
        s.resetCredits = credits.map { ResetCredits(available: $0, earliestExpiry: nil) }
        return s
    }

    /// Runs `action` and waits until the source reports the read as finished.
    func whenUpdated<S: UsageSource>(_ source: S, _ action: () -> Void) async {
        let done = expectation(description: "update")
        let previous = source.onUpdate
        source.onUpdate = { snap in
            previous?(snap)
            done.fulfill()
        }
        action()
        await fulfillment(of: [done], timeout: 5)
        source.onUpdate = previous
    }

    /// Lets queued tasks run (for checking that nothing happened).
    func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

final class CodexSourceTests: SourceTestCase {
    func testFailureKeepsLastValuesAsStale() async {
        let results = Shared<[Result<ProviderSnapshot, ProviderError>]>([.success(snapshot(used: 40)), .failure(.timedOut)])
        let codex = CodexSource(paths: paths, defaults: defaults) { _ in
            let r = results.value.removeFirst()
            return r
        }
        await whenUpdated(codex) { codex.refresh(force: true) }
        XCTAssertEqual(codex.status.snapshot?[.sevenDay]?.usedPercent, 40)
        XCTAssertFalse(codex.status.isStale)
        XCTAssertNotNil(SnapshotStore.load(paths.snapshotURL(.codex)), "saved for the next launch")
        await whenUpdated(codex) { codex.refresh(force: true) }
        XCTAssertEqual(codex.status.snapshot?[.sevenDay]?.usedPercent, 40)
        XCTAssertTrue(codex.status.isStale)
        XCTAssertEqual(codex.status.lastError, .timedOut)
        XCTAssertEqual(codex.status.consecutiveFailures, 1)
    }

    func testOverlappingRefreshesAreMerged() async {
        let reads = Shared(0)
        let codex = CodexSource(paths: paths, defaults: defaults) { [snap = snapshot()] _ in
            reads.value += 1
            return .success(snap)
        }
        await whenUpdated(codex) {
            codex.refresh(force: true)
            codex.refresh(force: true)
            codex.refreshNow()
        }
        await settle()
        XCTAssertEqual(reads.value, 1)
    }

    func testInactiveSourceDoesNotRead() async {
        let reads = Shared(0)
        let codex = CodexSource(paths: paths, defaults: defaults) { [snap = snapshot()] _ in
            reads.value += 1
            return .success(snap)
        }
        codex.setActive(false)
        codex.refreshNow()
        codex.networkDidReturn()
        await settle()
        XCTAssertEqual(reads.value, 0)
        XCTAssertFalse(codex.status.isFetching)
    }

    func testResetCreditArrivalIsNotifiedOnce() async {
        let counts = Shared([1, 2, 2, 3])
        let codex = CodexSource(paths: paths, defaults: defaults) { [self] _ in
            let n = counts.value.removeFirst()
            return .success(await MainActor.run { snapshot(credits: n) })
        }
        var notified: [Int] = []
        codex.onResetCreditArrived = { notified.append($0) }
        codex.notifyResetCredits = true
        for _ in 0..<3 { await whenUpdated(codex) { codex.refresh(force: true) } }
        XCTAssertEqual(notified, [2], "the first count is a baseline; the same count again is not an arrival")
        codex.notifyResetCredits = false
        await whenUpdated(codex) { codex.refresh(force: true) }
        XCTAssertEqual(notified, [2], "off in Settings: no notification")
    }

    func testExpiryDetailsAreReadOnlyWhileAPanelIsOpen() async {
        let details = Shared<[Bool]>([])
        let codex = CodexSource(paths: paths, defaults: defaults) { [snap = snapshot()] d in
            details.value.append(d)
            return .success(snap)
        }
        await whenUpdated(codex) { codex.refresh(force: true) }
        codex.panelDidOpen(showing: .claude) // any panel counts
        await whenUpdated(codex) { codex.refresh(force: true) }
        XCTAssertEqual(details.value, [false, true])
    }
}

final class GitHubSourceTests: SourceTestCase {
    static let calendar = ContributionCalendar(
        weeks: [[ContributionDay(date: "2026-11-22", count: 3, level: 2, weekday: 0)]], totalContributions: 3,
        fetchedAt: Date(timeIntervalSince1970: 1_795_000_000))

    func make(token: Bool = true, usage: [Result<ProviderSnapshot, ProviderError>] = [],
              reads: Shared<Int> = Shared(0), forgotten: Shared<Bool> = Shared(false),
              contributions: [Result<ContributionCalendar, ProviderError>] = [.success(calendar)]) -> GitHubSource {
        let queue = Shared(usage)
        let calendars = Shared(contributions)
        return GitHubSource(paths: paths,
                            readUsage: { reads.value += 1; return queue.value.removeFirst() },
                            readDays: { keys in .success(.init(amounts: Dictionary(uniqueKeysWithValues: keys.map { ($0, 0.3) }), included: 18)) },
                            readContributions: { calendars.value.count > 1 ? calendars.value.removeFirst() : calendars.value[0] },
                            hasToken: { token },
                            forgetToken: { forgotten.value = true },
                            login: token ? "someone" : nil)
    }

    func testNotConnectedDoesNotRead() async {
        let reads = Shared(0)
        let github = make(token: false, reads: reads)
        github.refreshNow()
        await settle()
        XCTAssertEqual(reads.value, 0)
        XCTAssertEqual(github.status.lastError, .notSignedIn)
        XCTAssertEqual(github.status.consecutiveFailures, 0)
    }

    func testBudgetAppliesWithoutReadingAgain() async {
        let reads = Shared(0)
        let github = make(usage: [.success(snapshot(used: 100, amounts: (15, 12, 3)))], reads: reads)
        await whenUpdated(github) { github.refreshNow() }
        XCTAssertEqual(github.display(.month, now: Date()).percent(mode: .used), 100)
        github.budgetUSD = 10
        await settle()
        XCTAssertEqual(reads.value, 1)
        XCTAssertEqual(github.display(.month, now: Date()).percent(mode: .used), 68) // 15 of 12 + 10
    }

    func testBudgetReadsAgainWhenSavedValuesHaveNoAmounts() async throws {
        try SnapshotStore.save(snapshot(used: 50), to: paths.snapshotURL(.github)) // as saved by 0.1.6
        let reads = Shared(0)
        let github = make(usage: [.success(snapshot(used: 100, amounts: (15, 12, 3)))], reads: reads)
        await whenUpdated(github) { github.budgetUSD = 10 }
        XCTAssertEqual(reads.value, 1)
    }

    func testDailyDaysAreReadOnceAndStored() async throws {
        let github = make()
        let day = GitHubDailyCache.utcKey(Date().addingTimeInterval(-10 * 86_400))
        github.loadDays([day])
        for _ in 0..<50 where github.daily.amounts[day] == nil { await Task.yield(); try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(github.daily.amounts[day], 0.3)
        XCTAssertEqual(GitHubDailyStore.load(paths: paths).amounts[day], 0.3)
        XCTAssertEqual(github.daily.needsRead([day], now: Date()), [], "past days are not read again")
    }

    func testDisconnectForgetsTokenAndFiles() async throws {
        let forgotten = Shared(false)
        let github = make(usage: [.success(snapshot(used: 10, amounts: (1, 12, 0)))], forgotten: forgotten)
        await whenUpdated(github) { github.refreshNow() }
        try GitHubDailyStore.save(GitHubDailyCache(), paths: paths)
        XCTAssertTrue(FileManager.default.fileExists(atPath: ContributionStore.url(paths: paths).path))
        github.disconnect()
        XCTAssertTrue(forgotten.value)
        XCTAssertNil(github.login)
        XCTAssertNil(github.status.snapshot)
        XCTAssertEqual(github.status.lastError, .notSignedIn)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.snapshotURL(.github).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: GitHubDailyStore.url(paths: paths).path))
        XCTAssertNil(github.contributions)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ContributionStore.url(paths: paths).path))
    }

    func testContributionsAreReadWithUsageStoredAndKeptOnFailure() async {
        let github = make(usage: [.success(snapshot(used: 10)), .success(snapshot(used: 20))],
                          contributions: [.success(Self.calendar), .failure(.failed(nil))])
        await whenUpdated(github) { github.refreshNow() }
        XCTAssertEqual(github.contributions, Self.calendar)
        XCTAssertEqual(ContributionStore.load(paths: paths), Self.calendar)
        await whenUpdated(github) { github.refreshNow() }
        XCTAssertEqual(github.contributions, Self.calendar, "a failed read keeps the last calendar")
        XCTAssertTrue(github.contributionsFailed)
        // Shown at once on the next launch.
        XCTAssertEqual(make().contributions, Self.calendar)
    }
}

final class ClaudeSourceTests: SourceTestCase {
    func testPauseFlagFollowsActive() {
        let claude = ClaudeSource(paths: paths)
        claude.setActive(false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.claudePausedURL.path))
        claude.setActive(true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.claudePausedURL.path))
    }

    func testReloadPicksUpRelayValues() async throws {
        let claude = ClaudeSource(paths: paths)
        XCTAssertNil(claude.status.snapshot)
        let snap = snapshot(used: 12)
        try SnapshotStore.save(snap, to: paths.snapshotURL(.claude))
        var received: ProviderSnapshot?
        claude.onUpdate = { received = $0 }
        claude.reload()
        XCTAssertEqual(claude.status.snapshot, snap)
        XCTAssertEqual(received, snap)
        // Paused: values the relay may still have written are not picked up.
        claude.setActive(false)
        try SnapshotStore.save(snapshot(used: 99), to: paths.snapshotURL(.claude))
        claude.reload()
        XCTAssertEqual(claude.status.snapshot, snap)
    }

    func testWindowIsFullAfterItsReset() {
        let claude = ClaudeSource(paths: paths)
        let past = now.addingTimeInterval(-60)
        try? SnapshotStore.save(ProviderSnapshot(windows: [.fiveHour: UsageWindow(usedPercent: 80, resetsAt: past)], fetchedAt: past),
                                to: paths.snapshotURL(.claude))
        claude.reload()
        XCTAssertEqual(claude.display(.fiveHour, now: Date()), .resetPassed(resetAt: past))
        XCTAssertEqual(claude.display(.fiveHour, now: Date()).percent(mode: .remaining), 100)
    }
}

final class UsageModelTests: SourceTestCase {
    func testRoutesToSourcesAndPausesInactiveOnes() async {
        let reads = Shared(0)
        let codex = CodexSource(paths: paths, defaults: defaults) { [snap = snapshot(used: 30)] _ in
            reads.value += 1
            return .success(snap)
        }
        let github = GitHubSource(paths: paths, readUsage: { .failure(.failed(nil)) }, readDays: { _ in .failure(.failed(nil)) },
                                  readContributions: { .failure(.notSignedIn) },
                                  hasToken: { false }, forgetToken: {}, login: nil)
        let model = UsageModel(paths: paths, codex: codex, github: github)
        var arrived: [Provider] = []
        model.onSnapshotArrived = { p, _ in arrived.append(p) }

        await whenUpdated(codex) { model.manualRefresh(.codex) }
        XCTAssertEqual(arrived, [.codex])
        XCTAssertEqual(model.display(ItemID(.codex, .sevenDay)).percent(mode: .used), 30)
        XCTAssertEqual(model.status(.codex).snapshot?[.sevenDay]?.usedPercent, 30)

        model.setActiveProviders([.codex])
        XCTAssertFalse(model.isActive(.claude))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.claudePausedURL.path))
        model.setActiveProviders([.github])
        model.manualRefresh(nil)
        await settle()
        XCTAssertEqual(reads.value, 1, "Codex is off: not read")
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.claudePausedURL.path), "Claude stays paused")
    }
}
