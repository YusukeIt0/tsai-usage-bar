import Foundation

/// Included GitHub Actions usage for private repositories, from the official billing API.
///
/// GitHub gives personal accounts a monthly monetary amount of included compute that only
/// private repositories consume; standard runners on public repositories are free and
/// unlimited. The billing summary mixes both, so private usage is the account total minus
/// every public repository's usage. Storage is a separate allowance and is not counted.
public enum GitHubActionsUsage {
    /// Included compute per month in USD, by plan name from `GET /user` (`plan.name`).
    /// Other plans are unknown: their value is shown as unavailable instead of guessed.
    public static let includedUSD: [String: Double] = ["free": 12, "pro": 18]

    public struct Item: Equatable, Sendable {
        public var sku: String
        public var grossAmount: Double
        public init(sku: String, grossAmount: Double) {
            self.sku = sku
            self.grossAmount = grossAmount
        }
    }

    public enum Failure: Error, Equatable {
        case unknownPlan(String?)
        case invalidResponse
    }

    /// Reads `usageItems` of a billing usage summary response. Only Actions compute counts.
    public static func items(fromSummaryJSON data: Data) throws -> [Item] {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let raw = obj["usageItems"] as? [[String: Any]] else { throw Failure.invalidResponse }
        return raw.compactMap { it in
            guard let sku = it["sku"] as? String, isCompute(sku: sku, product: it["product"] as? String),
                  let gross = doubleValue(it["grossAmount"]) else { return nil }
            return Item(sku: sku, grossAmount: gross)
        }
    }

    static func isCompute(sku: String, product: String?) -> Bool {
        if let product, product.lowercased() != "actions" { return false }
        let s = sku.lowercased()
        return s.hasPrefix("actions_") && !s.contains("storage")
    }

    /// The calendar month in UTC that contains `date`, and its end (the reset time).
    public static func period(containing date: Date) -> (year: Int, month: Int, resetsAt: Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month], from: date)
        let start = cal.date(from: c)!
        let next = cal.date(byAdding: .month, value: 1, to: start)!
        return (c.year!, c.month!, next)
    }

    /// Builds the monthly window: used percent of the plan's included compute.
    public static func window(plan: String?, total: [Item], publicRepos: [[Item]], now: Date) throws -> UsageWindow {
        guard let plan, let included = includedUSD[plan.lowercased()], included > 0 else {
            throw Failure.unknownPlan(plan)
        }
        let totalAmount = total.reduce(0) { $0 + $1.grossAmount }
        let publicAmount = publicRepos.joined().reduce(0) { $0 + $1.grossAmount }
        let privateAmount = max(0, totalAmount - publicAmount)
        let used = min(100, privateAmount / included * 100)
        return UsageWindow(usedPercent: used, resetsAt: period(containing: now).resetsAt)
    }
}
