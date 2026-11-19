import Foundation

// Languages live in `Resources/Languages/<code>.json`, one file per language. Adding a file
// adds the language: nothing in the code lists languages. `LanguageCatalog.problems` (run by
// the unit tests and by `TSAIUsageBar --check-languages` in CI) rejects incomplete files.

/// One supported language and its text.
public struct AppLanguage: Hashable, Sendable, Identifiable {
    /// File name and stored setting value, for example "ja" or "pt-br".
    public let code: String
    /// Name in the language itself, shown in the language picker.
    public let nativeName: String
    /// Locale for dates and durations.
    public let locale: Locale
    /// Position in the language picker.
    public let order: Int
    /// macOS language tags this language serves (see `LanguageCatalog.match`).
    public let matches: [String]
    /// Durations use short unit names instead of abbreviations ("1 ngày 16 giờ").
    public let spellsOutDurations: Bool
    /// Text by key, with English filled in for any missing key.
    let strings: [String: String]

    public var id: String { code }
    public static func == (a: AppLanguage, b: AppLanguage) -> Bool { a.code == b.code }
    public func hash(into h: inout Hasher) { h.combine(code) }

    /// Used only when no language file could be read (keys are shown as text).
    static let placeholder = AppLanguage(code: "en", nativeName: "English", locale: Locale(identifier: "en_US"),
                                         order: 0, matches: ["en"], spellsOutDurations: false, strings: [:])
}

/// The contents of one language file.
struct LanguageFile: Decodable {
    var code: String
    var name: String
    var locale: String
    var order: Int
    var matches: [String]
    /// "abbreviated" (default) or "short".
    var durationStyle: String?
    var strings: [String: String]
}

/// Language choice in Settings: automatic, or a language code.
public enum LanguageSetting: Hashable, Codable, Sendable {
    case automatic
    case fixed(String)

    /// Stored form: "automatic" or a language code. Accepts the 0.1.x values "japanese"/"english".
    public init(storedValue: String) {
        switch storedValue {
        case "", "automatic": self = .automatic
        case "japanese": self = .fixed("ja")
        case "english": self = .fixed("en")
        default: self = .fixed(storedValue)
        }
    }

    public var storedValue: String {
        switch self {
        case .automatic: return "automatic"
        case .fixed(let code): return code
        }
    }
}

/// All language files, read once.
public struct LanguageCatalog: Sendable {
    /// In picker order.
    public let languages: [AppLanguage]

    public init(languages: [AppLanguage]) {
        self.languages = languages.sorted { ($0.order, $0.code) < ($1.order, $1.code) }
    }

    public static let fileExtension = "json"
    public static let fallbackCode = "en"

    /// Reads every language file in `directory`. Missing keys fall back to English.
    public static func load(directory: URL) throws -> LanguageCatalog {
        let files = try readFiles(directory).map(\.file)
        let english = files.first { $0.code == fallbackCode }?.strings ?? [:]
        let languages = files.map { f in
            AppLanguage(code: f.code, nativeName: f.name, locale: Locale(identifier: f.locale), order: f.order,
                        matches: f.matches.map { $0.lowercased() }, spellsOutDurations: f.durationStyle == "short",
                        strings: english.merging(f.strings) { _, own in own })
        }
        return LanguageCatalog(languages: languages)
    }

    /// The app's languages: `Contents/Resources/Languages` in the app bundle, or
    /// `Resources/Languages` above the executable when run from a source checkout.
    public static let main: LanguageCatalog = {
        guard let dir = bundledDirectory(), let c = try? load(directory: dir), !c.languages.isEmpty else {
            return LanguageCatalog(languages: [.placeholder])
        }
        return c
    }()

