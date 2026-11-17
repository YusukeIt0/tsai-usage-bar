import Foundation

/// Local files owned by the app. Only rate-limit numbers and reset times are stored.
public struct AppPaths: Sendable {
    public let supportDirectory: URL

    public init(supportDirectory: URL? = nil) {
        if let supportDirectory {
            self.supportDirectory = supportDirectory
        } else if let override = ProcessInfo.processInfo.environment["TSAI_USAGEBAR_SUPPORT_DIR"], !override.isEmpty {
            self.supportDirectory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            let base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
            self.supportDirectory = base.appendingPathComponent("TSAI UsageBar", isDirectory: true)
        }
    }

    public func snapshotURL(_ provider: Provider) -> URL {
        supportDirectory.appendingPathComponent("\(provider.rawValue)-snapshot.json")
    }

    public var linkRecordURL: URL { supportDirectory.appendingPathComponent("claude-statusline-link.json") }
    /// Present while all Claude items are turned off; the relay then stores nothing.
    public var claudePausedURL: URL { supportDirectory.appendingPathComponent("claude-paused") }
    public var backupDirectory: URL { supportDirectory.appendingPathComponent("backups", isDirectory: true) }
    public var hookDirectory: URL { supportDirectory.appendingPathComponent("bin", isDirectory: true) }
    public var installedHookURL: URL { hookDirectory.appendingPathComponent("tsai-usagebar-hook") }

    public func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }
}

public enum SnapshotStore {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    public static func load(_ url: URL) -> ProviderSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(ProviderSnapshot.self, from: data)
    }

    public static func save(_ snapshot: ProviderSnapshot, to url: URL) throws {
        let data = try encoder.encode(snapshot)
        try writeAtomically(data, to: url, permissions: 0o600)
    }

    /// Applies one Claude statusLine reply that contained `rate_limits`. Each window keeps its
    /// own reception time; cached copies whose reset already passed do not replace values.
    public static func merge(_ windows: [WindowKind: UsageWindow], into existing: ProviderSnapshot?, at date: Date) -> ProviderSnapshot {
        var merged = existing?.windows ?? [:]
        for (k, v) in windows {
            // A window whose reset already passed is a cached copy from an earlier period.
            if let reset = v.resetsAt, reset <= date { continue }
            var w = v
            w.observedAt = date
            merged[k] = w
        }
        // Drop windows the latest reply no longer reports (plan without that limit).
        let reported = WindowKind.allCases.filter { windows[$0] != nil }
        for k in WindowKind.allCases where !reported.contains(k) { merged.removeValue(forKey: k) }
        return ProviderSnapshot(windows: merged, fetchedAt: date, reportedKinds: reported)
    }
}

public func writeAtomically(_ data: Data, to url: URL, permissions: Int? = nil) throws {
    let dir = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).\(ProcessInfo.processInfo.processIdentifier).tmp")
    try data.write(to: tmp)
    if let permissions {
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: tmp.path)
    }
    if rename(tmp.path, url.path) != 0 {
        try? FileManager.default.removeItem(at: tmp)
        throw CocoaError(.fileWriteUnknown)
    }
}

/// Darwin notification posted by the hook after it stores new Claude values.
public enum NotifyName {
    public static let claudeUpdated = "io.github.yusukeit0.tsai-usagebar.claude-updated"
}
