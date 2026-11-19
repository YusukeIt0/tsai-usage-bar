import AppKit
import UserNotifications
import UsageCore

/// macOS notifications for arriving Codex limit-reset credits.
/// Permission is asked only when the person turns the option on. Because builds are
/// ad-hoc signed, macOS may forget the permission after an update; Settings then shows it.
@MainActor
final class Notifier: ObservableObject {
    enum Permission: Equatable { case unknown, allowed, denied, notAsked }

    @Published private(set) var permission: Permission = .unknown

    func refreshPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            let p: Permission
            switch s.authorizationStatus {
            case .authorized, .provisional, .ephemeral: p = .allowed
            case .denied: p = .denied
            case .notDetermined: p = .notAsked
            @unknown default: p = .unknown
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { self.permission = p } }
        }
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self.refreshPermission() } }
        }
    }

    func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    func postResetCreditArrived(remaining: Int, strings: Strings) {
        let content = UNMutableNotificationContent()
        content.title = "Codex"
        content.body = strings.resetCreditArrived(remaining)
        content.sound = .default
        let req = UNNotificationRequest(identifier: "codex-reset-credit-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

/// `--notification-status` prints the permission; `--notification-test` also asks for it and
/// posts a sample notification. Used to check whether permission survives an update.
enum NotificationCheck {
    static func run(post: Bool) -> Never {
        let center = UNUserNotificationCenter.current()
        let done = DispatchSemaphore(value: 0)
        func report() {
            center.getNotificationSettings { s in
                print("bundle:", Bundle.main.bundleIdentifier ?? "-", "authorization:", s.authorizationStatus.rawValue,
                      "(0 notDetermined, 1 denied, 2 authorized)")
                done.signal()
            }
        }
        if post {
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                if granted {
                    let c = UNMutableNotificationContent()
                    c.title = "TSAI UsageBar"
                    c.body = "Test notification"
                    center.add(UNNotificationRequest(identifier: "test", content: c, trigger: nil)) { _ in report() }
                } else {
                    report()
                }
            }
        } else {
            report()
        }
        while done.wait(timeout: .now() + 0.1) == .timedOut { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        exit(0)
    }
}
