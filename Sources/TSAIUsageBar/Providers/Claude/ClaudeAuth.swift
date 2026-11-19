import AppKit
import Foundation

/// Claude Code sign-in state through the official `claude auth` command.
/// The app never reads Claude credentials itself.
enum ClaudeAuth {
    enum Status: Equatable {
        case signedIn(subscription: String?)
        case signedOut
        case notInstalled
        case unknown
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedPath: String?

    static func findClaude() -> String? {
        lock.lock(); defer { lock.unlock() }
        if let cachedPath, FileManager.default.isExecutableFile(atPath: cachedPath) { return cachedPath }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for p in ["\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "/opt/homebrew/bin/claude",
                  "/usr/local/bin/claude", "\(home)/.npm-global/bin/claude"]
        where FileManager.default.isExecutableFile(atPath: p) {
            cachedPath = p
            return p
        }
        cachedPath = ShellLookup.which("claude")
        return cachedPath
    }

    /// Runs `claude auth status --json` (about 0.2 s). Only sign-in state and plan are read.
    static func status() async -> Status {
        await Task.detached {
            guard let claude = findClaude() else { return Status.notInstalled }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: claude)
            p.arguments = ["auth", "status", "--json"]
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = CodexLocator.searchPath
            p.environment = env
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            do { try p.run() } catch { return .unknown }
            let deadline = Date().addingTimeInterval(10)
            while p.isRunning && Date() < deadline { try? await Task.sleep(nanoseconds: 50_000_000) }
            if p.isRunning { p.terminate(); return .unknown }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let loggedIn = obj["loggedIn"] as? Bool else { return .unknown }
            return loggedIn ? .signedIn(subscription: obj["subscriptionType"] as? String) : .signedOut
        }.value
    }

    /// Opens Terminal running the official `claude auth login`, which opens the browser.
    /// Terminal is used so any prompt from the login flow stays visible to the person.
    static func startLogin() {
        guard let claude = findClaude() else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tsai-usagebar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("claude-login.command")
        let quoted = "'" + claude.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let body = """
        #!/bin/sh
        \(quoted) auth login --claudeai
        rm -f "$0"
        """
        try? body.write(to: script, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        NSWorkspace.shared.open(script)
    }
}
