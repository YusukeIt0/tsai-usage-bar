import AppKit
import UsageCore

/// Per-day private-repository usage for the chart. Only days that are shown are read.
enum GitHubDailyClient {
    /// Public repositories with Actions usage in a month ("yyyy-MM"), remembered per launch.
    @MainActor private static var activePublicByMonth: [String: [String]] = [:]

    struct Result { var amounts: [String: Double]; var included: Double }

    static func read(days keys: [String]) async -> Swift.Result<Result, ProviderError> {
        do {
            guard let token = try await GitHubAuth.validAccessToken() else { return .failure(.notSignedIn) }
            let (userData, userStatus) = try await GitHubAPI.get("/user", token: token)
            guard userStatus == 200, let user = (try? JSONSerialization.jsonObject(with: userData)) as? [String: Any],
                  let login = user["login"] as? String else { return .failure(.failed(nil)) }
            let plan = (user["plan"] as? [String: Any])?["name"] as? String
            guard let included = plan.flatMap({ GitHubActionsUsage.includedUSD[$0.lowercased()] }) else { return .failure(.unknownPlan) }
            let base = "/users/\(login)/settings/billing/usage/summary?product=Actions"

            @Sendable func amount(_ query: String) async throws -> Double {
                let (d, s) = try await GitHubAPI.get(base + query, token: token)
                guard s == 200 else { throw ProviderError.failed(nil) }
                return try GitHubActionsUsage.items(fromSummaryJSON: d).reduce(0) { $0 + $1.grossAmount }
            }
            @Sendable func encode(_ repo: String) -> String { repo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? repo }

            // Which public repositories used Actions in each month involved.
            var publicRepos: [String]?
            var activeByMonth: [String: [String]] = [:]
            for month in Set(keys.map { String($0.prefix(7)) }) {
                if let cached = await MainActor.run(body: { activePublicByMonth[month] }) { activeByMonth[month] = cached; continue }
                if publicRepos == nil { publicRepos = try await GitHubClient.publicRepositories(login: login, token: token) }
                let parts = month.split(separator: "-")
                let used = try await concurrentMap(publicRepos ?? []) { repo in
                    try await amount("&year=\(parts[0])&month=\(Int(parts[1])!)&repository=\(encode(repo))") > 0 ? repo : nil
                }
                let active = used.compactMap { $0 }
                activeByMonth[month] = active
                let found = active
                await MainActor.run { activePublicByMonth[month] = found }
            }

            // Each day: the total, and each active public repository, all read in parallel.
            let active = activeByMonth
            let perDay = try await concurrentMap(keys) { key -> (String, Double) in
                let p = key.split(separator: "-")
                let dayQuery = "&year=\(p[0])&month=\(Int(p[1])!)&day=\(Int(p[2])!)"
                let repos = active[String(key.prefix(7))] ?? []
                let parts = try await concurrentMap([nil] + repos.map { Optional($0) }) { repo in
                    try await amount(dayQuery + (repo.map { "&repository=\(encode($0))" } ?? ""))
                }
                let total = parts.first ?? 0
                return (key, max(0, total - parts.dropFirst().reduce(0, +)))
            }
            return .success(Result(amounts: Dictionary(uniqueKeysWithValues: perDay), included: included))
        } catch let e as ProviderError {
            return .failure(e)
        } catch {
            return .failure(.failed(nil))
        }
    }
}
