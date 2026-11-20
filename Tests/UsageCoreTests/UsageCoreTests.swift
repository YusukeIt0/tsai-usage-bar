import XCTest
@testable import UsageCore

final class CodexParserTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func window(_ used: Double, _ mins: Int?, _ reset: Double?) -> [String: Any] {
        var w: [String: Any] = ["usedPercent": used]
        w["windowDurationMins"] = mins.map { $0 as Any } ?? NSNull()
        w["resetsAt"] = reset.map { $0 as Any } ?? NSNull()
        return w
    }

    func testMatchesWindowsByDurationNotPosition() throws {
        let bucket: [String: Any] = ["limitId": "codex",
                                     "primary": window(68, 10080, 1_800_500_000),
                                     "secondary": window(42, 300, 1_800_010_000)]
        let snap = try CodexRateLimitParser.parse(result: ["rateLimitsByLimitId": ["codex": bucket]], fetchedAt: now)
        XCTAssertEqual(snap[.fiveHour]?.usedPercent, 42)
        XCTAssertEqual(snap[.sevenDay]?.usedPercent, 68)
        XCTAssertEqual(snap[.fiveHour]?.resetsAt, Date(timeIntervalSince1970: 1_800_010_000))
    }

    func testWeeklyOnlyPlanReportsNoFiveHourWindow() throws {
        // Observed on a real account: only a 7-day window is returned.
        let bucket: [String: Any] = ["limitId": "codex", "primary": window(100, 10080, 1_800_500_000), "secondary": NSNull()]
        let snap = try CodexRateLimitParser.parse(result: ["rateLimits": bucket], fetchedAt: now)
        XCTAssertNil(snap[.fiveHour])
        XCTAssertFalse(snap.offers(.fiveHour))
        XCTAssertTrue(snap.offers(.sevenDay))
        XCTAssertEqual(ItemVisibility.defaultItem(for: .codex, snapshot: snap), ItemID(.codex, .sevenDay))
    }

    func testUnknownDurationsAreNotSubstituted() throws {
        let bucket: [String: Any] = ["primary": window(10, 60, nil), "secondary": window(20, nil, nil)]
        let snap = try CodexRateLimitParser.parse(result: ["rateLimits": bucket], fetchedAt: now)
        XCTAssertTrue(snap.windows.isEmpty)
    }

    func testOtherBucketIsIgnored() {
        let other: [String: Any] = ["limitId": "codex_other", "primary": window(5, 300, nil)]
        XCTAssertThrowsError(try CodexRateLimitParser.parse(result: ["rateLimits": other], fetchedAt: now))
    }

    func testPrefersCodexBucketInMultiView() throws {
        let other: [String: Any] = ["limitId": "codex_other", "primary": window(5, 300, nil)]
        let codex: [String: Any] = ["limitId": "codex", "primary": window(30, 300, nil)]
        let snap = try CodexRateLimitParser.parse(
            result: ["rateLimits": other, "rateLimitsByLimitId": ["codex_other": other, "codex": codex]], fetchedAt: now)
        XCTAssertEqual(snap[.fiveHour]?.usedPercent, 30)
    }
}

final class ClaudeParserTests: XCTestCase {
    func testParsesStatusLineRateLimits() throws {
        let json = #"{"session_id":"x","transcript_path":"/tmp/t","rate_limits":{"five_hour":{"used_percentage":12.4,"resets_at":1794943800},"seven_day":{"used_percentage":3,"resets_at":1795204800}}}"#
        let w = try ClaudeStatusLineParser.parseWindows(Data(json.utf8))
        XCTAssertEqual(w[.fiveHour]?.usedPercent, 12.4)
        XCTAssertEqual(w[.sevenDay]?.resetsAt, Date(timeIntervalSince1970: 1795204800))
    }

    func testNoRateLimitsYieldsNothing() throws {
        XCTAssertTrue(try ClaudeStatusLineParser.parseWindows(Data(#"{"model":{}}"#.utf8)).isEmpty)
    }

    func testPlanWithoutFiveHourWindow() throws {
        let json = #"{"rate_limits":{"seven_day":{"used_percentage":40,"resets_at":1795204800}}}"#
        let w = try ClaudeStatusLineParser.parseWindows(Data(json.utf8))
        let snap = SnapshotStore.merge(w, into: nil, at: Date(timeIntervalSince1970: 1_795_000_000))
        XCTAssertFalse(snap.offers(.fiveHour))
        XCTAssertEqual(ItemVisibility.defaultItem(for: .claude, snapshot: snap), ItemID(.claude, .sevenDay))
    }

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(try ClaudeStatusLineParser.parseWindows(Data("nope".utf8)))
    }
}

final class DisplayTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func snap(_ used: Double, reset: Date?, fetched: Date) -> ProviderSnapshot {
        ProviderSnapshot(windows: [.fiveHour: UsageWindow(usedPercent: used, resetsAt: reset)], fetchedAt: fetched)
    }

    func testLabelsAndModes() {
        let d = WindowDisplay.evaluate(snap(58, reset: t0 + 3600, fetched: t0), .fiveHour, now: t0)
        XCTAssertEqual(d.label(.fiveHour, mode: .remaining), "H42%")
        XCTAssertEqual(d.label(.fiveHour, mode: .used), "H58%")
        let full = WindowDisplay.evaluate(snap(0, reset: t0 + 3600, fetched: t0), .fiveHour, now: t0)
        XCTAssertEqual(full.label(.fiveHour, mode: .remaining), "H100%")
    }

    func testRemainingAndUsedAlwaysSumTo100() {
        for used in stride(from: 0.0, through: 100.0, by: 0.25) {
            let d = WindowDisplay.value(usedPercent: used, resetsAt: nil)
            XCTAssertEqual(d.percent(mode: .used)! + d.percent(mode: .remaining)!, 100)
        }
    }

    func testMissingValueIsNotGuessed() {
        let d = WindowDisplay.evaluate(nil, .sevenDay, now: t0)
        XCTAssertEqual(d, .unavailable)
        XCTAssertEqual(d.label(.sevenDay, mode: .remaining), "W—")
    }

    func testResetPassedWaitsForCodexAndGitHub() {
        let s = snap(90, reset: t0 + 60, fetched: t0)
        XCTAssertEqual(WindowDisplay.evaluate(s, .fiveHour, now: t0 + 59).label(.fiveHour, mode: .remaining), "H10%")
        let d = WindowDisplay.evaluate(s, .fiveHour, now: t0 + 61)
        XCTAssertEqual(d, .awaitingUpdateAfterReset(resetAt: t0 + 60))
        XCTAssertEqual(d.label(.fiveHour, mode: .remaining), "H—")
    }

    func testResetPassedShowsFullWindowForClaude() {
        // Owner decision (2026-11-18), Claude Code only: back to full after the reset time.
        let s = snap(90, reset: t0 + 60, fetched: t0)
        let d = WindowDisplay.evaluate(s, .fiveHour, now: t0 + 61, fullAfterReset: true)
        XCTAssertEqual(d, .resetPassed(resetAt: t0 + 60))
        XCTAssertEqual(d.label(.fiveHour, mode: .remaining), "H100%")
        XCTAssertEqual(d.label(.fiveHour, mode: .used), "H0%")
    }

    func testNewDataAfterResetIsShown() {
        let s = snap(3, reset: t0 + 18_000, fetched: t0 + 70)
        XCTAssertEqual(WindowDisplay.evaluate(s, .fiveHour, now: t0 + 80).percent(mode: .remaining), 97)
    }

    func testCachedPreResetCopyDoesNotReplaceValues() {
        // An idle Claude Code session can re-send its cached, already-reset values.
        let first = SnapshotStore.merge([.fiveHour: UsageWindow(usedPercent: 80, resetsAt: t0 + 60)], into: nil, at: t0)
        let resent = SnapshotStore.merge([.fiveHour: UsageWindow(usedPercent: 80, resetsAt: t0 + 60)], into: first, at: t0 + 120)
        XCTAssertEqual(WindowDisplay.evaluate(resent, .fiveHour, now: t0 + 120, fullAfterReset: true), .resetPassed(resetAt: t0 + 60))
    }

    func testMergeKeepsPerWindowTimes() {
        let a = SnapshotStore.merge([.fiveHour: UsageWindow(usedPercent: 10, resetsAt: t0 + 100),
                                     .sevenDay: UsageWindow(usedPercent: 20, resetsAt: t0 + 10_000)], into: nil, at: t0)
        let b = SnapshotStore.merge([.fiveHour: UsageWindow(usedPercent: 15, resetsAt: t0 + 100),
                                     .sevenDay: UsageWindow(usedPercent: 20, resetsAt: t0 + 10_000)], into: a, at: t0 + 50)
        XCTAssertEqual(b[.fiveHour]?.usedPercent, 15)
        XCTAssertEqual(b[.fiveHour]?.observedAt, t0 + 50)
    }

    func testSnapshotRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("s.json")
        let s = ProviderSnapshot(windows: [.sevenDay: UsageWindow(usedPercent: 33, resetsAt: t0)], fetchedAt: t0)
        try SnapshotStore.save(s, to: url)
        XCTAssertEqual(SnapshotStore.load(url), s)
    }
}