    public static func bundledDirectory(bundle: Bundle = .main) -> URL? {
        let fm = FileManager.default
        if let r = bundle.resourceURL?.appendingPathComponent("Languages"), fm.fileExists(atPath: r.path) { return r }
        var dir = bundle.executableURL?.deletingLastPathComponent()
        for _ in 0..<6 {
            guard let d = dir else { break }
            let candidate = d.appendingPathComponent("Resources/Languages")
            if fm.fileExists(atPath: candidate.path) { return candidate }
            dir = d.deletingLastPathComponent()
        }
        return nil
    }

    public func language(code: String) -> AppLanguage? { languages.first { $0.code == code } }

    public var english: AppLanguage { language(code: Self.fallbackCode) ?? languages.first ?? .placeholder }

    /// Settings shown in the picker: automatic, then each language.
    public var settings: [LanguageSetting] { [.automatic] + languages.map { .fixed($0.code) } }

    /// A fixed language that has no file (for example after it was removed) acts as automatic.
    /// Automatic picks the first supported macOS preferred language, otherwise English.
    public func resolve(_ setting: LanguageSetting, preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        if case .fixed(let code) = setting, let l = language(code: code) { return l }
        for tag in preferred {
            if let l = match(tag) { return l }
        }
        return english
    }

    /// Matches a macOS language tag against each language's `matches` patterns. A pattern
    /// matches when all its parts appear in the tag with the same base language; the
    /// pattern with the most parts wins ("zh-tw" over "zh"). When the tag names a script
    /// ("zh-Hans-TW"), its region is ignored, so the script decides.
    public func match(_ tag: String) -> AppLanguage? {
        var parts = tag.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        guard let base = parts.first else { return nil }
        if let script = parts.dropFirst().first(where: { $0.count == 4 && $0.allSatisfy(\.isLetter) }) {
            parts = [base, script]
        }
        var best: (AppLanguage, Int)?
        for lang in languages {
            for pattern in lang.matches {
                let p = pattern.split(separator: "-").map(String.init)
                guard p.first == base, p.allSatisfy(parts.contains) else { continue }
                if p.count > best?.1 ?? 0 { best = (lang, p.count) }
            }
        }
        return best?.0
    }

    // MARK: Checks

    private static func readFiles(_ directory: URL) throws -> [(url: URL, file: LanguageFile)] {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            // Skips AppleDouble "._x.json" files that archive tools may leave next to the real ones.
            .filter { $0.pathExtension == fileExtension && !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try urls.map { ($0, try JSONDecoder().decode(LanguageFile.self, from: Data(contentsOf: $0))) }
    }

    /// Everything wrong with the language files, as readable lines; empty when all is well.
    /// Each file must have every key with non-empty text and the same `{placeholders}` as English.
    public static func problems(directory: URL) -> [String] {
        let entries: [(url: URL, file: LanguageFile)]
        do { entries = try readFiles(directory) } catch { return ["cannot read language files: \(error)"] }
        var out: [String] = []
        guard let english = entries.first(where: { $0.file.code == fallbackCode })?.file else {
            return ["\(fallbackCode).\(fileExtension) is missing"]
        }
        let keys = Set(StringKey.allCases.map(\.rawValue))
        var owners: [String: String] = [:]
        var codes = Set<String>()
        for (url, f) in entries {
            let name = url.lastPathComponent
            if url.deletingPathExtension().lastPathComponent != f.code { out.append("\(name): code \"\(f.code)\" does not match the file name") }
            if !codes.insert(f.code).inserted { out.append("\(name): duplicate code \(f.code)") }
            if f.name.trimmingCharacters(in: .whitespaces).isEmpty { out.append("\(name): name is empty") }
            if f.locale.isEmpty { out.append("\(name): locale is empty") }
            if let s = f.durationStyle, !["abbreviated", "short"].contains(s) { out.append("\(name): durationStyle must be abbreviated or short") }
            if f.matches.isEmpty { out.append("\(name): matches is empty") }
            for m in f.matches.map({ $0.lowercased() }) {
                if let other = owners[m], other != f.code { out.append("\(name): match \"\(m)\" is also used by \(other)") }
                owners[m] = f.code
            }
            for k in keys.subtracting(f.strings.keys).sorted() { out.append("\(name): missing \"\(k)\"") }
            for k in Set(f.strings.keys).subtracting(keys).sorted() { out.append("\(name): unknown key \"\(k)\"") }
            for (k, v) in f.strings.sorted(by: { $0.key < $1.key }) where keys.contains(k) {
                if v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append("\(name): \"\(k)\" is empty"); continue }
                let expected = placeholders(english.strings[k] ?? "")
                let found = placeholders(v)
                if found != expected {
                    out.append("\(name): \"\(k)\" has placeholders \(found.sorted()) but English has \(expected.sorted())")
                }
            }
        }
        return out
    }

