import Foundation

public enum LanguageSetting: String, Codable, CaseIterable, Sendable {
    case automatic
    case japanese
    case english
}

public enum AppLanguage: String, Sendable {
    case ja
    case en

    /// Japanese when the first preferred macOS language is Japanese, otherwise English.
    public static func resolve(_ setting: LanguageSetting, preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        switch setting {
        case .japanese: return .ja
        case .english: return .en
        case .automatic:
            guard let first = preferred.first?.lowercased() else { return .en }
            return first.hasPrefix("ja") ? .ja : .en
        }
    }

    public var locale: Locale { Locale(identifier: self == .ja ? "ja_JP" : "en_US") }
}

/// All user-facing text. Kept in code so language changes apply without a restart.
public struct Strings: Sendable {
    public let lang: AppLanguage
    public init(_ lang: AppLanguage) { self.lang = lang }

    private func t(_ ja: String, _ en: String) -> String { lang == .ja ? ja : en }

    public func windowTitle(_ kind: WindowKind) -> String {
        switch kind {
        case .fiveHour: return t("5時間", "5 hours")
        case .sevenDay: return t("7日間", "7 days")
        }
    }

    public func modeCaption(_ mode: DisplayMode) -> String {
        mode == .remaining ? t("残量", "Remaining") : t("使用率", "Used")
    }

    public var unavailable: String { t("データなし", "No data") }
    public var awaitingAfterReset: String { t("リセット済み・更新待ち", "Reset passed · waiting for update") }
    public var notOffered: String { t("このプランでは提供されていません", "Not offered on this plan") }
    public var refresh: String { t("更新", "Refresh") }
    public var refreshing: String { t("更新中…", "Refreshing…") }
    public var settings: String { t("設定", "Settings") }
    public var quit: String { t("終了", "Quit") }
    public var never: String { t("未取得", "Never") }

    public func lastUpdated(_ text: String) -> String { t("最終更新：\(text)", "Updated \(text)") }
    public func resetLine(_ time: String, remaining: String?) -> String {
        guard let remaining else { return t("リセット：\(time)", "Resets \(time)") }
        return t("リセット：\(time)（あと\(remaining)）", "Resets \(time) (in \(remaining))")
    }

    // Errors
    public var codexNotFound: String { t("Codexが見つかりません", "Codex not found") }
    public var codexNotSignedIn: String { t("Codexにサインインしていません", "Not signed in to Codex") }
    public var fetchTimedOut: String { t("応答がありません", "No response") }
    public var fetchFailed: String { t("更新できませんでした", "Couldn't update") }
    public var showingLastValues: String { t("前回の値を表示中", "Showing last values") }
    public var signInCodex: String { t("ブラウザでCodexにサインイン", "Sign in to Codex in browser") }
    public var claudeNotSignedIn: String { t("Claude Codeにログインしていません", "Not signed in to Claude Code") }
    public var signInClaude: String { t("ブラウザでClaude Codeにログイン", "Sign in to Claude Code in browser") }
    public var claudeNotInstalled: String { t("Claude Codeが見つかりません", "Claude Code not found") }
    public var claudeNotLinked: String { t("Claude Codeと未連携", "Not connected to Claude Code") }
    public var claudeWaiting: String {
        t("Claude Codeの次の応答で表示されます", "Shown after Claude Code's next response")
    }

