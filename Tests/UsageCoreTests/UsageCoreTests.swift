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

    func testResetPassedWithoutNewDataWaitsInsteadOfShowing100() {
        let s = snap(90, reset: t0 + 60, fetched: t0)
        let d = WindowDisplay.evaluate(s, .fiveHour, now: t0 + 61)
        XCTAssertEqual(d, .awaitingUpdateAfterReset(resetAt: t0 + 60))
        XCTAssertEqual(d.label(.fiveHour, mode: .remaining), "H—")
    }

    func testNewDataAfterResetIsShown() {
        let s = snap(3, reset: t0 + 18_000, fetched: t0 + 70)
        XCTAssertEqual(WindowDisplay.evaluate(s, .fiveHour, now: t0 + 80).percent(mode: .remaining), 97)
    }

    func testCachedPreResetCopyDoesNotReplaceValues() {
        // An idle Claude Code session can re-send its cached, already-reset values.
        let first = SnapshotStore.merge([.fiveHour: UsageWindow(usedPercent: 80, resetsAt: t0 + 60)], into: nil, at: t0)
        let resent = SnapshotStore.merge([.fiveHour: UsageWindow(usedPercent: 80, resetsAt: t0 + 60)], into: first, at: t0 + 120)
        XCTAssertEqual(WindowDisplay.evaluate(resent, .fiveHour, now: t0 + 120), .awaitingUpdateAfterReset(resetAt: t0 + 60))
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
        let both: Set<Provider> = [.claude, .codex]
        XCTAssertEqual(ItemVisibility.activeProviders(enabled: [ItemID(.claude, .fiveHour)], initialized: both), [.claude])
        XCTAssertEqual(ItemVisibility.activeProviders(enabled: [ItemID(.codex, .sevenDay), ItemID(.claude, .sevenDay)],
                                                      initialized: both), both)
        // Not reported yet: keep active so available windows can be learned.
        XCTAssertEqual(ItemVisibility.activeProviders(enabled: [ItemID(.claude, .fiveHour)], initialized: [.claude]), both)
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

final class LocalizationTests: XCTestCase {
    func testAutomaticLanguage() {
        XCTAssertEqual(AppLanguage.resolve(.automatic, preferred: ["ja-JP", "en-US"]), .ja)
        XCTAssertEqual(AppLanguage.resolve(.automatic, preferred: ["en-GB"]), .en)
        XCTAssertEqual(AppLanguage.resolve(.automatic, preferred: ["th-TH", "ja-JP"]), .en)
        XCTAssertEqual(AppLanguage.resolve(.automatic, preferred: []), .en)
        XCTAssertEqual(AppLanguage.resolve(.japanese, preferred: ["en"]), .ja)
        XCTAssertEqual(AppLanguage.resolve(.english, preferred: ["ja"]), .en)
    }

    func testLocalTimeFormatting() {
        let tz = TimeZone(identifier: "Asia/Tokyo")!
        let now = ISO8601DateFormatter().date(from: "2026-11-17T07:00:00Z")! // 16:00 JST
        let sameDay = ISO8601DateFormatter().date(from: "2026-11-17T09:40:00Z")! // 18:40 JST
        let later = ISO8601DateFormatter().date(from: "2026-11-23T00:00:00Z")! // 11/23 09:00 JST
        XCTAssertEqual(TimeText(.ja, timeZone: tz).reset(sameDay, now: now), "18:40")
        XCTAssertEqual(TimeText(.ja, timeZone: tz).reset(later, now: now), "11月23日 9:00")
        XCTAssertEqual(TimeText(.ja).duration(2 * 3600 + 15 * 60), "2時間15分")
        XCTAssertEqual(TimeText(.en).duration(2 * 3600 + 15 * 60), "2h 15m")
        // 7-day windows show days and hours.
        let fiveDays: TimeInterval = 444_000 // 5 days, 3 hours, 20 minutes
        XCTAssertEqual(TimeText(.ja).duration(fiveDays), "5日3時間")
        XCTAssertEqual(TimeText(.en).duration(fiveDays), "5d 3h")
        XCTAssertEqual(TimeText(.ja).duration(TimeInterval(6 * 86_400)), "6日")
        XCTAssertEqual(Strings(.ja).resetLine("11月23日 9:00", remaining: "5日3時間"), "リセット：11月23日 9:00（あと5日3時間）")
        XCTAssertEqual(Strings(.ja).resetLine("18:40", remaining: "2時間15分"), "リセット：18:40（あと2時間15分）")
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
