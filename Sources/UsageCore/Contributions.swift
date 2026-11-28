import Foundation

/// One day of the GitHub contribution calendar, as GitHub's profile shows it.
public struct ContributionDay: Codable, Equatable, Hashable, Sendable {
    /// "yyyy-MM-dd", as GitHub returns it.
    public var date: String
    public var count: Int
    /// 0 (none) to 4, GitHub's own quartile for this day, so the same squares light up as on the profile.
    public var level: Int
    /// 0 = Sunday.
    public var weekday: Int

    public init(date: String, count: Int, level: Int, weekday: Int) {
        self.date = date
        self.count = count
        self.level = level
        self.weekday = weekday
    }

    /// Noon UTC of the day, for formatting with a UTC formatter.
    public var utcDate: Date? { Self.parser.date(from: date + " 12") }
    var month: Int? { Int(date.dropFirst(5).prefix(2)) }
    var dayOfMonth: Int? { Int(date.suffix(2)) }

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH"
        return f
    }()
}

/// The signed-in account's contribution calendar for the last year (GitHub GraphQL
/// `viewer.contributionsCollection.contributionCalendar`), shown 13 weeks at a time.
public struct ContributionCalendar: Codable, Equatable, Sendable {
    /// Oldest first. Each week runs Sunday to Saturday; the first and last can be partial.
    public var weeks: [[ContributionDay]]
    public var totalContributions: Int
    public var fetchedAt: Date

    public init(weeks: [[ContributionDay]], totalContributions: Int, fetchedAt: Date) {
        self.weeks = weeks
        self.totalContributions = totalContributions
        self.fetchedAt = fetchedAt
    }

    public static let weeksPerPage = 13

    /// The GraphQL query. Read-only; sent as POST because that is how GraphQL takes queries.
    public static let query = """
    query { viewer { contributionsCollection { contributionCalendar { totalContributions \
    weeks { contributionDays { date contributionCount contributionLevel weekday } } } } } }
    """

    public enum Failure: Error, Equatable { case invalid }

    public static func parse(_ data: Data, now: Date) throws -> ContributionCalendar {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let viewer = (root["data"] as? [String: Any])?["viewer"] as? [String: Any],
              let cal = (viewer["contributionsCollection"] as? [String: Any])?["contributionCalendar"] as? [String: Any],
              let total = cal["totalContributions"] as? Int,
              let weeks = cal["weeks"] as? [[String: Any]] else { throw Failure.invalid }
        let parsed: [[ContributionDay]] = try weeks.map { w in
            guard let days = w["contributionDays"] as? [[String: Any]] else { throw Failure.invalid }
            return try days.map { d in
                guard let date = d["date"] as? String, date.count == 10, let count = d["contributionCount"] as? Int,
                      let weekday = d["weekday"] as? Int, (0...6).contains(weekday) else { throw Failure.invalid }
                return ContributionDay(date: date, count: count, level: level(d["contributionLevel"] as? String), weekday: weekday)
            }
        }
        guard !parsed.isEmpty else { throw Failure.invalid }
        return ContributionCalendar(weeks: parsed, totalContributions: total, fetchedAt: now)
    }

    static func level(_ name: String?) -> Int {
        switch name {
        case "FIRST_QUARTILE": 1
        case "SECOND_QUARTILE": 2
        case "THIRD_QUARTILE": 3
        case "FOURTH_QUARTILE": 4
        default: 0
        }
    }

    /// Pages of 13 weeks, 0 = the latest. The oldest page is filled from the start of the
    /// year, so it can overlap the one after it rather than show a few lone weeks.
    public var pageCount: Int { max(1, Int((Double(weeks.count) / Double(Self.weeksPerPage)).rounded(.up))) }

    public func page(_ index: Int) -> [[ContributionDay]] {
        let p = min(max(0, index), pageCount - 1)
        let end = weeks.count - Self.weeksPerPage * p
        let start = end - Self.weeksPerPage
        if start <= 0 { return Array(weeks.prefix(Self.weeksPerPage)) }
        return Array(weeks[start..<end])
    }

    public static func total(_ weeks: [[ContributionDay]]) -> Int { weeks.joined().reduce(0) { $0 + $1.count } }

    /// Columns that start a new month, with the month (1–12), like the labels above GitHub's graph.
    /// The first column is labelled only when its month starts there; labels closer than
    /// `minGap` columns to the previous one are dropped so they don't overlap.
    public static func monthLabels(_ weeks: [[ContributionDay]], minGap: Int = 3) -> [(column: Int, month: Int)] {
        var out: [(Int, Int)] = []
        var previous: Int?
        for (i, w) in weeks.enumerated() {
            guard let first = w.first, let month = first.month else { continue }
            defer { previous = month }
            let starts = i == 0 ? (first.dayOfMonth ?? 99) <= 7 : month != previous
            guard starts else { continue }
            if let last = out.last, i - last.0 < minGap { continue }
            out.append((i, month))
        }
        return out
    }
}

public enum ContributionStore {
    public static func url(paths: AppPaths) -> URL { paths.supportDirectory.appendingPathComponent("github-contributions.json") }

    public static func load(paths: AppPaths) -> ContributionCalendar? {
        guard let data = try? Data(contentsOf: url(paths: paths)) else { return nil }
        return try? SnapshotStore.decoder.decode(ContributionCalendar.self, from: data)
    }

    public static func save(_ calendar: ContributionCalendar, paths: AppPaths) throws {
        try writeAtomically(try SnapshotStore.encoder.encode(calendar), to: url(paths: paths), permissions: 0o600)
    }

    public static func remove(paths: AppPaths) { try? FileManager.default.removeItem(at: url(paths: paths)) }
}