    // Settings
    public var menuBarItems: String { t("メニューバー表示", "Menu bar items") }
    public var reorderHint: String { t("⌘を押しながらドラッグで並べ替え", "Hold ⌘ and drag to reorder") }
    public var keepOneHint: String { t("最低1つは表示されます", "At least one item stays visible") }
    public var numbers: String { t("数値", "Numbers") }
    public var language: String { t("言語", "Language") }
    public var automatic: String { t("自動", "Automatic") }
    public var launchAtLogin: String { t("ログイン時に起動", "Launch at login") }
    public var connections: String { t("接続", "Connections") }
    public var connected: String { t("接続済み", "Connected") }
    public var notConnected: String { t("未接続", "Not connected") }
    // Updates
    public func updateAvailable(_ v: String) -> String { t("新しいバージョン v\(v) があります", "Version \(v) is available") }
    public var updateNow: String { t("アップデート", "Update") }
    public var updating: String { t("アップデート中…", "Updating…") }
    public var updateFailed: String { t("アップデートできませんでした", "Update failed") }
    public var upToDate: String { t("最新です", "Up to date") }
    public var checkForUpdates: String { t("確認", "Check") }
    public var version: String { t("バージョン", "Version") }
    public var pausedHidden: String { t("表示OFFのため停止中", "Paused (hidden)") }
    public var connect: String { t("連携する", "Connect") }
    public var disconnect: String { t("連携を解除", "Disconnect") }
    public var replacedByUser: String {
        t("statusLineが別の設定に変更されています", "statusLine was changed to another command")
    }
    public var launchAtLoginNeedsApproval: String {
        t("システム設定 > 一般 > ログイン項目で許可してください", "Allow it in System Settings > General > Login Items")
    }

    public func itemName(_ id: ItemID) -> String {
        "\(id.provider.displayName) \(id.window.letter) (\(windowTitle(id.window)))"
    }

    // Claude link confirmation
    public var linkTitle: String { t("Claude Codeと連携しますか？", "Connect to Claude Code?") }
    public func linkMessage(existing: String?, settingsPath: String) -> String {
        let keep = existing.map {
            t("現在のstatusLine（\($0)）はそのまま表示されます。", "Your current statusLine (\($0)) keeps showing as before.")
        } ?? ""
        return t("""
        利用枠を受け取るため、\(settingsPath) の statusLine をTSAI UsageBarの中継コマンドに変更します。\(keep)
        変更前の設定はバックアップし、連携解除やアンインストールで元に戻します。
        """, """
        To receive usage limits, TSAI UsageBar changes statusLine in \(settingsPath) to its relay command. \(keep)
        The previous setting is backed up and restored when you disconnect or uninstall.
        """)
    }
    public var cancel: String { t("キャンセル", "Cancel") }
    public var linkFailed: String { t("連携できませんでした", "Couldn't connect") }
    public var settingsUnreadable: String {
        t("Claude Codeの設定ファイルを読み取れません。変更していません。", "Couldn't read Claude Code settings. Nothing was changed.")
    }
}

/// Formats reset times in the Mac's local time zone.
public struct TimeText: Sendable {
    public let lang: AppLanguage
    public var timeZone: TimeZone

    public init(_ lang: AppLanguage, timeZone: TimeZone = .current) {
        self.lang = lang
        self.timeZone = timeZone
    }

    /// Same day: time only. Otherwise date and time.
    public func reset(_ date: Date, now: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let f = DateFormatter()
        f.locale = lang.locale
        f.timeZone = timeZone
        if cal.isDate(date, inSameDayAs: now) {
            f.dateFormat = "H:mm"
        } else {
            f.setLocalizedDateFormatFromTemplate(lang == .ja ? "MMMdHmm" : "MMMdjmm")
        }
        return f.string(from: date)
    }

    /// e.g. `2時間15分` / `2h 15m`.
    public func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int((interval / 60).rounded(.up)))
        let d = total / 1440, h = (total % 1440) / 60, m = total % 60
        if lang == .ja {
            if d > 0 { return h > 0 ? "\(d)日\(h)時間" : "\(d)日" }
            if h > 0 { return m > 0 ? "\(h)時間\(m)分" : "\(h)時間" }
            return "\(m)分"
        }
        if d > 0 { return h > 0 ? "\(d)d \(h)h" : "\(d)d" }
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }

    public func clock(_ date: Date, now: Date) -> String { reset(date, now: now) }
}
