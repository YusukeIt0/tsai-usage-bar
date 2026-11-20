import Foundation

/// Where a panel screenshot is saved and what it is called. The folder follows the Mac's own
/// screenshot setting (Screenshot app → Options → Save to), so it lands next to ⌘⇧4 captures.
public enum ScreenshotFile {
    /// Folder from the `location` value of `com.apple.screencapture`, or the Desktop (macOS's
    /// default) when it is unset or isn't an existing folder.
    public static func folder(location: String?, home: URL, isDirectory: (URL) -> Bool) -> URL {
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        guard var path = location?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { return desktop }
        if path == "~" {
            path = home.path
        } else if path.hasPrefix("~/") {
            path = home.appendingPathComponent(String(path.dropFirst(2))).path
        }
        guard path.hasPrefix("/") else { return desktop }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        return isDirectory(url) ? url : desktop
    }

    /// `TSAI UsageBar Claude Code 2026-11-21 5.29.51.png`, in the style of macOS screenshots.
    /// Adds ` (2)`, ` (3)`, … when a file with that name already exists.
    public static func name(service: String, date: Date, timeZone: TimeZone = .current,
                            exists: (String) -> Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd H.mm.ss"
        let base = "TSAI UsageBar \(service) \(f.string(from: date))"
        var candidate = "\(base).png"
        var n = 2
        while exists(candidate) {
            candidate = "\(base) (\(n)).png"
            n += 1
        }
        return candidate
    }
}