final class VisibilityTests: XCTestCase {
    func testHidesWindowsNotOfferedAndKeepsOneVisible() {
        let weeklyOnly = ProviderSnapshot(windows: [.sevenDay: UsageWindow(usedPercent: 1, resetsAt: nil)], fetchedAt: Date())
        let enabled: Set<ItemID> = [ItemID(.codex, .fiveHour), ItemID(.codex, .sevenDay)]
        XCTAssertEqual(ItemVisibility.visible(enabled: enabled, snapshots: [.codex: weeklyOnly]), [ItemID(.codex, .sevenDay)])
        XCTAssertEqual(ItemVisibility.visible(enabled: [], snapshots: [:]), [ItemID(.claude, .fiveHour)])
        XCTAssertEqual(ItemVisibility.visible(enabled: [ItemID(.codex, .fiveHour)], snapshots: [.codex: weeklyOnly]),
                       [ItemID(.codex, .fiveHour)])
    }

    func testProvidersWithAllItemsOffArePaused() {
        let all = Set(Provider.allCases)
        XCTAssertEqual(ItemVisibility.activeProviders(enabled: [ItemID(.claude, .fiveHour)], initialized: all), [.claude])
        XCTAssertEqual(ItemVisibility.activeProviders(enabled: [ItemID(.codex, .sevenDay), ItemID(.claude, .sevenDay)],
                                                      initialized: all), [.claude, .codex])
        XCTAssertEqual(ItemVisibility.activeProviders(enabled: [ItemID(.github, .month)], initialized: all), [.github])
        // Not reported yet: keep active so available windows can be learned.
        XCTAssertEqual(ItemVisibility.activeProviders(enabled: [ItemID(.claude, .fiveHour)], initialized: [.claude]), all)
    }

    func testUnknownProviderStateDoesNotHide() {
        let enabled: Set<ItemID> = [ItemID(.claude, .fiveHour), ItemID(.codex, .fiveHour)]
        XCTAssertEqual(ItemVisibility.visible(enabled: enabled, snapshots: [:]).count, 2)
    }
}

final class FetchPolicyTests: XCTestCase {
    let p = FetchPolicy()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testIntervals() {
        XCTAssertEqual(p.nextDelay(now: t0, lastAttempt: nil, consecutiveFailures: 0, popoverOpen: false, resetTimes: []), 0)
        XCTAssertEqual(p.nextDelay(now: t0, lastAttempt: t0, consecutiveFailures: 0, popoverOpen: false, resetTimes: []), 180)
        XCTAssertEqual(p.nextDelay(now: t0, lastAttempt: t0, consecutiveFailures: 0, popoverOpen: true, resetTimes: []), 60)
    }

    func testBackoffIsCapped() {
        let d1 = p.nextDelay(now: t0, lastAttempt: t0, consecutiveFailures: 1, popoverOpen: false, resetTimes: [])
        let d3 = p.nextDelay(now: t0, lastAttempt: t0, consecutiveFailures: 3, popoverOpen: false, resetTimes: [])
        let d9 = p.nextDelay(now: t0, lastAttempt: t0, consecutiveFailures: 9, popoverOpen: false, resetTimes: [])
        XCTAssertEqual(d1, 180)
        XCTAssertEqual(d3, 720)
        XCTAssertEqual(d9, 1800)
    }

    func testFetchesRightAfterReset() {
        let d = p.nextDelay(now: t0, lastAttempt: t0 - 100, consecutiveFailures: 0, popoverOpen: false, resetTimes: [t0 + 30])
        XCTAssertEqual(d, 35)
    }

    func testRepeatedClicksAreMerged() {
        XCTAssertFalse(p.shouldFetchOnDemand(now: t0, lastAttempt: t0 - 3, lastSuccess: t0 - 3))
        XCTAssertFalse(p.shouldFetchOnDemand(now: t0, lastAttempt: t0 - 20, lastSuccess: t0 - 20))
        XCTAssertTrue(p.shouldFetchOnDemand(now: t0, lastAttempt: t0 - 40, lastSuccess: t0 - 40))
        XCTAssertTrue(p.shouldFetchOnDemand(now: t0, lastAttempt: nil, lastSuccess: nil))
    }
}

/// The real language files in `Resources/Languages`.
enum TestLanguages {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Languages")
    static let catalog: LanguageCatalog = {
        do { return try LanguageCatalog.load(directory: directory) } catch { fatalError("language files: \(error)") }
    }()
    static func lang(_ code: String) -> AppLanguage {
        guard let l = catalog.language(code: code) else { fatalError("no language \(code)") }
        return l
    }
}

final class LocalizationTests: XCTestCase {
    let c = TestLanguages.catalog
    func L(_ code: String) -> AppLanguage { TestLanguages.lang(code) }

    /// The check CI relies on: every file has every key, non-empty text and the same
    /// placeholders as English, and its code matches the file name.
    func testLanguageFilesAreComplete() {
        XCTAssertEqual(LanguageCatalog.problems(directory: TestLanguages.directory), [])
    }

