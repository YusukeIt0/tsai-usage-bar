import Foundation

enum CodexLocator {
    static var searchPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.npm-global/bin",
                "\(home)/.bun/bin", "/usr/bin", "/bin"].joined(separator: ":")
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cached: URL?

    /// Finds the `codex` command. GUI apps do not inherit the shell PATH, so common install
    /// locations are checked first and the login shell is asked only as a fallback.
    static func find() -> URL? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let cached, FileManager.default.isExecutableFile(atPath: cached.path) { return cached }
        for dir in searchPath.split(separator: ":") {
            let p = "\(dir)/codex"
            if FileManager.default.isExecutableFile(atPath: p) { cached = URL(fileURLWithPath: p); return cached }
        }
        for app in ["/Applications/Codex.app/Contents/Resources/codex",
                    "/Applications/ChatGPT.app/Contents/Resources/codex"] where FileManager.default.isExecutableFile(atPath: app) {
            cached = URL(fileURLWithPath: app)
            return cached
        }
        if let p = ShellLookup.which("codex") { cached = URL(fileURLWithPath: p); return cached }
        return nil
    }
}

enum ShellLookup {
    /// Asks the user's login shell for a command path (`command -v`). Times out after 5 s.
    static func which(_ name: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-lc", "command -v \(name)"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(5)
        while p.isRunning && Date() < deadline { usleep(50_000) }
        if p.isRunning { p.terminate(); return nil }
        let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let s, s.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: s) else { return nil }
        return s
    }
}
