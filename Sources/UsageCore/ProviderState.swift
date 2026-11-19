import Foundation

/// Why the last read of a provider failed. One type for every provider, so status
/// handling (stale values, backoff) is shared; views turn it into provider-specific text.
public enum ProviderError: Error, Equatable, Sendable {
    /// The service's command-line tool is not installed (Codex).
    case notInstalled
    /// Not signed in, or the account is not connected (Codex, GitHub).
    case notSignedIn
    case timedOut
    /// The plan's included usage is not known (GitHub).
    case unknownPlan
    /// More public repositories than the app checks (GitHub).
    case tooManyRepositories
    case failed(String?)
}

/// Reading state of one provider: the last values and how the latest attempt went.
public struct ProviderStatus: Equatable, Sendable {
    public var snapshot: ProviderSnapshot?
    public var isFetching = false
    public var lastAttempt: Date?
    public var lastError: ProviderError?
    public var consecutiveFailures = 0

    public init(snapshot: ProviderSnapshot? = nil, lastError: ProviderError? = nil) {
        self.snapshot = snapshot
        self.lastError = lastError
    }

    /// The shown values are older than a failed attempt.
    public var isStale: Bool { lastError != nil && snapshot != nil }

    public mutating func begin(at date: Date) {
        isFetching = true
        lastAttempt = date
    }

    public mutating func succeed(_ snapshot: ProviderSnapshot) {
        isFetching = false
        self.snapshot = snapshot
        lastError = nil
        consecutiveFailures = 0
    }

    /// Keeps the last values; they show as stale.
    public mutating func fail(_ error: ProviderError) {
        isFetching = false
        lastError = error
        consecutiveFailures += 1
    }
}

/// Notices Codex limit-reset credits arriving. The last count is kept across launches,
/// so credits granted while the app was closed are noticed once.
public struct ResetCreditTracker {
    public static let defaultsKey = "codex.resetCredits.lastCount"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// Remembers the count and returns how many arrived since the last count seen, or nil.
    /// The first count ever seen is a baseline.
    public func observe(_ credits: ResetCredits?) -> Int? {
        guard let credits else { return nil }
        let previous = defaults.object(forKey: Self.defaultsKey) as? Int
        defaults.set(credits.available, forKey: Self.defaultsKey)
        return ResetCredits.arrived(previous: previous, current: credits.available)
    }
}
