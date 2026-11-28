import AppKit
import UsageCore

/// GitHub sign-in through the TSAI UsageBar GitHub App (device flow, "Plan: read" only).
///
/// Tokens are kept in a file readable only by this user in the app's support folder, the
/// same approach the Codex CLI uses for its login. The Keychain is not used because these
/// builds are ad-hoc signed, so macOS would ask for access again after every update.
/// The app's only permission is reading the account's plan and billing usage; the token also
/// reads public data such as the contribution calendar, which needs no permission.
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