    func testProblemsAreReported() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let en = try Data(contentsOf: TestLanguages.directory.appendingPathComponent("en.json"))
        try en.write(to: dir.appendingPathComponent("en.json"))
        var obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: en) as? [String: Any])
        var strings = try XCTUnwrap(obj["strings"] as? [String: String])
        strings["settings"] = nil                                  // missing key
        strings["lastUpdated"] = "Updated {when}"                  // wrong placeholder
        strings["quit"] = " "                                      // empty
        strings["extra"] = "x"                                     // unknown key
        obj["strings"] = strings
        obj["code"] = "xx"
        obj["matches"] = ["en"]                                    // already English's
        try JSONSerialization.data(withJSONObject: obj).write(to: dir.appendingPathComponent("xx.json"))
        let problems = LanguageCatalog.problems(directory: dir).joined(separator: "\n")
        for expected in ["missing \"settings\"", "\"lastUpdated\" has placeholders", "\"quit\" is empty",
                         "unknown key \"extra\"", "match \"en\" is also used by"] {
            XCTAssertTrue(problems.contains(expected), expected)
        }
        // A file named differently from its code.
        try FileManager.default.moveItem(at: dir.appendingPathComponent("xx.json"), to: dir.appendingPathComponent("yy.json"))
        XCTAssertTrue(LanguageCatalog.problems(directory: dir).joined().contains("does not match the file name"))
    }

    func testMissingKeysFallBackToEnglish() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(contentsOf: TestLanguages.directory.appendingPathComponent("en.json")).write(to: dir.appendingPathComponent("en.json"))
        let partial = #"{"code":"xx","name":"X","locale":"en","order":99,"matches":["xx"],"strings":{"quit":"Q"}}"#
        try Data(partial.utf8).write(to: dir.appendingPathComponent("xx.json"))
        try Data([0, 5, 22, 7]).write(to: dir.appendingPathComponent("._xx.json")) // AppleDouble leftover
        let catalog = try LanguageCatalog.load(directory: dir)
        XCTAssertEqual(LanguageCatalog.problems(directory: dir).filter { $0.contains("cannot read") }, [])
        let s = Strings(try XCTUnwrap(catalog.language(code: "xx")))
        XCTAssertEqual(s.quit, "Q")
        XCTAssertEqual(s.settings, "Settings")
        XCTAssertEqual(catalog.languages.map(\.code), ["en", "xx"])
    }

    func testAutomaticLanguage() {
        let auto = LanguageSetting.automatic
        func r(_ preferred: [String]) -> String { c.resolve(auto, preferred: preferred).code }
        XCTAssertEqual(r(["ja-JP", "en-US"]), "ja")
        XCTAssertEqual(r(["en-GB"]), "en")
        XCTAssertEqual(r(["th-TH", "ja-JP"]), "th")
        // The first supported preference wins; unsupported ones are skipped.
        XCTAssertEqual(r(["nl-NL", "de-DE", "ja-JP"]), "de")
        XCTAssertEqual(r(["nl-NL", "sv-SE"]), "en")
        XCTAssertEqual(r([]), "en")
        XCTAssertEqual(r(["fr-CA"]), "fr")
        XCTAssertEqual(r(["ko-KR"]), "ko")
        XCTAssertEqual(r(["pt-BR"]), "pt-br")
        XCTAssertEqual(r(["pt-PT"]), "pt-br")
        XCTAssertEqual(r(["id-ID"]), "id")
        XCTAssertEqual(r(["in"]), "id")
        XCTAssertEqual(r(["es-MX"]), "es")
        XCTAssertEqual(r(["es-419"]), "es")
        XCTAssertEqual(r(["ru-KZ"]), "ru")
        XCTAssertEqual(r(["vi-VN"]), "vi")
        XCTAssertEqual(r(["uk-UA", "ru-RU"]), "ru") // first supported wins
        // Chinese: explicit script first, then region.
        XCTAssertEqual(r(["zh-Hant-HK"]), "zh-hant")
        XCTAssertEqual(r(["zh-Hans-TW"]), "zh-hans")
        XCTAssertEqual(r(["zh-Hant"]), "zh-hant")
        XCTAssertEqual(r(["zh-TW"]), "zh-hant")
        XCTAssertEqual(r(["zh-HK"]), "zh-hant")
        XCTAssertEqual(r(["zh-MO"]), "zh-hant")
        XCTAssertEqual(r(["zh-CN"]), "zh-hans")
        XCTAssertEqual(r(["zh"]), "zh-hans")
        XCTAssertEqual(r(["zh_TW"]), "zh-hant")
        XCTAssertEqual(c.resolve(.fixed("ja"), preferred: ["en"]).code, "ja")
        // A fixed language without a file acts as automatic.
        XCTAssertEqual(c.resolve(.fixed("nl"), preferred: ["de-DE"]).code, "de")
    }

    func testSettingStorageAndMigration() {
        XCTAssertEqual(LanguageSetting(storedValue: "japanese"), .fixed("ja")) // 0.1.x value
        XCTAssertEqual(LanguageSetting(storedValue: "english"), .fixed("en"))
        XCTAssertEqual(LanguageSetting(storedValue: "automatic"), .automatic)
        XCTAssertEqual(LanguageSetting(storedValue: ""), .automatic)
        XCTAssertEqual(LanguageSetting(storedValue: "zh-hant"), .fixed("zh-hant"))
        for s in c.settings { XCTAssertEqual(LanguageSetting(storedValue: s.storedValue), s) }
        // Picker order and stored codes are unchanged from 0.1.18.
        XCTAssertEqual(c.languages.map(\.code),
                       ["en", "ja", "zh-hant", "zh-hans", "ko", "fr", "de", "th", "pt-br", "id", "es", "ru", "vi"])
        XCTAssertEqual(c.settings.count, 14)
    }

    func testEveryLanguageHasDistinctLocalizedText() {
        // Each language returns its own text (no silent English fallback) and fills placeholders.
        var titles = Set<String>()
        for lang in c.languages {
            let s = Strings(lang)
            titles.insert(s.settings + s.language + s.refresh)
            let line = s.resetLine("X", remaining: "Y")
            XCTAssertTrue(line.contains("X") && line.contains("Y") && !line.contains("{"), lang.code)
            XCTAssertTrue(s.updateAvailable("9.9").contains("9.9"), lang.code)
            XCTAssertTrue(s.linkMessage(existing: "cmd", settingsPath: "P").contains("cmd"), lang.code)
            XCTAssertFalse(s.linkMessage(existing: nil, settingsPath: "P").contains("{"), lang.code)
            XCTAssertFalse(TimeText(lang).duration(444_000).isEmpty)
        }
        XCTAssertEqual(titles.count, c.languages.count)
    }

    func testLocalTimeFormatting() {
        let tz = TimeZone(identifier: "Asia/Tokyo")!
        let now = ISO8601DateFormatter().date(from: "2026-11-17T07:00:00Z")! // 16:00 JST
        let sameDay = ISO8601DateFormatter().date(from: "2026-11-17T09:40:00Z")! // 18:40 JST
        let later = ISO8601DateFormatter().date(from: "2026-11-23T00:00:00Z")! // 11/23 09:00 JST
        XCTAssertEqual(TimeText(L("ja"), timeZone: tz).reset(sameDay, now: now), "18:40")
        XCTAssertEqual(TimeText(L("ja"), timeZone: tz).reset(later, now: now), "11月23日 9:00")
        XCTAssertEqual(TimeText(L("ko")).duration(5 * 3600 + 3 * 60), "5시간 3분")
        XCTAssertEqual(TimeText(L("zh-hans")).duration(TimeInterval(2 * 86_400)), "2天")
        XCTAssertEqual(TimeText(L("ja")).duration(2 * 3600 + 15 * 60), "2時間15分")
        XCTAssertEqual(TimeText(L("en")).duration(2 * 3600 + 15 * 60), "2h 15m")
        // 7-day windows show days and hours.
        let fiveDays: TimeInterval = 444_000 // 5 days, 3 hours, 20 minutes
        XCTAssertEqual(TimeText(L("ja")).duration(fiveDays), "5日3時間")
        XCTAssertEqual(TimeText(L("en")).duration(fiveDays), "5d 3h")
        XCTAssertEqual(TimeText(L("ja")).duration(TimeInterval(6 * 86_400)), "6日")
        XCTAssertEqual(Strings(L("ja")).resetLine("11月23日 9:00", remaining: "5日3時間"), "リセット：11月23日 9:00（あと5日3時間）")
        XCTAssertEqual(Strings(L("ja")).resetLine("18:40", remaining: "2時間15分"), "リセット：18:40（あと2時間15分）")
    }
}

