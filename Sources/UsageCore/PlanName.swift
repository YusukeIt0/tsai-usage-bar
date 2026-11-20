import Foundation

/// Plan names shown next to a panel's title, from each service's own plan identifier.
/// Names follow the service's own wording; an identifier without a known name is shown as
/// received rather than guessed.
public enum PlanName {
    /// Claude Code: from `claude auth status --json` (see `claudePlan`). Anthropic renamed
    /// Max 5x to Max and Max 20x to Ultra on 2026-10-30.
    static let claude = ["free": "Free", "pro": "Pro", "max": "Max", "max_5x": "Max", "max_20x": "Ultra",
                         "team": "Team", "enterprise": "Enterprise"]
    /// Codex: `planType` from `account/rateLimits/read`. OpenAI names its three Pro tiers by
    /// price ("Pro 100", "Pro 200", "Pro 500"), and the Codex CLI's PlanType has exactly three
    /// personal Pro values: `prolite` (Pro 100, seen on a real account), `pro` (the original
    /// $200 Pro) and `promax`.
    static let codex = ["free": "Free", "go": "Go", "plus": "Plus",
                        "prolite": "Pro 100", "pro": "Pro 200", "promax": "Pro 500",
                        "team": "Team", "business": "Business", "enterprise": "Enterprise", "edu": "Edu"]
    /// GitHub: `plan.name` from `GET /user`.
    static let github = ["free": "Free", "pro": "Pro"]

    /// Claude Code's plan identifier: `planTier` when it names a Max tier (`max_5x`, `max_20x`),
    /// otherwise `subscriptionType`. `max_other` and the catch-all `other` say nothing more
    /// than `subscriptionType`.
    public static func claudePlan(subscriptionType: String?, planTier: String?) -> String? {
        if let planTier, ["max_5x", "max_20x"].contains(planTier) { return planTier }
        return subscriptionType
    }

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