    static func placeholders(_ s: String) -> Set<String> {
        var found = Set<String>()
        var rest = s[...]
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            found.insert(String(rest[rest.index(after: open)..<close]))
            rest = rest[rest.index(after: close)...]
        }
        return found
    }
}

/// Keys of all user-facing text. Each language file has exactly these keys.
public enum StringKey: String, CaseIterable, Sendable {
    case windowFiveHour = "window.fiveHour"
    case windowSevenDay = "window.sevenDay"
    case windowMonth = "window.month"
    case modeRemaining = "mode.remaining"
    case modeUsed = "mode.used"
    case unavailable
    case awaitingAfterReset
    case resetNewWindowOnNextUse
    case dailyWeeklyTitle
    case dailyMonthlyTitle
    case dailyNoData
    case githubDailyNote
    case loading
    case resetCreditsLine
    case resetCreditsExpiry
    case resetCreditArrived
    case notifyResetCredits
    case notificationsDenied
    case openSystemSettings
    case previousWeek
    case nextWeek
    case notOffered
    case refresh
    case refreshing
    case settings
    case quit
    case never
    case lastUpdated
    case resetLine
    case resetLineWithRemaining
    case codexNotFound
    case codexNotSignedIn
    case fetchTimedOut
    case fetchFailed
    case showingLastValues
    case signInCodex
    case claudeNotSignedIn
    case signInClaude
    case claudeNotInstalled
    case claudeNotLinked
    case claudeWaiting
    case menuBarItems
    case reorderHint
    case keepOneHint
    case numbers
    case language
    case automatic
    case launchAtLogin
    case connections
    case connected
    case notConnected
    case updateAvailable
    case updateNow
    case updating
    case updateFailed
    case upToDate
    case checkingForUpdates
    case signingIn
    case checkForUpdates
    case version
    case privateFreeQuota
    case publicReposFree
    case githubDelay
    case privateFreeQuotaWithBudget
    case legendFree
    case legendBudget
    case budgetRowTitle
    case budgetSpent
    case budgetUsedUp
    case monthlyBudget
    case budgetHelp
    case setBudgetOnGitHub
    case freeQuotaUsedUp
    case githubNotConnected
    case connectGitHub
    case githubEnterCode
    case githubUnknownPlan
    case githubTooManyRepos
    case pausedHidden
    case connect
    case disconnect
    case replacedByUser
    case launchAtLoginNeedsApproval
    case linkTitle
    case linkMessageKeepCurrent = "linkMessage.keepCurrent"
    case linkMessage
    case cancel
    case linkFailed
    case settingsUnreadable
}

/// All user-facing text in one language. Language changes apply without a restart.
public struct Strings: Sendable {
    public let lang: AppLanguage
    public init(_ lang: AppLanguage) { self.lang = lang }

    /// Text for a key; the key itself if no file had it.
    func t(_ key: StringKey) -> String { lang.strings[key.rawValue] ?? key.rawValue }

    /// Text with `{name}` placeholders filled.
    func t(_ key: StringKey, _ values: [String: String]) -> String {
        values.reduce(t(key)) { s, kv in s.replacingOccurrences(of: "{\(kv.key)}", with: kv.value) }
    }

