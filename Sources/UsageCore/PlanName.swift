import Foundation

/// Plan names shown next to a panel's title, from each service's own plan identifier.
/// Names follow the service's own wording; an identifier without a known name is shown as
/// received rather than guessed.
public enum PlanName {
    /// Claude Code: `subscriptionType` from `claude auth status --json`.
    static let claude = ["free": "Free", "pro": "Pro", "max": "Max", "team": "Team", "enterprise": "Enterprise"]
    /// Codex: `planType` from `account/rateLimits/read`. OpenAI names its Pro tiers by price
    /// ("Pro 100", "Pro 200", "Pro 500"); `prolite` is Pro 100. `pro` is shown as "Pro" since
    /// which of the higher tiers it stands for isn't confirmed.
    static let codex = ["free": "Free", "go": "Go", "plus": "Plus", "prolite": "Pro 100", "pro": "Pro",
                        "team": "Team", "business": "Business", "enterprise": "Enterprise", "edu": "Edu"]
    /// GitHub: `plan.name` from `GET /user`.
    static let github = ["free": "Free", "pro": "Pro"]

    public static func display(_ provider: Provider, _ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              raw.lowercased() != "unknown" else { return nil }
        let names: [String: String]
        switch provider {
        case .claude: names = claude
        case .codex: names = codex
        case .github: names = github
        }
        return names[raw.lowercased()] ?? raw
    }
}
