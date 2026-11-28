import Foundation

/// Minimal access with the user's token. Only reads: REST GET requests, and GraphQL queries,
/// which GraphQL takes as POST (never mutations).
enum GitHubAPI {
    static func get(_ path: String, token: String?) async throws -> (Data, Int) {
        var req = URLRequest(url: URL(string: "https://api.github.com" + path)!, cachePolicy: .reloadIgnoringLocalCacheData,
                             timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        return try await send(req, token: token)
    }

    static func graphQL(_ query: String, token: String) async throws -> (Data, Int) {
        precondition(query.trimmingCharacters(in: .whitespaces).hasPrefix("query"), "GraphQL queries only")
        var req = URLRequest(url: URL(string: "https://api.github.com/graphql")!, cachePolicy: .reloadIgnoringLocalCacheData,
                             timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query])
        return try await send(req, token: token)
    }

    private static func send(_ request: URLRequest, token: String?) async throws -> (Data, Int) {
        var req = request
        req.setValue("TSAI-UsageBar/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        return (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
