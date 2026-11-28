import Foundation
import UsageCore

/// Reads the account's contribution calendar for the last year, the same one its GitHub
/// profile shows. Works with the app's "Plan: read" token: the calendar needs no extra permission.
enum GitHubContributionsClient {
    static func read(now: Date = Date()) async -> Result<ContributionCalendar, ProviderError> {
        do {
            guard let token = try await GitHubAuth.validAccessToken() else { return .failure(.notSignedIn) }
            let (data, status) = try await GitHubAPI.graphQL(ContributionCalendar.query, token: token)
            if status == 401 { return .failure(.notSignedIn) }
            guard status == 200 else { return .failure(.failed(nil)) }
            return .success(try ContributionCalendar.parse(data, now: now))
        } catch {
            return .failure(.failed(nil))
        }
    }
}
