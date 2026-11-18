import Foundation

public enum Provider: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
    case github

    public var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .github: return "GitHub Actions"
        }
    }

    /// Windows this provider can report, in display order.
    public var windows: [WindowKind] {
        switch self {
        case .claude, .codex: return [.fiveHour, .sevenDay]
        case .github: return [.month]
        }
    }
}

/// The two usage windows the app shows. Values are never moved between kinds.
public enum WindowKind: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
    case fiveHour
    case sevenDay
    /// Calendar month (GitHub's included Actions usage for private repositories).
    case month

    /// Letter shown in the menu bar.
    public var letter: String {
        switch self {
        case .fiveHour: return "H"
        case .sevenDay: return "W"
        case .month: return "M"
        }
    }

    /// Official window length in minutes; nil when it is not a fixed length.
    public var minutes: Int? {
        switch self {
        case .fiveHour: return 300
        case .sevenDay: return 10080
        case .month: return nil
        }
    }
}

/// One menu bar item: a provider plus a window.
public struct ItemID: Hashable, Codable, CaseIterable, Sendable {
    public let provider: Provider
    public let window: WindowKind

    public init(_ provider: Provider, _ window: WindowKind) {
        self.provider = provider
        self.window = window
    }

    public static let allCases: [ItemID] = Provider.allCases.flatMap { p in p.windows.map { ItemID(p, $0) } }

    public var key: String { "\(provider.rawValue).\(window.rawValue)" }
}

public struct UsageWindow: Codable, Equatable, Sendable {
    /// 0...100, as reported by the service.
    public var usedPercent: Double
    public var resetsAt: Date?
    /// When this window's value was received. Nil means the snapshot's `fetchedAt`.
    public var observedAt: Date?
    /// For amount-based windows (GitHub Actions, USD): amount used and the included amount.
    /// Kept so the percent can be recomputed when the person changes their budget.
    public var usedAmount: Double?
    public var includedAmount: Double?

    public init(usedPercent: Double, resetsAt: Date?, observedAt: Date? = nil,
                usedAmount: Double? = nil, includedAmount: Double? = nil) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.observedAt = observedAt
        self.usedAmount = usedAmount
        self.includedAmount = includedAmount
    }
}

/// Last successfully received values for one provider.
public struct ProviderSnapshot: Codable, Equatable, Sendable {
    public var windows: [WindowKind: UsageWindow]
    /// When the values were received from the official source.
    public var fetchedAt: Date
    /// Windows included in the latest official reply. A window missing here is not offered
    /// for this account or plan (for example, plans without a 5-hour limit).
    public var reportedKinds: [WindowKind]?
    /// Codex limit-reset credits ("reset tickets"), when the service reports them.
    public var resetCredits: ResetCredits?

    public init(windows: [WindowKind: UsageWindow], fetchedAt: Date, reportedKinds: [WindowKind]? = nil) {
        self.windows = windows
        self.fetchedAt = fetchedAt
        self.reportedKinds = reportedKinds ?? WindowKind.allCases.filter { windows[$0] != nil }
    }

    /// False only when the latest official reply is known and lacks this window.
    public func offers(_ kind: WindowKind) -> Bool {
        guard let reportedKinds else { return true }
        return reportedKinds.contains(kind)
    }

    public subscript(kind: WindowKind) -> UsageWindow? { windows[kind] }
}

public enum DisplayMode: String, Codable, CaseIterable, Sendable {
    case remaining
    case used
}

/// Codex limit-reset credits from `rateLimitResetCredits`.
public struct ResetCredits: Codable, Equatable, Sendable {
    public var available: Int
    /// Earliest expiry among available credits; nil when unknown or none expire.
    public var earliestExpiry: Date?

    public init(available: Int, earliestExpiry: Date?) {
        self.available = available
        self.earliestExpiry = earliestExpiry
    }

    /// How many credits arrived since `previous`, or nil when none did. The first value
    /// seen (no previous count) is a baseline, not an arrival.
    public static func arrived(previous: Int?, current: Int) -> Int? {
        guard let previous, current > previous else { return nil }
        return current - previous
    }

    /// Keeps a known expiry when a lighter read (count only) reports the same count.
    public func keepingExpiry(from old: ResetCredits?) -> ResetCredits {
        guard earliestExpiry == nil, let old, old.available == available else { return self }
        return ResetCredits(available: available, earliestExpiry: old.earliestExpiry)
    }
}