    public func windowTitle(_ kind: WindowKind) -> String {
        switch kind {
        case .fiveHour: return t(.windowFiveHour)
        case .sevenDay: return t(.windowSevenDay)
        case .month: return t(.windowMonth)
        }
    }

    public func modeCaption(_ mode: DisplayMode) -> String {
        mode == .remaining ? t(.modeRemaining) : t(.modeUsed)
    }

    public func resetCreditsLine(_ count: Int) -> String { t(.resetCreditsLine, ["count": String(count)]) }
    public func resetCreditsExpiry(_ date: String) -> String { t(.resetCreditsExpiry, ["date": date]) }
    public func resetCreditArrived(_ remaining: Int) -> String { t(.resetCreditArrived, ["count": String(remaining)]) }
    public func lastUpdated(_ text: String) -> String { t(.lastUpdated, ["time": text]) }
    public func resetLine(_ time: String, remaining: String?) -> String {
        guard let remaining else { return t(.resetLine, ["time": time]) }
        return t(.resetLineWithRemaining, ["time": time, "remaining": remaining])
    }
    public func updateAvailable(_ v: String) -> String { t(.updateAvailable, ["version": v]) }
    public func privateFreeQuotaWithBudget(_ amount: String) -> String { t(.privateFreeQuotaWithBudget, ["amount": amount]) }
    public func budgetRowTitle(_ amount: String) -> String { t(.budgetRowTitle, ["amount": amount]) }
    public func budgetSpent(_ used: String, _ total: String) -> String { t(.budgetSpent, ["used": used, "total": total]) }
    public func githubEnterCode(_ code: String) -> String { t(.githubEnterCode, ["code": code]) }

    public func itemName(_ id: ItemID) -> String {
        "\(id.provider.displayName) \(id.window.letter) (\(windowTitle(id.window)))"
    }

    public func linkMessage(existing: String?, settingsPath: String) -> String {
        let keep = existing.map { t(.linkMessageKeepCurrent, ["command": $0]) } ?? ""
        return t(.linkMessage, ["path": settingsPath, "keep": keep])
    }

