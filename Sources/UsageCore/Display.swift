import Foundation

/// What to show for one window, derived from the last received values only.
public enum WindowDisplay: Equatable, Sendable {
    /// No value has been received for this window.
    case unavailable
    /// The reset time has passed and no newer value has been received yet.
    /// The old value is no longer valid, and a new one is not invented.
    case awaitingUpdateAfterReset(resetAt: Date)
    case value(usedPercent: Double, resetsAt: Date?)

    public static func evaluate(_ snapshot: ProviderSnapshot?, _ kind: WindowKind, now: Date) -> WindowDisplay {
        guard let snapshot, let window = snapshot[kind] else { return .unavailable }
        // A value belongs to the window ending at `resetsAt`. Once that time passes the
        // value is outdated, even if a client re-sent its cached copy afterwards.
        if let reset = window.resetsAt, now >= reset {
            return .awaitingUpdateAfterReset(resetAt: reset)
        }
        return .value(usedPercent: window.usedPercent, resetsAt: window.resetsAt)
    }

    /// Integer percentage for the chosen mode, or nil when there is no valid value.
    public func percent(mode: DisplayMode) -> Int? {
        guard case let .value(used, _) = self else { return nil }
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
