import AppKit
import UsageCore

/// Checks GitHub Releases about once a day and can run the official installer to update.
/// Only a generic User-Agent with the app version is sent; no usage data or identifiers.
@MainActor
final class UpdateChecker: ObservableObject {
    enum InstallState: Equatable { case idle, installing, failed }

    @Published private(set) var latest: AppVersion?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var checking = false
    @Published private(set) var checkFailed = false
    @Published private(set) var installState: InstallState = .idle

    let current = AppVersion(AppInfo.version)
    private let defaults: UserDefaults
    private var timer: Timer?
    private let interval: TimeInterval = 24 * 3600

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        latest = defaults.string(forKey: "update.latest").flatMap(AppVersion.init)
        lastChecked = defaults.object(forKey: "update.lastChecked") as? Date
    }

    var updateAvailable: Bool { ReleaseInfo.isUpdate(latest: latest, current: current) }

    func start() {
        // First check shortly after launch, then about daily (also after wake, if due).
        schedule(after: dueIn() ?? 30)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule(after: max(30, self?.dueIn() ?? 30)) }
        }
    }

    private func dueIn() -> TimeInterval? {
        guard let lastChecked else { return nil }
        return max(30, interval - Date().timeIntervalSince(lastChecked))
    }

    private func schedule(after delay: TimeInterval) {
        timer?.invalidate()
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
        t.tolerance = 600
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func check() async {
        guard !checking, current != nil else { return }
        checking = true
        defer {
            checking = false
            schedule(after: interval)
        }
        var req = URLRequest(url: ReleaseInfo.latestAPI, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("TSAI-UsageBar/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let v = ReleaseInfo.latestVersion(fromJSON: data) else { checkFailed = true; return }
            latest = v
            lastChecked = Date()
            checkFailed = false
            defaults.set(v.description, forKey: "update.latest")
            defaults.set(lastChecked, forKey: "update.lastChecked")
        } catch {
            checkFailed = true
        }
    }

    /// Runs the installer from the release tag. It quits this app, replaces it, keeps settings,
    /// and starts the new version. If it fails, this app keeps running and shows the failure.
    func installUpdate() {
        guard let latest, updateAvailable, installState != .installing else { return }
        installState = .installing
        let url = ReleaseInfo.installerURL(for: latest).absoluteString
        let log = AppPaths().supportDirectory.appendingPathComponent("update.log").path
        try? AppPaths().ensureDirectory()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "/usr/bin/curl -fsSL \"$1\" | /bin/sh > \"$2\" 2>&1", "update", url, log]
        var env = ProcessInfo.processInfo.environment
        env["TSAI_USAGEBAR_VERSION"] = latest.description
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        p.terminationHandler = { proc in
            let ok = proc.terminationStatus == 0
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.installState = ok ? .idle : .failed }
            }
        }
        do { try p.run() } catch { installState = .failed }
    }
}
