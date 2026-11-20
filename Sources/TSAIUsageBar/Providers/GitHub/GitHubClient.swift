import AppKit
import UsageCore

/// Reads this month's included Actions usage for private repositories.
enum GitHubClient {
    /// Public repositories checked at most (each needs one request).
    static let maxPublicRepos = 300

    static func readUsage(now: Date = Date()) async -> Result<ProviderSnapshot, ProviderError> {
        do {
            guard let token = try await GitHubAuth.validAccessToken() else { return .failure(.notSignedIn) }
            let (userData, userStatus) = try await GitHubAPI.get("/user", token: token)
            if userStatus == 401 { GitHubAuth.remove(); return .failure(.notSignedIn) }
            guard userStatus == 200, let user = (try? JSONSerialization.jsonObject(with: userData)) as? [String: Any],
                  let login = user["login"] as? String else { return .failure(.failed(nil)) }
            let plan = (user["plan"] as? [String: Any])?["name"] as? String
            let p = GitHubActionsUsage.period(containing: now)
            let base = "/users/\(login)/settings/billing/usage/summary?year=\(p.year)&month=\(p.month)&product=Actions"

            let (totalData, totalStatus) = try await GitHubAPI.get(base, token: token)
            guard totalStatus == 200 else { return .failure(.failed(nil)) }
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
                            guard s == 200 else { throw ProviderError.failed(nil) }
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
                var w = try GitHubActionsUsage.window(plan: plan, total: total, publicRepos: publicItems, now: now)
                w.chargedAmount = GitHubActionsUsage.chargedAmount(fromSummaryJSON: totalData)
                var snapshot = ProviderSnapshot(windows: [.month: w], fetchedAt: now)
                snapshot.plan = plan
                return .success(snapshot)
            } catch {
                return .failure(.unknownPlan)
            }
        } catch let e as ProviderError {
            return .failure(e)
        } catch {
            return .failure(.failed(nil))
        }
    }

    /// Full names of the account's public repositories (public data).
    static func publicRepositories(login: String, token: String) async throws -> [String] {
        var names: [String] = []
        for page in 1...4 {
            let (d, s) = try await GitHubAPI.get("/users/\(login)/repos?type=owner&per_page=100&page=\(page)", token: token)
            guard s == 200, let arr = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { throw ProviderError.failed(nil) }
            names += arr.compactMap { r in (r["private"] as? Bool) == false ? r["full_name"] as? String : nil }
            if arr.count < 100 { break }
        }
        return names
    }
}
