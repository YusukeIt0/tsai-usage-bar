import Foundation

/// Connects the app to Claude Code's `statusLine` without losing the user's own status line.
///
/// Linking replaces `statusLine` in Claude Code's user settings with the hook. The original
/// value is recorded and the hook keeps running it, so the visible status line stays the same.
/// Unlinking restores the original only while the setting still points at the hook.
public struct StatusLineLink {
    public enum State: Equatable {
        case notLinked
        case linked
        /// A link record exists but the settings now point elsewhere (changed by the user).
        case replacedByUser
    }

    public enum LinkError: Error, Equatable {
        case settingsUnreadable
        case settingsNotObject
        case hookMissing
        case writeFailed
    }

    public struct Record: Codable, Equatable {
        /// Original `statusLine` value as JSON text; nil when none was set.
        public var originalStatusLineJSON: String?
        public var settingsPath: String
        public var backupPath: String?
        public var linkedAt: Date
    }

    public static let hookArgument = "statusline"

    public let paths: AppPaths
    public let settingsURL: URL

    public init(paths: AppPaths = AppPaths(), settingsURL: URL? = nil) {
        self.paths = paths
        self.settingsURL = settingsURL ?? StatusLineLink.defaultSettingsURL()
    }

    public static func defaultSettingsURL() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["CLAUDE_CONFIG_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir).appendingPathComponent("settings.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    // MARK: State

    public func loadRecord() -> Record? {
        guard let data = try? Data(contentsOf: paths.linkRecordURL) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try? d.decode(Record.self, from: data)
    }

    public func state() -> State {
        let current = (try? readSettings())?["statusLine"]
        let pointsToHook = isHookStatusLine(current)
        if pointsToHook { return .linked }
        return loadRecord() == nil ? .notLinked : .replacedByUser
    }

    /// Description of the status line that would be kept, for the confirmation dialog.
    public func existingStatusLineCommand() -> String? {
        guard let s = (try? readSettings())?["statusLine"] as? [String: Any] else { return nil }
        return s["command"] as? String
    }

    // MARK: Link / unlink

    public func link(now: Date = Date()) throws {
        guard FileManager.default.isExecutableFile(atPath: paths.installedHookURL.path) else {
            throw LinkError.hookMissing
        }
        var settings = try readSettings()
        let current = settings["statusLine"]
        if isHookStatusLine(current) { return }

        try paths.ensureDirectory()
        let backup = try backupSettings(now: now)

        var originalJSON: String?
        if let current, !(current is NSNull) {
            let data = try JSONSerialization.data(withJSONObject: current, options: [.fragmentsAllowed, .sortedKeys])
            originalJSON = String(data: data, encoding: .utf8)
        }

        var newValue: [String: Any] = [:]
        if let old = current as? [String: Any] {
            // Keep display options such as padding and refreshInterval.
            for (k, v) in old where k != "command" && k != "type" { newValue[k] = v }
        }
        newValue["type"] = "command"
        newValue["command"] = hookCommand()
        settings["statusLine"] = newValue

        let record = Record(originalStatusLineJSON: originalJSON, settingsPath: settingsURL.path,
                            backupPath: backup?.path, linkedAt: now)
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try writeAtomically(try e.encode(record), to: paths.linkRecordURL, permissions: 0o600)
        try writeSettings(settings)
    }

    /// Restores the original status line. Leaves settings untouched if the user has since
    /// pointed `statusLine` somewhere else.
    public func unlink() throws {
        let record = loadRecord()
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            var settings = try readSettings()
            if isHookStatusLine(settings["statusLine"]) {
                if let json = record?.originalStatusLineJSON,
                   let data = json.data(using: .utf8),
                   let original = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                    settings["statusLine"] = original
                } else {
                    settings.removeValue(forKey: "statusLine")
                }
                try writeSettings(settings)
            }
        }
        try? FileManager.default.removeItem(at: paths.linkRecordURL)
    }

    /// The original command the hook should keep running, if any.
    public func originalCommand() -> String? {
        guard let json = loadRecord()?.originalStatusLineJSON,
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["type"] as? String ?? "command") == "command",
              let cmd = obj["command"] as? String, !cmd.isEmpty else { return nil }
        if cmd.contains(paths.installedHookURL.path) { return nil } // never call ourselves
        return cmd
    }

    // MARK: Helpers

    public func hookCommand() -> String {
        "'\(paths.installedHookURL.path.replacingOccurrences(of: "'", with: "'\\''"))' \(Self.hookArgument)"
    }

    func isHookStatusLine(_ value: Any?) -> Bool {
        guard let dict = value as? [String: Any], let cmd = dict["command"] as? String else { return false }
        return cmd.contains(paths.installedHookURL.path) || cmd.contains("tsai-usagebar-hook")
    }

    func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        guard let data = try? Data(contentsOf: settingsURL) else { throw LinkError.settingsUnreadable }
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { throw LinkError.settingsUnreadable }
        guard let dict = obj as? [String: Any] else { throw LinkError.settingsNotObject }
        return dict
    }

    func writeSettings(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: settings,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        var mode: Int?
        if let attrs = try? FileManager.default.attributesOfItem(atPath: settingsURL.path),
           let perm = attrs[.posixPermissions] as? NSNumber {
            mode = perm.intValue
        }
        do {
            try writeAtomically(data + Data("\n".utf8), to: settingsURL, permissions: mode)
        } catch {
            throw LinkError.writeFailed
        }
    }

    /// Keeps only the most recent backup.
    func backupSettings(now: Date) throws -> URL? {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return nil }
        let fm = FileManager.default
        try fm.createDirectory(at: paths.backupDirectory, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let dest = paths.backupDirectory.appendingPathComponent("claude-settings-\(f.string(from: now)).json")
        if let old = try? fm.contentsOfDirectory(at: paths.backupDirectory, includingPropertiesForKeys: nil) {
            for u in old where u.lastPathComponent.hasPrefix("claude-settings-") { try? fm.removeItem(at: u) }
        }
        try fm.copyItem(at: settingsURL, to: dest)
        return dest
    }
}
