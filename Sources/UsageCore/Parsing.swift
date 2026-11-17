import Foundation

public enum ParseError: Error, Equatable {
    case invalidJSON
    case missingRateLimits
}

// MARK: - Codex App Server

/// Parses the `result` object of `account/rateLimits/read`.
///
/// Windows are matched only by `windowDurationMins` (300 = 5 hours, 10080 = 7 days).
/// `primary` / `secondary` positions are not trusted, and other buckets or durations
/// are never substituted for the expected window.
public enum CodexRateLimitParser {
    public static let codexLimitID = "codex"

    public static func parse(result: [String: Any], fetchedAt: Date) throws -> ProviderSnapshot {
        guard let bucket = codexBucket(in: result) else { throw ParseError.missingRateLimits }
        var windows: [WindowKind: UsageWindow] = [:]
        for slot in ["primary", "secondary"] {
            guard let w = bucket[slot] as? [String: Any],
                  let minutes = intValue(w["windowDurationMins"]),
                  let kind = WindowKind.allCases.first(where: { $0.minutes == minutes }),
                  let used = doubleValue(w["usedPercent"]) else { continue }
            if windows[kind] != nil { continue } // duplicate duration: keep the first, never merge
            windows[kind] = UsageWindow(usedPercent: clampPercent(used),
                                        resetsAt: epochDate(w["resetsAt"]))
        }
        return ProviderSnapshot(windows: windows, fetchedAt: fetchedAt)
    }

    /// Picks the Codex bucket. Prefers the multi-bucket view keyed by `codex`; falls back
    /// to the legacy single view only when it is not explicitly another bucket.
    static func codexBucket(in result: [String: Any]) -> [String: Any]? {
        if let byID = result["rateLimitsByLimitId"] as? [String: Any],
           let codex = byID[codexLimitID] as? [String: Any] {
            return codex
        }
        if let single = result["rateLimits"] as? [String: Any] {
            if let id = single["limitId"] as? String, id != codexLimitID { return nil }
            return single
        }
        return nil
    }
}

// MARK: - Claude Code statusLine

/// Parses the JSON that Claude Code sends to a `statusLine` command.
/// Only `rate_limits.five_hour` and `rate_limits.seven_day` are read.
public enum ClaudeStatusLineParser {
    /// Returns only the windows present in the input. Empty when the input carries no
    /// rate limits (for example before the first response of a session).
    public static func parseWindows(_ data: Data) throws -> [WindowKind: UsageWindow] {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ParseError.invalidJSON
        }
        guard let limits = obj["rate_limits"] as? [String: Any] else { return [:] }
        var windows: [WindowKind: UsageWindow] = [:]
        let keys: [(String, WindowKind)] = [("five_hour", .fiveHour), ("seven_day", .sevenDay)]
        for (key, kind) in keys {
            guard let w = limits[key] as? [String: Any],
                  let used = doubleValue(w["used_percentage"]) else { continue }
            windows[kind] = UsageWindow(usedPercent: clampPercent(used),
                                        resetsAt: epochDate(w["resets_at"]))
        }
        return windows
    }
}

// MARK: - Helpers

func doubleValue(_ any: Any?) -> Double? {
    switch any {
    case let n as NSNumber where !(n is Bool) && CFGetTypeID(n) != CFBooleanGetTypeID():
        let d = n.doubleValue
        return d.isFinite ? d : nil
    case let s as String:
        return Double(s)
    default:
        return nil
    }
}

func intValue(_ any: Any?) -> Int? {
    guard let d = doubleValue(any), d == d.rounded() else { return nil }
    return Int(d)
}

/// Accepts Unix seconds, Unix milliseconds, or an ISO 8601 string.
func epochDate(_ any: Any?) -> Date? {
    if let s = any as? String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
    }
    guard let v = doubleValue(any), v > 0 else { return nil }
    return Date(timeIntervalSince1970: v > 100_000_000_000 ? v / 1000 : v)
}

func clampPercent(_ v: Double) -> Double { min(100, max(0, v)) }