final class StatusLineLinkTests: XCTestCase {
    var dir: URL!
    var paths: AppPaths!
    var settingsURL: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        paths = AppPaths(supportDirectory: dir.appendingPathComponent("support"))
        settingsURL = dir.appendingPathComponent("claude/settings.json")
        try FileManager.default.createDirectory(at: paths.hookDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: paths.installedHookURL.path, contents: Data("#!/bin/sh\n".utf8),
                                       attributes: [.posixPermissions: 0o755])
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func readSettings() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as! [String: Any]
    }

    func testLinkKeepsExistingStatusLineAndRestoresIt() throws {
        let original = #"{"model":"opus","statusLine":{"type":"command","command":"~/my-line.sh","padding":2},"hooks":{"x":1}}"#
        try Data(original.utf8).write(to: settingsURL)
        let link = StatusLineLink(paths: paths, settingsURL: settingsURL)

        try link.link()
        var s = try readSettings()
        let sl = s["statusLine"] as! [String: Any]
        XCTAssertTrue((sl["command"] as! String).contains("tsai-usagebar-hook"))
        XCTAssertEqual(sl["padding"] as? Int, 2)
        XCTAssertEqual(s["model"] as? String, "opus")
        XCTAssertNotNil(s["hooks"])
        XCTAssertEqual(link.state(), .linked)
        XCTAssertEqual(link.originalCommand(), "~/my-line.sh")
        XCTAssertNotNil(link.loadRecord()?.backupPath)

        try link.link() // idempotent: does not record itself as the original
        XCTAssertEqual(link.originalCommand(), "~/my-line.sh")

        try link.unlink()
        s = try readSettings()
        XCTAssertEqual((s["statusLine"] as! [String: Any])["command"] as? String, "~/my-line.sh")
        XCTAssertEqual((s["statusLine"] as! [String: Any])["padding"] as? Int, 2)
        XCTAssertEqual(link.state(), .notLinked)
    }

    func testLinkWithoutExistingSettings() throws {
        let link = StatusLineLink(paths: paths, settingsURL: settingsURL)
        try link.link()
        XCTAssertEqual(link.state(), .linked)
        XCTAssertNil(link.originalCommand())
        try link.unlink()
        XCTAssertNil(try readSettings()["statusLine"])
    }

    func testUnlinkDoesNotOverrideUserChange() throws {
        try Data(#"{"statusLine":{"type":"command","command":"a.sh"}}"#.utf8).write(to: settingsURL)
        let link = StatusLineLink(paths: paths, settingsURL: settingsURL)
        try link.link()
        try Data(#"{"statusLine":{"type":"command","command":"b.sh"}}"#.utf8).write(to: settingsURL)
        XCTAssertEqual(link.state(), .replacedByUser)
        try link.unlink()
        XCTAssertEqual((try readSettings()["statusLine"] as! [String: Any])["command"] as? String, "b.sh")
    }

    func testInvalidSettingsAreNotTouched() throws {
        try Data("{ broken".utf8).write(to: settingsURL)
        let link = StatusLineLink(paths: paths, settingsURL: settingsURL)
        XCTAssertThrowsError(try link.link())
        XCTAssertEqual(try String(contentsOf: settingsURL, encoding: .utf8), "{ broken")
    }

    func testRequiresInstalledHook() throws {
        try FileManager.default.removeItem(at: paths.installedHookURL)
        XCTAssertThrowsError(try StatusLineLink(paths: paths, settingsURL: settingsURL).link())
    }
}

final class UpdateTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertLessThan(AppVersion("0.1.9")!, AppVersion("0.1.10")!)
        XCTAssertLessThan(AppVersion("v0.1.3")!, AppVersion("0.2")!)
        XCTAssertEqual(AppVersion("0.1")!, AppVersion("0.1.0")!)
        XCTAssertNil(AppVersion("dev"))
        XCTAssertNil(AppVersion("0.1.4-beta"))
        XCTAssertNil(AppVersion("1..2"))
    }

    func testParsesOnlyPublishedReleases() {
        let ok = #"{"tag_name":"v0.1.4","draft":false,"prerelease":false}"#
        XCTAssertEqual(ReleaseInfo.latestVersion(fromJSON: Data(ok.utf8)), AppVersion("0.1.4"))
        XCTAssertNil(ReleaseInfo.latestVersion(fromJSON: Data(#"{"tag_name":"v0.2.0","prerelease":true}"#.utf8)))
        XCTAssertNil(ReleaseInfo.latestVersion(fromJSON: Data(#"{"tag_name":"v0.2.0","draft":true}"#.utf8)))
        XCTAssertNil(ReleaseInfo.latestVersion(fromJSON: Data("{}".utf8)))
    }

    func testUpdateOnlyWhenNewerAndKnown() {
        XCTAssertTrue(ReleaseInfo.isUpdate(latest: AppVersion("0.1.4"), current: AppVersion("0.1.3")))
        XCTAssertFalse(ReleaseInfo.isUpdate(latest: AppVersion("0.1.3"), current: AppVersion("0.1.3")))
        XCTAssertFalse(ReleaseInfo.isUpdate(latest: AppVersion("0.1.2"), current: AppVersion("0.1.3")))
        XCTAssertFalse(ReleaseInfo.isUpdate(latest: AppVersion("0.1.4"), current: nil)) // dev build
        XCTAssertEqual(ReleaseInfo.installerURL(for: AppVersion("0.1.4")!).absoluteString,
                       "https://raw.githubusercontent.com/YusukeIt0/tsai-usage-bar/v0.1.4/install.sh")
    }
}

final class GitHubActionsUsageTests: XCTestCase {
    typealias Item = GitHubActionsUsage.Item

    func summary(_ items: [(String, Double)]) -> Data {
        let arr = items.map { ["product": "Actions", "sku": $0.0, "grossAmount": $0.1] as [String: Any] }
        return try! JSONSerialization.data(withJSONObject: ["usageItems": arr])
    }

    func testPrivateUsageIsTotalMinusPublicRepositories() throws {
        // Real November 2026 shape: two public repositories and one private one.
        let total = try GitHubActionsUsage.items(fromSummaryJSON: summary([
            ("actions_linux", 56.262), ("actions_macos", 56.234), ("actions_storage", 0.0039)]))
        let dotLink = try GitHubActionsUsage.items(fromSummaryJSON: summary([
            ("actions_linux", 34.812), ("actions_macos", 55.18), ("actions_storage", 0.0018)]))
        let tsai = try GitHubActionsUsage.items(fromSummaryJSON: summary([("actions_macos", 1.054)]))
        XCTAssertEqual(total.count, 2) // storage is a separate allowance
        let now = ISO8601DateFormatter().date(from: "2026-11-18T03:00:00Z")!
        let w = try GitHubActionsUsage.window(plan: "pro", total: total, publicRepos: [dotLink, tsai], now: now)
        XCTAssertEqual(w.usedPercent, 100) // 21.45 of 18 USD: used up, never above 100
        XCTAssertEqual(w.resetsAt, ISO8601DateFormatter().date(from: "2026-12-01T00:00:00Z"))
    }

    func testPartialUseAndPlans() throws {
        let total = [Item(sku: "actions_linux", grossAmount: 6)]
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(try GitHubActionsUsage.window(plan: "pro", total: total, publicRepos: [], now: now).usedPercent, 100.0 / 3, accuracy: 0.001)
        XCTAssertEqual(try GitHubActionsUsage.window(plan: "free", total: total, publicRepos: [], now: now).usedPercent, 50)
        XCTAssertEqual(try GitHubActionsUsage.window(plan: "pro", total: [], publicRepos: [], now: now).usedPercent, 0)
        // Unknown plans are not guessed.
        XCTAssertThrowsError(try GitHubActionsUsage.window(plan: "business", total: total, publicRepos: [], now: now))
        XCTAssertThrowsError(try GitHubActionsUsage.window(plan: nil, total: total, publicRepos: [], now: now))
    }

    func testOnlyActionsComputeCounts() throws {
        let data = try! JSONSerialization.data(withJSONObject: ["usageItems": [
            ["product": "Actions", "sku": "actions_windows", "grossAmount": 1.5],
            ["product": "Packages", "sku": "packages_storage", "grossAmount": 9.0],
            ["product": "Actions", "sku": "actions_storage", "grossAmount": 3.0]]])
        XCTAssertEqual(try GitHubActionsUsage.items(fromSummaryJSON: data), [Item(sku: "actions_windows", grossAmount: 1.5)])
        XCTAssertThrowsError(try GitHubActionsUsage.items(fromSummaryJSON: Data("{}".utf8)))
    }

    func testMonthWindowAndItems() {
        XCTAssertEqual(Provider.github.windows, [.month])
        XCTAssertTrue(ItemID.allCases.contains(ItemID(.github, .month)))
        XCTAssertFalse(ItemID.allCases.contains(ItemID(.github, .fiveHour)))
        XCTAssertNil(WindowKind.month.minutes) // never matched to a Codex duration
        let snap = ProviderSnapshot(windows: [.month: UsageWindow(usedPercent: 1, resetsAt: nil)], fetchedAt: Date())
        XCTAssertEqual(ItemVisibility.defaultItem(for: .github, snapshot: snap), ItemID(.github, .month))
        XCTAssertEqual(WindowDisplay.value(usedPercent: 25, resetsAt: nil).label(.month, mode: .remaining), "M75%")
    }
}

final class ClaudeWindowAfterResetTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testWindowDroppedAfterResetStaysOfferedAndShowsFull() {
        // Claude Code reports both windows, then drops five_hour once its reset passes.
        let first = SnapshotStore.merge([.fiveHour: UsageWindow(usedPercent: 40, resetsAt: t0 + 3600),
                                         .sevenDay: UsageWindow(usedPercent: 10, resetsAt: t0 + 500_000)], into: nil, at: t0)
        let afterReset = SnapshotStore.merge([.sevenDay: UsageWindow(usedPercent: 10, resetsAt: t0 + 500_000)],
                                             into: first, at: t0 + 3700)
        XCTAssertTrue(afterReset.offers(.fiveHour))
        XCTAssertEqual(ItemVisibility.visible(enabled: [ItemID(.claude, .fiveHour)], snapshots: [.claude: afterReset]),
                       [ItemID(.claude, .fiveHour)])
        let d = WindowDisplay.evaluate(afterReset, .fiveHour, now: t0 + 3700, fullAfterReset: true)
        XCTAssertEqual(d, .resetPassed(resetAt: t0 + 3600))
        XCTAssertEqual(d.label(.fiveHour, mode: .remaining), "H100%") // back to full until the next use
        // Still offered across further replies until the next use brings a new window.
        let later = SnapshotStore.merge([.sevenDay: UsageWindow(usedPercent: 11, resetsAt: t0 + 500_000)],
                                        into: afterReset, at: t0 + 7200)
        XCTAssertTrue(later.offers(.fiveHour))
        let nextUse = SnapshotStore.merge([.fiveHour: UsageWindow(usedPercent: 2, resetsAt: t0 + 7200 + 18_000),
                                           .sevenDay: UsageWindow(usedPercent: 12, resetsAt: t0 + 500_000)], into: later, at: t0 + 7300)
        XCTAssertEqual(WindowDisplay.evaluate(nextUse, .fiveHour, now: t0 + 7300, fullAfterReset: true).percent(mode: .remaining), 98)
    }

    func testWindowMissingBeforeResetIsNotOffered() {
        // Disappearing before its reset time (for example a plan change) means not offered.
        let first = SnapshotStore.merge([.fiveHour: UsageWindow(usedPercent: 40, resetsAt: t0 + 3600),
                                         .sevenDay: UsageWindow(usedPercent: 10, resetsAt: t0 + 500_000)], into: nil, at: t0)
        let gone = SnapshotStore.merge([.sevenDay: UsageWindow(usedPercent: 10, resetsAt: t0 + 500_000)], into: first, at: t0 + 60)
        XCTAssertFalse(gone.offers(.fiveHour))
    }
}

final class GitHubBudgetTests: XCTestCase {
    func testBudgetExtendsTheLimit() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let w = try GitHubActionsUsage.window(plan: "pro", total: [.init(sku: "actions_linux", grossAmount: 21.45)],
                                              publicRepos: [], now: now)
        XCTAssertEqual(w.usedPercent, 100)         // 21.45 of the 18 USD included
        XCTAssertEqual(w.usedAmount, 21.45)
        XCTAssertEqual(w.includedAmount, 18)
        let withBudget = GitHubActionsUsage.applyingBudget(w, budgetUSD: 10)
        XCTAssertEqual(withBudget.usedPercent, 21.45 / 28 * 100, accuracy: 0.001) // ~77% of 18 + 10
        XCTAssertEqual(WindowDisplay.value(usedPercent: withBudget.usedPercent, resetsAt: nil).label(.month, mode: .remaining), "M23%")
        XCTAssertEqual(GitHubActionsUsage.applyingBudget(w, budgetUSD: 1).usedPercent, 100) // capped
        XCTAssertEqual(GitHubActionsUsage.applyingBudget(w, budgetUSD: nil), w)
        XCTAssertEqual(GitHubActionsUsage.applyingBudget(w, budgetUSD: 0), w)
    }

    func testOlderSnapshotsWithoutAmountsAreUnchanged() throws {
        // Snapshots saved by 0.1.6 have no amounts; the budget cannot be applied to them.
        let old = UsageWindow(usedPercent: 40, resetsAt: nil)
        XCTAssertEqual(GitHubActionsUsage.applyingBudget(old, budgetUSD: 10), old)
        let json = #"{"usedPercent":40,"resetsAt":1800000000}"#
        let decoded = try JSONDecoder().decode(UsageWindow.self, from: Data(json.utf8))
        XCTAssertNil(decoded.usedAmount)
    }
}

final class DailyUsageTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Bangkok")!; return c }()
    func at(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    func testRecordsIncreasesPerLocalDay() {
        var log = DailyUsageLog()
        let reset = at("2026-11-21T03:00:00Z")
        log.record(UsageWindow(usedPercent: 40, resetsAt: reset), at: at("2026-11-17T02:00:00Z"), calendar: cal) // baseline
        log.record(UsageWindow(usedPercent: 45, resetsAt: reset), at: at("2026-11-17T05:00:00Z"), calendar: cal)
        log.record(UsageWindow(usedPercent: 52, resetsAt: reset), at: at("2026-11-17T16:30:00Z"), calendar: cal) // 23:30 local
        log.record(UsageWindow(usedPercent: 60, resetsAt: reset), at: at("2026-11-17T17:30:00Z"), calendar: cal) // 00:30 next day
        XCTAssertEqual(log.days["2026-11-17"], 12)
        XCTAssertEqual(log.days["2026-11-18"], 8)
        XCTAssertEqual(log.since, "2026-11-17")
    }

    func testNewWindowCountsItsWholeValue() {
        var log = DailyUsageLog()
        log.record(UsageWindow(usedPercent: 90, resetsAt: at("2026-11-21T03:00:00Z")), at: at("2026-11-20T01:00:00Z"), calendar: cal)
        log.record(UsageWindow(usedPercent: 3, resetsAt: at("2026-11-28T05:00:00Z")), at: at("2026-11-21T06:00:00Z"), calendar: cal)
        XCTAssertEqual(log.days["2026-11-21"], 3)
    }

    func testDecreaseOrSameValueAddsNothing() {
        var log = DailyUsageLog()
        let reset = at("2026-11-21T03:00:00Z")
        log.record(UsageWindow(usedPercent: 50, resetsAt: reset), at: at("2026-11-18T01:00:00Z"), calendar: cal)
        log.record(UsageWindow(usedPercent: 50, resetsAt: reset.addingTimeInterval(30)), at: at("2026-11-18T02:00:00Z"), calendar: cal)
        log.record(UsageWindow(usedPercent: 48, resetsAt: reset), at: at("2026-11-18T03:00:00Z"), calendar: cal)
        XCTAssertNil(log.days["2026-11-18"])
    }

    func testDaysBeforeRecordingAreNoDataNotZero() {
        var log = DailyUsageLog()
        let reset = at("2026-11-21T03:00:00Z")
        log.record(UsageWindow(usedPercent: 10, resetsAt: reset), at: at("2026-11-16T03:00:00Z"), calendar: cal)
        log.record(UsageWindow(usedPercent: 15, resetsAt: reset), at: at("2026-11-18T03:00:00Z"), calendar: cal)
        let v = log.values(endingAt: at("2026-11-18T10:00:00Z"), count: 7, calendar: cal)
        XCTAssertEqual(v.count, 7)
        XCTAssertNil(v[0].percent)            // 11-12: before recording
        XCTAssertEqual(v[4].percent, 0)       // 11-16: recording started, nothing used
        XCTAssertEqual(v[5].percent, 0)       // 11-17
        XCTAssertEqual(v[6].percent, 5)       // 11-18
        XCTAssertEqual(log.firstDay, "2026-11-16")
    }

    func testBarLabelsShowPercent() {
        XCTAssertEqual(DailyUsageLog.barLabel(0), "")
        XCTAssertEqual(DailyUsageLog.barLabel(0.3), "<1%")
        XCTAssertEqual(DailyUsageLog.barLabel(0.99), "<1%")
        XCTAssertEqual(DailyUsageLog.barLabel(1), "1%")
        XCTAssertEqual(DailyUsageLog.barLabel(17.6), "18%")
        XCTAssertEqual(DailyUsageLog.barLabel(100), "100%")
    }

    func testOldDaysArePruned() {
        var log = DailyUsageLog(days: ["2026-01-01": 4], last: UsageWindow(usedPercent: 1, resetsAt: at("2026-11-21T03:00:00Z")), since: "2026-01-01")
        log.record(UsageWindow(usedPercent: 2, resetsAt: at("2026-11-21T03:00:00Z")), at: at("2026-11-18T03:00:00Z"), calendar: cal)
        XCTAssertNil(log.days["2026-01-01"])
        XCTAssertEqual(log.days["2026-11-18"], 1)
    }
}

final class GitHubDailyCacheTests: XCTestCase {
    func at(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    func testPercentOfMonthlyAllowance() {
        var c = GitHubDailyCache()
        c.includedAmount = 18
        c.amounts = ["2026-11-17": 1.8, "2026-11-18": 0]
        XCTAssertEqual(c.percent("2026-11-17", budgetUSD: nil)!, 10, accuracy: 0.001)
        XCTAssertEqual(c.percent("2026-11-17", budgetUSD: 18)!, 5, accuracy: 0.001)
        XCTAssertEqual(c.percent("2026-11-18", budgetUSD: nil), 0)
        XCTAssertNil(c.percent("2026-11-16", budgetUSD: nil)) // not read yet: no data, not zero
    }

    func testOnlyMissingOrRecentDaysAreRead() {
        var c = GitHubDailyCache()
        let now = at("2026-11-19T05:00:00Z")
        c.fetchedAt = ["2026-11-10": at("2026-11-12T00:00:00Z"),
                       "2026-11-18": now.addingTimeInterval(-7200),
                       "2026-11-19": now.addingTimeInterval(-600)]
        XCTAssertEqual(c.needsRead(["2026-11-10", "2026-11-11", "2026-11-18", "2026-11-19", "2026-11-20"], now: now),
                       ["2026-11-11", "2026-11-18"]) // past day cached, recent day older than 1 h, future skipped
        XCTAssertEqual(GitHubDailyCache.utcKey(at("2026-11-18T23:30:00Z")), "2026-11-18")
    }
}

final class JSONNumberTests: XCTestCase {
    /// Regression: values of exactly 0 and 1 from real JSON were read as booleans and dropped.
    func testZeroAndOnePercentFromRealJSONAreRead() throws {
        let claude = #"{"rate_limits":{"five_hour":{"used_percentage":0,"resets_at":1900000000},"seven_day":{"used_percentage":1,"resets_at":1900500000}}}"#
        let w = try ClaudeStatusLineParser.parseWindows(Data(claude.utf8))
        XCTAssertEqual(w[.fiveHour]?.usedPercent, 0)
        XCTAssertEqual(w[.sevenDay]?.usedPercent, 1)

        let codex = #"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":0,"windowDurationMins":300,"resetsAt":1900000000},"secondary":{"usedPercent":1,"windowDurationMins":10080,"resetsAt":1900500000}}}"#
        let result = try JSONSerialization.jsonObject(with: Data(codex.utf8)) as! [String: Any]
        let snap = try CodexRateLimitParser.parse(result: result, fetchedAt: Date())
        XCTAssertEqual(snap[.fiveHour]?.usedPercent, 0)
        XCTAssertEqual(snap[.sevenDay]?.usedPercent, 1)
        XCTAssertTrue(snap.offers(.fiveHour))
    }

    func testRealBooleansAreStillRejected() throws {
        let json = #"{"rate_limits":{"five_hour":{"used_percentage":true,"resets_at":1900000000}}}"#
        XCTAssertTrue(try ClaudeStatusLineParser.parseWindows(Data(json.utf8)).isEmpty)
    }
}

final class ResetCreditsTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let weekly: [String: Any] = ["limitId": "codex", "primary": ["usedPercent": 10, "windowDurationMins": 10080, "resetsAt": 1_800_500_000]]

    func testParsesCountAndEarliestAvailableExpiry() throws {
        let result: [String: Any] = ["rateLimits": weekly, "rateLimitResetCredits": [
            "availableCount": 2,
            "credits": [
                ["id": "a", "resetType": "codexRateLimits", "status": "available", "grantedAt": 1, "expiresAt": 1_802_000_000],
                ["id": "b", "resetType": "codexRateLimits", "status": "available", "grantedAt": 1, "expiresAt": 1_801_000_000],
                ["id": "c", "resetType": "codexRateLimits", "status": "redeemed", "grantedAt": 1, "expiresAt": 1_800_100_000],
            ]]]
        let snap = try CodexRateLimitParser.parse(result: result, fetchedAt: now)
        XCTAssertEqual(snap.resetCredits, ResetCredits(available: 2, earliestExpiry: Date(timeIntervalSince1970: 1_801_000_000)))
    }

    func testCountOnlyAndMissing() throws {
        let countOnly: [String: Any] = ["rateLimits": weekly, "rateLimitResetCredits": ["availableCount": 0, "credits": NSNull()]]
        XCTAssertEqual(try CodexRateLimitParser.parse(result: countOnly, fetchedAt: now).resetCredits, ResetCredits(available: 0, earliestExpiry: nil))
        XCTAssertNil(try CodexRateLimitParser.parse(result: ["rateLimits": weekly], fetchedAt: now).resetCredits)
    }

    func testArrivalDetection() {
        XCTAssertNil(ResetCredits.arrived(previous: nil, current: 3))   // first value: baseline only
        XCTAssertNil(ResetCredits.arrived(previous: 2, current: 2))
        XCTAssertNil(ResetCredits.arrived(previous: 2, current: 1))     // used one
        XCTAssertEqual(ResetCredits.arrived(previous: 1, current: 2), 1)
        XCTAssertEqual(ResetCredits.arrived(previous: 0, current: 3), 3)
    }

    func testCountOnlyReadKeepsKnownExpiry() {
        let detailed = ResetCredits(available: 2, earliestExpiry: now)
        XCTAssertEqual(ResetCredits(available: 2, earliestExpiry: nil).keepingExpiry(from: detailed), detailed)
        XCTAssertNil(ResetCredits(available: 1, earliestExpiry: nil).keepingExpiry(from: detailed).earliestExpiry) // count changed
    }
}

final class GitHubBudgetRowTests: XCTestCase {
    func testChargedAmountIsGitHubsNetAmount() {
        // Real November shape: Linux over the free usage, macOS and storage free.
        let data = try! JSONSerialization.data(withJSONObject: ["usageItems": [
            ["product": "Actions", "sku": "actions_linux", "grossAmount": 56.262, "netAmount": 3.294],
            ["product": "Actions", "sku": "actions_macos", "grossAmount": 56.234, "netAmount": 0],
            ["product": "Actions", "sku": "actions_storage", "grossAmount": 0.004, "netAmount": 0],
            ["product": "Packages", "sku": "packages_storage", "grossAmount": 1, "netAmount": 1]]])
        XCTAssertEqual(GitHubActionsUsage.chargedAmount(fromSummaryJSON: data)!, 3.294, accuracy: 0.0001)
    }

    func testBudgetPercent() {
        var w = UsageWindow(usedPercent: 100, resetsAt: nil, usedAmount: 21.45, includedAmount: 18)
        w.chargedAmount = 3.294
        XCTAssertEqual(GitHubActionsUsage.budgetPercent(w, budgetUSD: 20)!, 16.47, accuracy: 0.01)
        XCTAssertEqual(GitHubActionsUsage.budgetPercent(w, budgetUSD: 2), 100) // capped
        XCTAssertNil(GitHubActionsUsage.budgetPercent(w, budgetUSD: nil))
        w.chargedAmount = nil
        XCTAssertNil(GitHubActionsUsage.budgetPercent(w, budgetUSD: 20)) // older snapshot: re-read first
    }
}

final class BudgetBarSplitTests: XCTestCase {
    let w = UsageWindow(usedPercent: 100, resetsAt: nil, usedAmount: 21.45, includedAmount: 18)

    func testUsedAndRemainingSplit() {
        // 18 free + 10 budget = 28. Used 21.45: all 18 free, 3.45 of the budget.
        let used = BudgetBarSplit.parts(w, budgetUSD: 10, mode: .used)!
        XCTAssertEqual(used.free, 18 / 28, accuracy: 0.0001)
        XCTAssertEqual(used.budget, 3.45 / 28, accuracy: 0.0001)
        let left = BudgetBarSplit.parts(w, budgetUSD: 10, mode: .remaining)!
        XCTAssertEqual(left.free, 0, accuracy: 0.0001)
        XCTAssertEqual(left.budget, 6.55 / 28, accuracy: 0.0001)
        XCTAssertEqual(used.free + used.budget + left.free + left.budget, 1, accuracy: 0.0001)
    }

    func testWithinFreeUsageAndEdges() {
        let early = UsageWindow(usedPercent: 25, resetsAt: nil, usedAmount: 7, includedAmount: 18)
        let used = BudgetBarSplit.parts(early, budgetUSD: 10, mode: .used)!
        XCTAssertEqual(used.free, 0.25, accuracy: 0.0001)
        XCTAssertEqual(used.budget, 0)
        let over = UsageWindow(usedPercent: 100, resetsAt: nil, usedAmount: 40, includedAmount: 18)
        XCTAssertEqual(BudgetBarSplit.parts(over, budgetUSD: 10, mode: .used)!.budget, 10 / 28, accuracy: 0.0001) // capped
        XCTAssertNil(BudgetBarSplit.parts(w, budgetUSD: nil, mode: .used))
        XCTAssertNil(BudgetBarSplit.parts(UsageWindow(usedPercent: 1, resetsAt: nil), budgetUSD: 10, mode: .used))
    }
}

final class ProviderStatusTests: XCTestCase {
    func testFailureKeepsValuesAndMarksThemStale() {
        var s = ProviderStatus()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let snap = ProviderSnapshot(windows: [.sevenDay: UsageWindow(usedPercent: 40, resetsAt: nil)], fetchedAt: t0)
        s.begin(at: t0)
        XCTAssertTrue(s.isFetching)
        XCTAssertEqual(s.lastAttempt, t0)
        s.succeed(snap)
        XCTAssertFalse(s.isFetching)
        XCTAssertFalse(s.isStale)
        s.fail(.timedOut)
        s.fail(.failed("x"))
        XCTAssertEqual(s.snapshot, snap)
        XCTAssertTrue(s.isStale)
        XCTAssertEqual(s.consecutiveFailures, 2)
        s.succeed(snap)
        XCTAssertEqual(s.consecutiveFailures, 0)
        XCTAssertNil(s.lastError)
        // An error without values is not "stale": there is nothing old to show.
        XCTAssertFalse(ProviderStatus(lastError: .notSignedIn).isStale)
    }

    func testGitHubFetchPolicy() {
        let p = GitHubFetchPolicy()
        let t0 = Date(timeIntervalSince1970: 100_000)
        XCTAssertTrue(p.shouldFetch(force: false, now: t0, lastAttempt: nil))
        XCTAssertFalse(p.shouldFetch(force: false, now: t0, lastAttempt: t0 - 3599))
        XCTAssertTrue(p.shouldFetch(force: false, now: t0, lastAttempt: t0 - 3600))
        XCTAssertTrue(p.shouldFetch(force: true, now: t0, lastAttempt: t0 - 1))
        XCTAssertFalse(p.shouldFetchOnPanelOpen(now: t0, lastAttempt: t0 - 600))
        XCTAssertTrue(p.shouldFetchOnPanelOpen(now: t0, lastAttempt: t0 - 601))
        XCTAssertTrue(p.shouldFetchOnPanelOpen(now: t0, lastAttempt: nil))
        XCTAssertEqual(p.nextDelay(consecutiveFailures: 0), 3600)
        XCTAssertEqual(p.nextDelay(consecutiveFailures: 2), 7200)
        XCTAssertEqual(p.nextDelay(consecutiveFailures: 9), 14_400) // at most 4×
    }

    func testResetCreditTracker() throws {
        let suite = "tsai-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let t = ResetCreditTracker(defaults: defaults)
        XCTAssertNil(t.observe(nil))
        XCTAssertNil(t.observe(ResetCredits(available: 1, earliestExpiry: nil))) // first value: baseline
        XCTAssertEqual(t.observe(ResetCredits(available: 3, earliestExpiry: nil)), 2)
        XCTAssertNil(t.observe(ResetCredits(available: 3, earliestExpiry: nil)))
        XCTAssertNil(t.observe(ResetCredits(available: 0, earliestExpiry: nil))) // used up
        // Kept across launches: a new tracker on the same defaults remembers the count.
        XCTAssertEqual(ResetCreditTracker(defaults: defaults).observe(ResetCredits(available: 1, earliestExpiry: nil)), 1)
    }

    func testGitHubDailyCacheApplyAndStore() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let paths = AppPaths(supportDirectory: dir)
        let now = ISO8601DateFormatter().date(from: "2026-11-19T12:00:00Z")!
        var cache = GitHubDailyCache()
        cache.amounts["2020-01-01"] = 1 // older than two years: pruned
        cache.apply(amounts: ["2026-11-18": 0.5, "2026-11-19": 0.25], included: 18, now: now)
        XCTAssertEqual(cache.includedAmount, 18)
        XCTAssertEqual(cache.amounts, ["2026-11-18": 0.5, "2026-11-19": 0.25])
        XCTAssertEqual(cache.fetchedAt["2026-11-19"], now)
        try GitHubDailyStore.save(cache, paths: paths)
        XCTAssertEqual(GitHubDailyStore.load(paths: paths), cache)
        GitHubDailyStore.remove(paths: paths)
        XCTAssertEqual(GitHubDailyStore.load(paths: paths), GitHubDailyCache())
    }
}

final class ScreenshotFileTests: XCTestCase {
    let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)

    func testFolderFollowsTheMacScreenshotSetting() {
        let all: (URL) -> Bool = { _ in true }
        XCTAssertEqual(ScreenshotFile.folder(location: "~/Downloads", home: home, isDirectory: all).path, "/Users/me/Downloads")
        XCTAssertEqual(ScreenshotFile.folder(location: "/Volumes/Shots", home: home, isDirectory: all).path, "/Volumes/Shots")
        XCTAssertEqual(ScreenshotFile.folder(location: "~", home: home, isDirectory: all).path, "/Users/me")
    }

    func testFolderFallsBackToDesktop() {
        XCTAssertEqual(ScreenshotFile.folder(location: nil, home: home, isDirectory: { _ in true }).path, "/Users/me/Desktop")
        XCTAssertEqual(ScreenshotFile.folder(location: "  ", home: home, isDirectory: { _ in true }).path, "/Users/me/Desktop")
        XCTAssertEqual(ScreenshotFile.folder(location: "relative/dir", home: home, isDirectory: { _ in true }).path, "/Users/me/Desktop")
        // A folder that was removed or a file.
        XCTAssertEqual(ScreenshotFile.folder(location: "~/Gone", home: home, isDirectory: { _ in false }).path, "/Users/me/Desktop")
    }

    func testNameLooksLikeAMacScreenshotAndNeverOverwrites() {
        let date = Date(timeIntervalSince1970: 1_795_213_791) // 2026-11-21 05:29:51 in UTC+7
        let tz = TimeZone(secondsFromGMT: 7 * 3600)!
        XCTAssertEqual(ScreenshotFile.name(service: "Claude Code", date: date, timeZone: tz) { _ in false },
                       "TSAI UsageBar Claude Code 2026-11-21 5.29.51.png")
        let taken: Set = ["TSAI UsageBar Codex 2026-11-21 5.29.51.png", "TSAI UsageBar Codex 2026-11-21 5.29.51 (2).png"]
        XCTAssertEqual(ScreenshotFile.name(service: "Codex", date: date, timeZone: tz) { taken.contains($0) },
                       "TSAI UsageBar Codex 2026-11-21 5.29.51 (3).png")
    }
}

final class PlanNameTests: XCTestCase {
    func testKnownPlansUseTheServicesOwnNames() {
        XCTAssertEqual(PlanName.display(.claude, "pro"), "Pro")
        XCTAssertEqual(PlanName.display(.claude, "max"), "Max")
        XCTAssertEqual(PlanName.display(.codex, "prolite"), "Pro 100")
        XCTAssertEqual(PlanName.display(.codex, "pro"), "Pro 200")
        XCTAssertEqual(PlanName.display(.codex, "promax"), "Pro 500")
        XCTAssertEqual(PlanName.display(.codex, "plus"), "Plus")
        XCTAssertEqual(PlanName.display(.github, "free"), "Free")
    }

    func testUnknownPlansAreShownAsReceivedAndMissingOnesHidden() {
        XCTAssertEqual(PlanName.display(.codex, "pro500"), "pro500")
        XCTAssertNil(PlanName.display(.codex, nil))
        XCTAssertNil(PlanName.display(.codex, " "))
        XCTAssertNil(PlanName.display(.codex, "unknown"))
    }

    func testCodexPlanIsReadFromTheRateLimitReply() throws {
        let bucket: [String: Any] = ["limitId": "codex", "planType": "prolite",
                                     "primary": ["usedPercent": 93, "windowDurationMins": 10080, "resetsAt": 1_795_768_269]]
        let byID = try CodexRateLimitParser.parse(result: ["rateLimitsByLimitId": ["codex": bucket]], fetchedAt: Date())
        XCTAssertEqual(byID.plan, "prolite")
        let single = try CodexRateLimitParser.parse(result: ["rateLimits": bucket], fetchedAt: Date())
        XCTAssertEqual(single.plan, "prolite")
    }
}
