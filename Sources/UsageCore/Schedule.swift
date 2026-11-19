import Foundation

/// Decides when Codex should be queried next. Pure so it can be tested.
public struct FetchPolicy: Sendable {
    public var backgroundInterval: TimeInterval = 180
    public var popoverInterval: TimeInterval = 60
    public var maxBackoff: TimeInterval = 30 * 60
    /// Wait a little after a reset so the service reports the new window.
    public var resetGrace: TimeInterval = 5
    /// Requests closer together than this are merged.
    public var minimumGap: TimeInterval = 10

    public init() {}

    /// Seconds until the next automatic fetch.
    public func nextDelay(now: Date,
                          lastAttempt: Date?,
                          consecutiveFailures: Int,
                          popoverOpen: Bool,
                          resetTimes: [Date]) -> TimeInterval {
        let base = popoverOpen ? popoverInterval : backgroundInterval
        var interval = base
        if consecutiveFailures > 0 {
            let factor = pow(2.0, Double(min(consecutiveFailures, 8)))
            interval = min(maxBackoff, base * factor / 2)
            interval = max(interval, base)
        }
        let sinceLast = lastAttempt.map { now.timeIntervalSince($0) } ?? .infinity
        var delay = max(0, interval - max(0, sinceLast))
        if sinceLast.isInfinite { delay = 0 }

        // Fetch right after an upcoming reset, but never sooner than the merge gap.
        if let nextReset = resetTimes.filter({ $0.addingTimeInterval(resetGrace) > now }).min() {
            let untilReset = nextReset.addingTimeInterval(resetGrace).timeIntervalSince(now)
            delay = min(delay, max(untilReset, 0))
        }
        let gapRemaining = max(0, minimumGap - max(0, sinceLast))
        return max(delay, gapRemaining)
    }

    /// True when an on-demand request (popover opened) should start a fetch.
    public func shouldFetchOnDemand(now: Date, lastAttempt: Date?, lastSuccess: Date?) -> Bool {
        guard let lastAttempt else { return true }
        if now.timeIntervalSince(lastAttempt) < minimumGap { return false }
        guard let lastSuccess else { return true }
        return now.timeIntervalSince(lastSuccess) >= 30
    }
}

/// Decides when GitHub billing usage is read. Its totals lag by hours, so hourly is enough.
public struct GitHubFetchPolicy: Sendable {
    public var interval: TimeInterval = 3600
    /// Opening the panel reads again when the last attempt is older than this.
    public var panelRefreshAge: TimeInterval = 600
    /// Failures stretch the interval up to this many times.
    public var maxBackoffFactor: Double = 4

    public init() {}

    public func shouldFetch(force: Bool, now: Date, lastAttempt: Date?) -> Bool {
        guard !force, let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= interval
    }

    public func shouldFetchOnPanelOpen(now: Date, lastAttempt: Date?) -> Bool {
        now.timeIntervalSince(lastAttempt ?? .distantPast) > panelRefreshAge
    }

    public func nextDelay(consecutiveFailures: Int) -> TimeInterval {
        interval * min(maxBackoffFactor, max(1, Double(consecutiveFailures)))
    }
}
