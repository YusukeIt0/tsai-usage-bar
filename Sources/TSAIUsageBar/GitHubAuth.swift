import AppKit
import UsageCore

/// GitHub sign-in through the TSAI UsageBar GitHub App (device flow, "Plan: read" only).
///
/// Tokens are kept in a file readable only by this user in the app's support folder, the
/// same approach the Codex CLI uses for its login. The Keychain is not used because these
/// builds are ad-hoc signed, so macOS would ask for access again after every update.
/// The token can only read the account's plan and billing usage.
enum GitHubAuth {
    static let clientID = "Iv23lindgcrOz1pwSfLm"

    struct Tokens: Codable {
        var accessToken: String
        var accessExpires: Date?
        var refreshToken: String?
        var refreshExpires: Date?
        var login: String?
    }

    struct DeviceCode {
        let deviceCode: String
        let userCode: String
        let verificationURL: URL
        let interval: TimeInterval
        let expiresAt: Date
    }

    enum AuthError: Error, Equatable {
        case denied
        case expired
        case cancelled
        case network
        case invalid
    }

    static var tokenURL: URL { AppPaths().supportDirectory.appendingPathComponent("github-token.json") }

    // MARK: Storage

    static func load() -> Tokens? {
        guard let data = try? Data(contentsOf: tokenURL) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return try? d.decode(Tokens.self, from: data)
    }

    static func save(_ t: Tokens) throws {
        try AppPaths().ensureDirectory()
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        try writeAtomically(try e.encode(t), to: tokenURL, permissions: 0o600)
    }

    static func remove() { try? FileManager.default.removeItem(at: tokenURL) }

    // MARK: Device flow

    static func startDeviceFlow() async throws -> DeviceCode {
        let r = try await post("https://github.com/login/device/code", ["client_id": clientID])
        guard let device = r["device_code"] as? String, let user = r["user_code"] as? String,
              let uri = (r["verification_uri"] as? String).flatMap(URL.init(string:)) else { throw AuthError.invalid }
        let interval = (r["interval"] as? NSNumber)?.doubleValue ?? 5
        let expires = (r["expires_in"] as? NSNumber)?.doubleValue ?? 900
        return DeviceCode(deviceCode: device, userCode: user, verificationURL: uri,
                          interval: interval, expiresAt: Date().addingTimeInterval(expires))
    }

