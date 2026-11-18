import Foundation

/// What to show for one window, derived from the last received values only.
public enum WindowDisplay: Equatable, Sendable {
    /// No value has been received for this window.
    case unavailable
    /// The reset time has passed and no newer value has been received yet.
    /// The old value is no longer valid, and a new one is not invented.
    case awaitingUpdateAfterReset(resetAt: Date)
    /// Claude Code only (owner decision, 2026-11-18): after the reset time the window is
    /// back to full. Claude Code drops a window once it resets and starts a new one with
    /// the next use, so nothing is used until then.
    case resetPassed(resetAt: Date)
    case value(usedPercent: Double, resetsAt: Date?)

    public static func evaluate(_ snapshot: ProviderSnapshot?, _ kind: WindowKind, now: Date,
                                fullAfterReset: Bool = false) -> WindowDisplay {
        guard let snapshot, let window = snapshot[kind] else { return .unavailable }
        // A value belongs to the window ending at `resetsAt`. Once that time passes the
        // value is outdated, even if a client re-sent its cached copy afterwards.
        if let reset = window.resetsAt, now >= reset {
            return fullAfterReset ? .resetPassed(resetAt: reset) : .awaitingUpdateAfterReset(resetAt: reset)
        }
        return .value(usedPercent: window.usedPercent, resetsAt: window.resetsAt)
    }

    /// Integer percentage for the chosen mode, or nil when there is no value.
    public func percent(mode: DisplayMode) -> Int? {
        let used: Double
        switch self {
        case .unavailable, .awaitingUpdateAfterReset: return nil
        case .resetPassed: used = 0
        case .value(let u, _): used = u
        }
        let usedInt = Int(used.rounded())
        let value = mode == .used ? usedInt : 100 - usedInt
        return min(100, max(0, value))
    }

    /// Menu bar label such as `H42%`, `W100%`, or `H—`.
    public func label(_ kind: WindowKind, mode: DisplayMode) -> String {
        if let p = percent(mode: mode) { return "\(kind.letter)\(p)%" }
        return "\(kind.letter)—"
    }
}
