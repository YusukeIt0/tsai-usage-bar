import Foundation

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
