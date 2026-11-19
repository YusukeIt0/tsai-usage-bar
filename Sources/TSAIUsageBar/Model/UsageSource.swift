import Combine
import Foundation
import UsageCore

/// One service the app reads.
///
/// Everything specific to a service lives in its source: how and when it is read, sign-in,
/// stored files and display rules. `UsageModel` only forwards app-wide events (items turned
/// on or off, panel opened, sleep and wake, clock and network changes) to every source.
/// Adding a service means adding a source and registering it in `UsageModel`.
@MainActor
protocol UsageSource: ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    var provider: Provider { get }
    var status: ProviderStatus { get }
    /// Per-day share of the 7-day window, for services whose history the app records.
    var dailyLog: DailyUsageLog? { get }
    /// Called after every read or reload; carries the snapshot when new values arrived.
    var onUpdate: ((ProviderSnapshot?) -> Void)? { get set }

    func start()
    /// False when all of the service's menu bar items are off: nothing is read or stored.
    func setActive(_ active: Bool)
    /// What to show for one window, with the service's own rules applied.
    func display(_ window: WindowKind, now: Date) -> WindowDisplay
    /// The ↻ button.
    func refreshNow()
    /// Any panel opened; `showing` is the service whose panel it is.
    func panelDidOpen(showing: Provider)
    func panelDidClose()
    func willSleep()
    func didWake()
    func clockDidChange()
    func networkDidReturn()
}

extension UsageSource {
    var dailyLog: DailyUsageLog? { nil }
    func display(_ window: WindowKind, now: Date) -> WindowDisplay {
        WindowDisplay.evaluate(status.snapshot, window, now: now)
    }
    func panelDidClose() {}
    func willSleep() {}
    func clockDidChange() {}
    func networkDidReturn() {}
}

/// Runs `action` once after `delay` seconds on the main run loop (survives menu tracking).
@MainActor
func scheduleTimer(after delay: TimeInterval, tolerance: TimeInterval, _ action: @escaping @MainActor () -> Void) -> Timer {
    let t = Timer(timeInterval: delay, repeats: false) { _ in
        Task { @MainActor in action() }
    }
    t.tolerance = tolerance
    RunLoop.main.add(t, forMode: .common)
    return t
}