    public var unavailable: String { t(.unavailable) }
    public var awaitingAfterReset: String { t(.awaitingAfterReset) }
    public var resetNewWindowOnNextUse: String { t(.resetNewWindowOnNextUse) }
    public var dailyWeeklyTitle: String { t(.dailyWeeklyTitle) }
    public var dailyMonthlyTitle: String { t(.dailyMonthlyTitle) }
    public var dailyNoData: String { t(.dailyNoData) }
    public var githubDailyNote: String { t(.githubDailyNote) }
    public var loading: String { t(.loading) }
    public var notifyResetCredits: String { t(.notifyResetCredits) }
    public var notificationsDenied: String { t(.notificationsDenied) }
    public var openSystemSettings: String { t(.openSystemSettings) }
    public var previousWeek: String { t(.previousWeek) }
    public var nextWeek: String { t(.nextWeek) }
    public var notOffered: String { t(.notOffered) }
    public var refresh: String { t(.refresh) }
    public var refreshing: String { t(.refreshing) }
    public var settings: String { t(.settings) }
    public var quit: String { t(.quit) }
    public var never: String { t(.never) }
    public var codexNotFound: String { t(.codexNotFound) }
    public var codexNotSignedIn: String { t(.codexNotSignedIn) }
    public var fetchTimedOut: String { t(.fetchTimedOut) }
    public var fetchFailed: String { t(.fetchFailed) }
    public var showingLastValues: String { t(.showingLastValues) }
    public var signInCodex: String { t(.signInCodex) }
    public var claudeNotSignedIn: String { t(.claudeNotSignedIn) }
    public var signInClaude: String { t(.signInClaude) }
    public var claudeNotInstalled: String { t(.claudeNotInstalled) }
    public var claudeNotLinked: String { t(.claudeNotLinked) }
    public var claudeWaiting: String { t(.claudeWaiting) }
    public var menuBarItems: String { t(.menuBarItems) }
    public var reorderHint: String { t(.reorderHint) }
    public var keepOneHint: String { t(.keepOneHint) }
    public var numbers: String { t(.numbers) }
    public var language: String { t(.language) }
    public var automatic: String { t(.automatic) }
    public var launchAtLogin: String { t(.launchAtLogin) }
    public var connections: String { t(.connections) }
    public var connected: String { t(.connected) }
    public var notConnected: String { t(.notConnected) }
    public var updateNow: String { t(.updateNow) }
    public var updating: String { t(.updating) }
    public var updateFailed: String { t(.updateFailed) }
    public var upToDate: String { t(.upToDate) }
    public var checkingForUpdates: String { t(.checkingForUpdates) }
    public var signingIn: String { t(.signingIn) }
    public var checkForUpdates: String { t(.checkForUpdates) }
    public var version: String { t(.version) }
    public var privateFreeQuota: String { t(.privateFreeQuota) }
    public var publicReposFree: String { t(.publicReposFree) }
    public var githubDelay: String { t(.githubDelay) }
    public var legendFree: String { t(.legendFree) }
    public var legendBudget: String { t(.legendBudget) }
    public var budgetUsedUp: String { t(.budgetUsedUp) }
    public var monthlyBudget: String { t(.monthlyBudget) }
    public var budgetHelp: String { t(.budgetHelp) }
    public var setBudgetOnGitHub: String { t(.setBudgetOnGitHub) }
    public var freeQuotaUsedUp: String { t(.freeQuotaUsedUp) }
    public var githubNotConnected: String { t(.githubNotConnected) }
    public var connectGitHub: String { t(.connectGitHub) }
    public var githubUnknownPlan: String { t(.githubUnknownPlan) }
    public var githubTooManyRepos: String { t(.githubTooManyRepos) }
    public var pausedHidden: String { t(.pausedHidden) }
    public var connect: String { t(.connect) }
    public var disconnect: String { t(.disconnect) }
    public var replacedByUser: String { t(.replacedByUser) }
    public var launchAtLoginNeedsApproval: String { t(.launchAtLoginNeedsApproval) }
    public var linkTitle: String { t(.linkTitle) }
    public var cancel: String { t(.cancel) }
    public var linkFailed: String { t(.linkFailed) }
    public var settingsUnreadable: String { t(.settingsUnreadable) }
}

/// Formats reset times in the Mac's local time zone, in the app's language.
public struct TimeText: Sendable {
    public let lang: AppLanguage
    public var timeZone: TimeZone

    public init(_ lang: AppLanguage, timeZone: TimeZone = .current) {
        self.lang = lang
        self.timeZone = timeZone
    }

    /// Same day: time only. Otherwise date and time. Uses the language's own 12/24-hour style.
    public func reset(_ date: Date, now: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let f = DateFormatter()
        f.locale = lang.locale
        f.timeZone = timeZone
        f.setLocalizedDateFormatFromTemplate(cal.isDate(date, inSameDayAs: now) ? "jmm" : "MMMdjmm")
        return f.string(from: date)
    }

    /// Two largest units, rounded up to the minute: `5日3時間`, `2h 15m`, `5วัน 3ชม.`.
    public func duration(_ interval: TimeInterval) -> String {
        let minutes = max(0, (interval / 60).rounded(.up))
        let f = DateComponentsFormatter()
        var cal = Calendar(identifier: .gregorian)
        cal.locale = lang.locale
        f.calendar = cal
        f.allowedUnits = [.day, .hour, .minute]
        f.maximumUnitCount = 2
        // Some abbreviations run number and unit together (Vietnamese "1ngày 16g"); such languages set durationStyle "short".
        f.unitsStyle = lang.spellsOutDurations ? .short : .abbreviated
        f.zeroFormattingBehavior = .dropAll
        return f.string(from: max(60, minutes * 60)) ?? ""
    }

    public func clock(_ date: Date, now: Date) -> String { reset(date, now: now) }
}
