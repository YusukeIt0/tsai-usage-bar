import Foundation
import UsageCore

enum CodexError: Error, Equatable {
    case notFound
    case notSignedIn
    case timedOut
    case failed(String)
}

/// Short-lived connection to the official `codex app-server` (JSON-RPC over stdio).
/// Each call starts the server, performs the handshake, sends one request, and stops it.
/// Only read requests and the official browser sign-in are used.
final class CodexAppServerSession: @unchecked Sendable {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let queue = DispatchQueue(label: "codex.app-server.session")
    private var buffer = Data()
    private var nextID = 1
    private var waiters: [Int: (Result<[String: Any], CodexError>) -> Void] = [:]
    private var notificationHandler: ((String, [String: Any]) -> Void)?
    private var closed = false

    init(executable: URL) {
        process.executableURL = executable
        process.arguments = ["app-server"]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = CodexLocator.searchPath
        process.environment = env
    }

    func onNotification(_ handler: @escaping (String, [String: Any]) -> Void) {
        queue.sync { notificationHandler = handler }
    }

    func start() throws {
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            self?.queue.async { self?.consume(data) }
        }
        process.terminationHandler = { [weak self] _ in
            self?.queue.async { self?.failAll(.failed("app-server exited")) }
        }
        try process.run()
    }

    func request(_ method: String, params: [String: Any]?, timeout: TimeInterval) async -> Result<[String: Any], CodexError> {
        await withCheckedContinuation { cont in
            queue.async {
                if self.closed { cont.resume(returning: .failure(.failed("closed"))); return }
                let id = self.nextID
                self.nextID += 1
                var once = false
                let finish: (Result<[String: Any], CodexError>) -> Void = { r in
                    if once { return }
                    once = true
                    cont.resume(returning: r)
                }
                self.waiters[id] = finish
                var msg: [String: Any] = ["id": id, "method": method]
                if let params { msg["params"] = params }
                self.send(msg)
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    if let w = self.waiters.removeValue(forKey: id) { w(.failure(.timedOut)) }
                }
            }
        }
    }

    func notify(_ method: String) {
        queue.async { self.send(["method": method]) }
    }

    func close() {
        queue.sync {
            closed = true
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            try? stdinPipe.fileHandleForWriting.close()
            failAll(.failed("closed"))
        }
        let p = process
        if p.isRunning {
            p.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if p.isRunning { kill(p.processIdentifier, SIGKILL) }
            }
        }
    }

    /// Standard handshake: `initialize` then the `initialized` notification.
    func initialize(timeout: TimeInterval) async -> Result<Void, CodexError> {
        let params: [String: Any] = [
            "clientInfo": ["name": "tsai_usagebar", "title": "TSAI UsageBar", "version": AppInfo.version],
            "capabilities": ["experimentalApi": false, "requestAttestation": false,
                             "optOutNotificationMethods": ["remoteControl/status/changed"]],
        ]
        switch await request("initialize", params: params, timeout: timeout) {
        case .success:
            notify("initialized")
            return .success(())
        case .failure(let e):
            return .failure(e)
        }
    }

    // MARK: Private (queue)

    private func send(_ obj: [String: Any]) {
        guard !closed, var data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        data.append(0x0A)
        do { try stdinPipe.fileHandleForWriting.write(contentsOf: data) } catch {
            failAll(.failed("write failed"))
        }
    }

    private func consume(_ data: Data) {
        if data.isEmpty { return }
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
            if let id = (obj["id"] as? NSNumber)?.intValue, obj["method"] == nil {
                guard let w = waiters.removeValue(forKey: id) else { continue }
                if let result = obj["result"] as? [String: Any] {
                    w(.success(result))
                } else if let err = obj["error"] as? [String: Any] {
                    let message = err["message"] as? String ?? "error"
                    w(.failure(Self.classify(message)))
                } else {
                    w(.success([:]))
                }
            } else if let method = obj["method"] as? String {
                notificationHandler?(method, obj["params"] as? [String: Any] ?? [:])
            }
        }
    }

    private func failAll(_ e: CodexError) {
        let ws = waiters
        waiters.removeAll()
        for (_, w) in ws { w(.failure(e)) }
    }

    static func classify(_ message: String) -> CodexError {
        let m = message.lowercased()
        if m.contains("auth") || m.contains("login") || m.contains("sign in") || m.contains("unauthorized") {
            return .notSignedIn
        }
        return .failed(message)
    }
}

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

/// High-level Codex operations used by the app.
enum CodexClient {
    static let timeout: TimeInterval = 15

    static func readRateLimits() async -> Result<ProviderSnapshot, CodexError> {
        guard let exe = CodexLocator.find() else { return .failure(.notFound) }
        let session = CodexAppServerSession(executable: exe)
        defer { session.close() }
        do { try session.start() } catch { return .failure(.notFound) }
        if case .failure(let e) = await session.initialize(timeout: timeout) { return .failure(e) }

        // Signed-in check first so a missing login is reported clearly.
        if case .success(let acct) = await session.request("account/read", params: [:], timeout: timeout),
           acct["account"] == nil || acct["account"] is NSNull,
           (acct["requiresOpenaiAuth"] as? Bool) == true {
            return .failure(.notSignedIn)
        }
        let r = await session.request("account/rateLimits/read",
                                      params: ["excludeResetCreditDetails": true], timeout: timeout)
        switch r {
        case .success(let result):
            do { return .success(try CodexRateLimitParser.parse(result: result, fetchedAt: Date())) }
            catch { return .failure(.failed("unexpected response")) }
        case .failure(let e):
            return .failure(e)
        }
    }

    /// Official ChatGPT sign-in: the server returns a URL that is opened in the browser.
    /// Waits for `account/login/completed` (up to 10 minutes).
    static func signIn(openURL: @escaping @Sendable (URL) -> Void) async -> Result<Void, CodexError> {
        guard let exe = CodexLocator.find() else { return .failure(.notFound) }
        let session = CodexAppServerSession(executable: exe)
        defer { session.close() }
        let completed = AsyncStream<Bool>.makeStream()
        session.onNotification { method, params in
            if method == "account/login/completed" {
                completed.continuation.yield((params["success"] as? Bool) == true)
                completed.continuation.finish()
            }
        }
        do { try session.start() } catch { return .failure(.notFound) }
        if case .failure(let e) = await session.initialize(timeout: timeout) { return .failure(e) }
        let r = await session.request("account/login/start", params: ["type": "chatgpt"], timeout: timeout)
        guard case .success(let res) = r, let s = res["authUrl"] as? String, let url = URL(string: s) else {
            if case .failure(let e) = r { return .failure(e) }
            return .failure(.failed("no sign-in URL"))
        }
        openURL(url)
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 600 * 1_000_000_000)
            completed.continuation.finish()
        }
        defer { timeoutTask.cancel() }
        for await ok in completed.stream {
            return ok ? .success(()) : .failure(.notSignedIn)
        }
        return .failure(.timedOut)
    }
}
