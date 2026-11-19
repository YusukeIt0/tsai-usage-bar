import Foundation
import UsageCore

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
    private var waiters: [Int: (Result<[String: Any], ProviderError>) -> Void] = [:]
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

    func request(_ method: String, params: [String: Any]?, timeout: TimeInterval) async -> Result<[String: Any], ProviderError> {
        await withCheckedContinuation { cont in
            queue.async {
                if self.closed { cont.resume(returning: .failure(.failed("closed"))); return }
                let id = self.nextID
                self.nextID += 1
                var once = false
                let finish: (Result<[String: Any], ProviderError>) -> Void = { r in
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
    func initialize(timeout: TimeInterval) async -> Result<Void, ProviderError> {
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

    private func failAll(_ e: ProviderError) {
        let ws = waiters
        waiters.removeAll()
        for (_, w) in ws { w(.failure(e)) }
    }

    static func classify(_ message: String) -> ProviderError {
        let m = message.lowercased()
        if m.contains("auth") || m.contains("login") || m.contains("sign in") || m.contains("unauthorized") {
            return .notSignedIn
        }
        return .failed(message)
    }
}
