import Foundation

/// Per-day usage built from successive official values of one window.
///
/// Claude Code and Codex report only the current used percent of each window, never past
/// days, so the app records how much the 7-day window grew on each local calendar day.
/// Days before recording started are absent (not zero).
public struct DailyUsageLog: Codable, Equatable, Sendable {
    /// Local calendar day ("yyyy-MM-dd") → percent of the window used that day.
    public var days: [String: Double]
    /// The last value seen, to compute the next increase.
    public var last: UsageWindow?
    /// First day with a recorded baseline; earlier days have no data.
    public var since: String?

    public static let keepDays = 120

    public init(days: [String: Double] = [:], last: UsageWindow? = nil, since: String? = nil) {
        self.days = days
        self.last = last
        self.since = since
    }

    /// Adds the increase between the last value and `window` to the day of `date`.
    /// - Same window (same reset time): the increase since the last value.
    /// - A new window (reset time moved on): its whole value, used since it started.
    /// - First value ever: only a baseline; earlier usage is unknown.
    public mutating func record(_ window: UsageWindow, at date: Date, calendar: Calendar = .current) {
        let day = Self.dayKey(date, calendar: calendar)
        if let last {
            var increase: Double = 0
            if Self.sameWindow(last, window) {
                increase = max(0, window.usedPercent - last.usedPercent)
            } else if let newReset = window.resetsAt, let oldReset = last.resetsAt, newReset > oldReset {
                increase = window.usedPercent
            }
            if increase > 0 { days[day, default: 0] += increase }
        } else if since == nil {
            since = day
        }
        last = window
        prune(before: calendar.date(byAdding: .day, value: -Self.keepDays, to: date) ?? date, calendar: calendar)
    }

    /// Values for `count` consecutive days ending at `end`; nil for days without data.
    public func values(endingAt end: Date, count: Int = 7, calendar: Calendar = .current) -> [(day: Date, percent: Double?)] {
        (0..<count).reversed().compactMap { offset -> (Date, Double?)? in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: end)) else { return nil }
            let key = Self.dayKey(d, calendar: calendar)
            if let v = days[key] { return (d, v) }
            if let since, key >= since { return (d, 0) }
            return (d, nil)
        }
    }

    /// Bar label: "12%", "<1%" for small use, nothing for zero (a baseline shows it).
    public static func barLabel(_ percent: Double) -> String {
        if percent <= 0 { return "" }
        if percent < 1 { return "<1%" }
        return "\(Int(percent.rounded()))%"
    }

    /// The earliest day with data, for limiting how far back the chart can go.
    public var firstDay: String? { ([since].compactMap { $0 } + days.keys).min() }

    static func sameWindow(_ a: UsageWindow, _ b: UsageWindow) -> Bool {
        guard let x = a.resetsAt, let y = b.resetsAt else { return false }
        return abs(x.timeIntervalSince(y)) < 120 // tolerate rounding of reported reset times
    }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    mutating func prune(before cutoff: Date, calendar: Calendar) {
        let key = Self.dayKey(cutoff, calendar: calendar)
        days = days.filter { $0.key >= key }
        if let s = since, s < key { since = key }
    }
}

public enum DailyUsageStore {
    public static func url(_ provider: Provider, paths: AppPaths) -> URL {
        paths.supportDirectory.appendingPathComponent("\(provider.rawValue)-daily.json")
    }

    public static func load(_ provider: Provider, paths: AppPaths) -> DailyUsageLog {
        guard let data = try? Data(contentsOf: url(provider, paths: paths)) else { return DailyUsageLog() }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return (try? d.decode(DailyUsageLog.self, from: data)) ?? DailyUsageLog()
    }

    public static func save(_ log: DailyUsageLog, _ provider: Provider, paths: AppPaths) throws {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        try writeAtomically(try e.encode(log), to: url(provider, paths: paths), permissions: 0o600)
    }

    /// Records a new 7-day value for a provider (read, update, write).
    public static func record(_ window: UsageWindow?, for provider: Provider, at date: Date = Date(), paths: AppPaths) {
        guard let window else { return }
        var log = load(provider, paths: paths)
        let before = log
        log.record(window, at: date)
        if log != before { try? save(log, provider, paths: paths) }
    }
}