    /// Polls until the person approves in the browser, then stores the tokens.
    static func waitForApproval(_ code: DeviceCode) async throws -> Tokens {
        var interval = code.interval
        while Date() < code.expiresAt {
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            try Task.checkCancellation()
            let r = try await post("https://github.com/login/oauth/access_token", [
                "client_id": clientID, "device_code": code.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
            if let tokens = tokens(from: r) {
                var t = tokens
                t.login = try? await fetchLogin(t.accessToken)
                try save(t)
                return t
            }
            switch r["error"] as? String {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            case "access_denied": throw AuthError.denied
            case "expired_token": throw AuthError.expired
            default: throw AuthError.invalid
            }
        }
        throw AuthError.expired
    }

    /// A usable access token, refreshing it when it is about to expire.
    static func validAccessToken() async throws -> String? {
        guard var t = load() else { return nil }
        if let exp = t.accessExpires, exp.timeIntervalSinceNow < 300 {
            guard let refresh = t.refreshToken, (t.refreshExpires ?? .distantFuture) > Date() else {
                remove()
                return nil
            }
            let r = try await post("https://github.com/login/oauth/access_token", [
                "client_id": clientID, "grant_type": "refresh_token", "refresh_token": refresh,
            ])
            guard let fresh = tokens(from: r) else {
                if (r["error"] as? String) == "bad_refresh_token" { remove(); return nil }
                throw AuthError.invalid
            }
            let login = t.login
            t = fresh
            t.login = login
            try save(t)
        }
        return t.accessToken
    }

    private static func tokens(from r: [String: Any]) -> Tokens? {
        guard let access = r["access_token"] as? String else { return nil }
        let now = Date()
        return Tokens(
            accessToken: access,
            accessExpires: (r["expires_in"] as? NSNumber).map { now.addingTimeInterval($0.doubleValue) },
            refreshToken: r["refresh_token"] as? String,
            refreshExpires: (r["refresh_token_expires_in"] as? NSNumber).map { now.addingTimeInterval($0.doubleValue) },
            login: nil)
    }

    static func fetchLogin(_ token: String) async throws -> String? {
        let (data, _) = try await GitHubAPI.get("/user", token: token)
        return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["login"] as? String
    }

    private static func post(_ url: String, _ form: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: url)!, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("TSAI-UsageBar/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        var comps = URLComponents()
        comps.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = comps.percentEncodedQuery?.data(using: .utf8)
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        } catch {
            throw AuthError.network
        }
    }
}

/// Minimal REST access with the user's token. Only GET requests are made.
enum GitHubAPI {
    static func get(_ path: String, token: String?) async throws -> (Data, Int) {
        var req = URLRequest(url: URL(string: "https://api.github.com" + path)!, cachePolicy: .reloadIgnoringLocalCacheData,
                             timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("TSAI-UsageBar/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

enum GitHubError: Error, Equatable {
    case notConnected
    case unknownPlan
    case tooManyRepositories
    case failed
}

/// Reads this month's included Actions usage for private repositories.
enum GitHubClient {
    /// Public repositories checked at most (each needs one request).
    static let maxPublicRepos = 300

    static func readUsage(now: Date = Date()) async -> Result<ProviderSnapshot, GitHubError> {
        do {
            guard let token = try await GitHubAuth.validAccessToken() else { return .failure(.notConnected) }
            let (userData, userStatus) = try await GitHubAPI.get("/user", token: token)
            if userStatus == 401 { GitHubAuth.remove(); return .failure(.notConnected) }
            guard userStatus == 200, let user = (try? JSONSerialization.jsonObject(with: userData)) as? [String: Any],
                  let login = user["login"] as? String else { return .failure(.failed) }
            let plan = (user["plan"] as? [String: Any])?["name"] as? String
            let p = GitHubActionsUsage.period(containing: now)
            let base = "/users/\(login)/settings/billing/usage/summary?year=\(p.year)&month=\(p.month)&product=Actions"

            let (totalData, totalStatus) = try await GitHubAPI.get(base, token: token)
            guard totalStatus == 200 else { return .failure(.failed) }
            let total = try GitHubActionsUsage.items(fromSummaryJSON: totalData)

            // Public repositories are free; subtract them. Skipped when nothing was used.
            var publicItems: [[GitHubActionsUsage.Item]] = []
            if total.contains(where: { $0.grossAmount > 0 }) {
                let repos = try await publicRepositories(login: login, token: token)
                guard repos.count <= maxPublicRepos else { return .failure(.tooManyRepositories) }
                publicItems = try await withThrowingTaskGroup(of: [GitHubActionsUsage.Item].self) { group in
                    var results: [[GitHubActionsUsage.Item]] = []
                    var iterator = repos.makeIterator()
                    func add() {
                        guard let repo = iterator.next() else { return }
                        group.addTask {
                            let q = repo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? repo
                            let (d, s) = try await GitHubAPI.get(base + "&repository=\(q)", token: token)
                            guard s == 200 else { throw GitHubError.failed }
                            return try GitHubActionsUsage.items(fromSummaryJSON: d)
                        }
                    }
                    for _ in 0..<4 { add() }
                    while let r = try await group.next() {
                        results.append(r)
                        add()
                    }
                    return results
                }
            }
            do {
                let w = try GitHubActionsUsage.window(plan: plan, total: total, publicRepos: publicItems, now: now)
                return .success(ProviderSnapshot(windows: [.month: w], fetchedAt: now))
            } catch {
                return .failure(.unknownPlan)
            }
        } catch let e as GitHubError {
            return .failure(e)
        } catch {
            return .failure(.failed)
        }
    }

    /// Full names of the account's public repositories (public data).
    static func publicRepositories(login: String, token: String) async throws -> [String] {
        var names: [String] = []
        for page in 1...4 {
            let (d, s) = try await GitHubAPI.get("/users/\(login)/repos?type=owner&per_page=100&page=\(page)", token: token)
            guard s == 200, let arr = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { throw GitHubError.failed }
            names += arr.compactMap { r in (r["private"] as? Bool) == false ? r["full_name"] as? String : nil }
            if arr.count < 100 { break }
        }
        return names
    }
}
