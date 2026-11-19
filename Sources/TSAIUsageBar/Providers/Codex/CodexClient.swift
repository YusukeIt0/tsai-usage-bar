import Foundation
import UsageCore

/// High-level Codex operations used by the app.
enum CodexClient {
    static let timeout: TimeInterval = 15

    /// `details`: also read reset-credit detail rows (expiry); done only when a panel is open.
    static func readRateLimits(details: Bool = false) async -> Result<ProviderSnapshot, ProviderError> {
        guard let exe = CodexLocator.find() else { return .failure(.notInstalled) }
        let session = CodexAppServerSession(executable: exe)
        defer { session.close() }
        do { try session.start() } catch { return .failure(.notInstalled) }
        if case .failure(let e) = await session.initialize(timeout: timeout) { return .failure(e) }

        // Signed-in check first so a missing login is reported clearly.
        if case .success(let acct) = await session.request("account/read", params: [:], timeout: timeout),
           acct["account"] == nil || acct["account"] is NSNull,
           (acct["requiresOpenaiAuth"] as? Bool) == true {
            return .failure(.notSignedIn)
        }
        let r = await session.request("account/rateLimits/read",
                                      params: ["excludeResetCreditDetails": !details], timeout: timeout)
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
    static func signIn(openURL: @escaping @Sendable (URL) -> Void) async -> Result<Void, ProviderError> {
        guard let exe = CodexLocator.find() else { return .failure(.notInstalled) }
        let session = CodexAppServerSession(executable: exe)
        defer { session.close() }
        let completed = AsyncStream<Bool>.makeStream()
        session.onNotification { method, params in
            if method == "account/login/completed" {
                completed.continuation.yield((params["success"] as? Bool) == true)
                completed.continuation.finish()
            }
        }
        do { try session.start() } catch { return .failure(.notInstalled) }
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
