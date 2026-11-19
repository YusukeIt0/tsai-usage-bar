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
    /// The month's billed amount beyond free usage for Actions (all SKUs), from `netAmount`.
    public static func chargedAmount(fromSummaryJSON data: Data) -> Double? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let raw = obj["usageItems"] as? [[String: Any]] else { return nil }
        return raw.reduce(0) { sum, it in
            guard (it["product"] as? String)?.lowercased() ?? "actions" == "actions" else { return sum }
            return sum + (doubleValue(it["netAmount"]) ?? 0)
        }
    }

    /// Share of the person's budget spent, from the billed amount. Nil without both values.
    public static func budgetPercent(_ window: UsageWindow, budgetUSD: Double?) -> Double? {
        guard let budget = budgetUSD, budget > 0, let charged = window.chargedAmount else { return nil }
        return min(100, max(0, charged / budget * 100))
    }

    public static func window(plan: String?, total: [Item], publicRepos: [[Item]], now: Date) throws -> UsageWindow {
        guard let plan, let included = includedUSD[plan.lowercased()], included > 0 else {
            throw Failure.unknownPlan(plan)
        }
        let totalAmount = total.reduce(0) { $0 + $1.grossAmount }
        let publicAmount = publicRepos.joined().reduce(0) { $0 + $1.grossAmount }
        let privateAmount = max(0, totalAmount - publicAmount)
        let used = min(100, privateAmount / included * 100)
        return UsageWindow(usedPercent: used, resetsAt: period(containing: now).resetsAt,
                           usedAmount: privateAmount, includedAmount: included)
    }

    /// The same window measured against included usage plus the person's monthly Actions
    /// budget (entered in Settings; GitHub has no public API for personal budgets).
    /// Without a positive budget, or without stored amounts, the window is unchanged.
    public static func applyingBudget(_ window: UsageWindow, budgetUSD: Double?) -> UsageWindow {
        guard let budget = budgetUSD, budget > 0,
              let used = window.usedAmount, let included = window.includedAmount else { return window }
        var w = window
        w.usedPercent = min(100, max(0, used / (included + budget) * 100))
        return w
    }
}

/// Per-day private-repository Actions usage (USD), from GitHub's official per-day billing
/// summaries. Keys are billing days in UTC ("yyyy-MM-dd"). Past days are kept; the last two
/// days are read again because GitHub's totals lag.
public struct GitHubDailyCache: Codable, Equatable, Sendable {
    public var amounts: [String: Double] = [:]
    public var fetchedAt: [String: Date] = [:]
    /// Included monthly amount used as the 100% reference (from the plan).
    public var includedAmount: Double?

    public init() {}

    /// Days in `keys` that still need a read at `now`.
    public func needsRead(_ keys: [String], now: Date) -> [String] {
        let today = Self.utcKey(now)
        let yesterday = Self.utcKey(now.addingTimeInterval(-86_400))
        return keys.filter { key in
            if key > today { return false } // future
            guard let fetched = fetchedAt[key] else { return true }
            if key == today || key == yesterday { return now.timeIntervalSince(fetched) > 3600 }
            return false
        }
    }

    /// Share of the month's allowance (included plus budget) used on that day, or nil.
    public func percent(_ key: String, budgetUSD: Double?) -> Double? {
        guard let amount = amounts[key], let included = includedAmount, included > 0 else { return nil }
        let limit = included + max(0, budgetUSD ?? 0)
        return min(100, amount / limit * 100)
    }

    public static func utcKey(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return DailyUsageLog.dayKey(date, calendar: cal)
    }

    /// Keeps about two years, the period GitHub's summary endpoint serves.
    public mutating func prune(now: Date) {
        let cutoff = Self.utcKey(now.addingTimeInterval(-730 * 86_400))
        amounts = amounts.filter { $0.key >= cutoff }
        fetchedAt = fetchedAt.filter { $0.key >= cutoff }
    }
}

/// Split of the "free usage + budget" bar into its free and budget parts.
public enum BudgetBarSplit {
    /// Fractions of the whole bar (0...1) for the free part and the budget part.
    /// Used mode: free used, then budget used. Remaining mode: free left, then budget left.
    /// Usage consumes the free amount first, then the budget. Nil without amounts or a budget.
    public static func parts(_ window: UsageWindow, budgetUSD: Double?, mode: DisplayMode) -> (free: Double, budget: Double)? {
        guard let budget = budgetUSD, budget > 0, let used = window.usedAmount,
              let included = window.includedAmount, included > 0 else { return nil }
        let total = included + budget
        let freeUsed = min(max(used, 0), included)
        let budgetUsed = min(max(used - included, 0), budget)
        switch mode {
        case .used: return (freeUsed / total, budgetUsed / total)
        case .remaining: return ((included - freeUsed) / total, (budget - budgetUsed) / total)
        }
    }
}
