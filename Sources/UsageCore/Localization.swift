import Foundation

/// Language choice in Settings: automatic, or one of the supported languages.
/// The supported set matches the TripSurf website: en, ja, zh-hant, zh-hans, ko, fr, de, th.
public enum LanguageSetting: Hashable, Codable, Sendable {
    case automatic
    case fixed(AppLanguage)

    public static var allCases: [LanguageSetting] { [.automatic] + AppLanguage.allCases.map { .fixed($0) } }

    /// Stored form: "automatic" or a language code. Accepts the 0.1.x values "japanese"/"english".
    public init?(storedValue: String) {
        switch storedValue {
        case "automatic": self = .automatic
        case "japanese": self = .fixed(.ja)
        case "english": self = .fixed(.en)
        default:
            guard let lang = AppLanguage(rawValue: storedValue) else { return nil }
            self = .fixed(lang)
        }
    }

    public var storedValue: String {
        switch self {
        case .automatic: return "automatic"
        case .fixed(let l): return l.rawValue
        }
    }
}

public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case en
    case ja
    case zhHant = "zh-hant"
    case zhHans = "zh-hans"
    case ko
    case fr
    case de
    case th

    /// Name shown in the language picker, in the language itself.
    public var nativeName: String {
        switch self {
        case .en: return "English"
        case .ja: return "日本語"
        case .zhHant: return "繁體中文"
        case .zhHans: return "简体中文"
        case .ko: return "한국어"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .th: return "ไทย"
        }
    }

    public var locale: Locale {
        switch self {
        case .en: return Locale(identifier: "en_US")
        case .ja: return Locale(identifier: "ja_JP")
        case .zhHant: return Locale(identifier: "zh_Hant_TW")
        case .zhHans: return Locale(identifier: "zh_Hans_CN")
        case .ko: return Locale(identifier: "ko_KR")
        case .fr: return Locale(identifier: "fr_FR")
        case .de: return Locale(identifier: "de_DE")
        case .th: return Locale(identifier: "th_TH")
        }
    }

    /// The first supported macOS preferred language wins; otherwise English.
    /// Chinese uses an explicit Hant/Hans script when present; otherwise TW/HK/MO
    /// select Traditional and other regions select Simplified.
    public static func resolve(_ setting: LanguageSetting, preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        if case .fixed(let l) = setting { return l }
        for tag in preferred {
            if let l = match(tag) { return l }
        }
        return .en
    }

    static func match(_ tag: String) -> AppLanguage? {
        let parts = tag.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        guard let base = parts.first else { return nil }
        if base == "zh" {
            if parts.contains("hant") { return .zhHant }
            if parts.contains("hans") { return .zhHans }
            return parts.contains(where: { ["tw", "hk", "mo"].contains($0) }) ? .zhHant : .zhHans
        }
        return AppLanguage.allCases.first { $0.rawValue == base }
    }
}

/// All user-facing text. Kept in code so language changes apply without a restart.
/// `L` requires every language, so a missing translation does not compile.
public struct Strings: Sendable {
    public let lang: AppLanguage
    public init(_ lang: AppLanguage) { self.lang = lang }

    // swiftlint:disable:next function_parameter_count
    private func L(_ en: String, _ ja: String, _ zhHant: String, _ zhHans: String,
                   _ ko: String, _ fr: String, _ de: String, _ th: String) -> String {
        switch lang {
        case .en: return en
        case .ja: return ja
        case .zhHant: return zhHant
        case .zhHans: return zhHans
        case .ko: return ko
        case .fr: return fr
        case .de: return de
        case .th: return th
        }
    }

    /// Replaces %1, %2… in a translated template.
    private func fill(_ template: String, _ args: String...) -> String {
        var s = template
        for (i, a) in args.enumerated() { s = s.replacingOccurrences(of: "%\(i + 1)", with: a) }
        return s
    }

    public func windowTitle(_ kind: WindowKind) -> String {
        switch kind {
        case .fiveHour: return L("5 hours", "5時間", "5小時", "5小时", "5시간", "5 heures", "5 Stunden", "5 ชั่วโมง")
        case .sevenDay: return L("7 days", "7日間", "7天", "7天", "7일", "7 jours", "7 Tage", "7 วัน")
        case .month: return L("This month", "今月", "本月", "本月", "이번 달", "Ce mois-ci", "Diesen Monat", "เดือนนี้")
        }
    }

    public func modeCaption(_ mode: DisplayMode) -> String {
        mode == .remaining
            ? L("Remaining", "残量", "剩餘", "剩余", "남은 양", "Restant", "Verbleibend", "คงเหลือ")
            : L("Used", "使用率", "已使用", "已使用", "사용량", "Utilisé", "Verbraucht", "ใช้ไป")
    }

    public var unavailable: String { L("No data", "データなし", "無資料", "无数据", "데이터 없음", "Aucune donnée", "Keine Daten", "ไม่มีข้อมูล") }
    public var awaitingAfterReset: String {
        L("Reset passed · waiting for update", "リセット済み・更新待ち", "已重置・等待更新", "已重置・等待更新",
          "초기화됨 · 업데이트 대기 중", "Réinitialisé · en attente de mise à jour", "Zurückgesetzt · warte auf Aktualisierung", "รีเซ็ตแล้ว · กำลังรอข้อมูลใหม่")
    }
    public var resetNewWindowOnNextUse: String {
        L("Reset · a new window starts on next use", "リセット済み・次の利用で新しい枠が始まります",
          "已重置・下次使用時開始新的額度", "已重置・下次使用时开始新的额度",
          "초기화됨 · 다음 사용 시 새 기간 시작", "Réinitialisé · une nouvelle période démarre à la prochaine utilisation",
          "Zurückgesetzt · neues Zeitfenster beginnt bei nächster Nutzung", "รีเซ็ตแล้ว · ช่วงใหม่จะเริ่มเมื่อใช้งานครั้งถัดไป")
    }
    /// Chart titles say what the percentages are of, so bar labels like "12%" are clear.
    public var dailyWeeklyTitle: String {
        L("Daily (% of week)", "日別（週間枠の％）", "每日（每週額度％）", "每日（每周额度％）",
          "일별 (주간 한도 %)", "Par jour (% semaine)", "Täglich (% Woche)", "รายวัน (% ของสัปดาห์)")
    }
    public var dailyMonthlyTitle: String {
        L("Daily (% of month)", "日別（月間枠の％）", "每日（每月額度％）", "每日（每月额度％）",
          "일별 (월간 한도 %)", "Par jour (% mois)", "Täglich (% Monat)", "รายวัน (% ของเดือน)")
    }
    public var dailyNoData: String {
        L("Recorded from the day this version started", "このバージョンを使い始めた日から記録されます", "從開始使用此版本的那天起記錄",
          "从开始使用此版本的那天起记录", "이 버전을 사용하기 시작한 날부터 기록됨", "Enregistré à partir du premier jour d’utilisation de cette version",
          "Wird ab dem ersten Tag mit dieser Version aufgezeichnet", "บันทึกตั้งแต่วันที่เริ่มใช้เวอร์ชันนี้")
    }
    public var githubDailyNote: String {
        L("Dates are UTC", "日付はUTC", "日期為 UTC", "日期为 UTC", "날짜는 UTC 기준", "Dates en UTC", "Daten in UTC", "วันที่ตาม UTC")
    }
    public var loading: String { L("Loading…", "読み込み中…", "載入中…", "加载中…", "불러오는 중…", "Chargement…", "Wird geladen…", "กำลังโหลด…") }
    // Codex limit-reset credits
    public func resetCreditsLine(_ count: Int) -> String {
        fill(L("Limit resets: %1 left", "上限のリセット：残り%1回", "額度重置：剩餘 %1 次", "额度重置：剩余 %1 次",
               "한도 초기화: %1회 남음", "Réinitialisations de limite : %1 restante(s)", "Limit-Zurücksetzungen: %1 übrig",
               "รีเซ็ตขีดจำกัด: เหลือ %1 ครั้ง"), String(count))
    }
    public func resetCreditsExpiry(_ date: String) -> String {
        fill(L("Earliest expiry: %1", "最短の期限：%1", "最早到期：%1", "最早到期：%1", "가장 빠른 만료: %1",
               "Première expiration : %1", "Frühester Ablauf: %1", "หมดอายุเร็วสุด: %1"), date)
    }
    public func resetCreditArrived(_ remaining: Int) -> String {
        fill(L("A limit reset arrived (%1 left)", "上限のリセットが届きました（残り%1回）", "收到額度重置（剩餘 %1 次）",
               "收到额度重置（剩余 %1 次）", "한도 초기화가 도착했습니다 (%1회 남음)", "Une réinitialisation de limite est arrivée (%1 restante(s))",
               "Eine Limit-Zurücksetzung ist eingetroffen (%1 übrig)", "ได้รับการรีเซ็ตขีดจำกัดแล้ว (เหลือ %1 ครั้ง)"), String(remaining))
    }
    public var notifyResetCredits: String {
        L("Notify when a limit reset arrives", "上限のリセットが届いたら通知", "收到額度重置時通知", "收到额度重置时通知",
          "한도 초기화가 도착하면 알림", "Notifier à l’arrivée d’une réinitialisation de limite",
          "Benachrichtigen, wenn eine Limit-Zurücksetzung eintrifft", "แจ้งเตือนเมื่อได้รับการรีเซ็ตขีดจำกัด")
    }
    public var notificationsDenied: String {
        L("Notifications are not allowed", "通知が許可されていません", "未允許通知", "未允许通知",
          "알림이 허용되지 않음", "Notifications non autorisées", "Mitteilungen sind nicht erlaubt", "ไม่ได้อนุญาตการแจ้งเตือน")
    }
    public var openSystemSettings: String {
        L("Open Settings", "設定を開く", "打開設定", "打开设置", "설정 열기", "Ouvrir les réglages", "Einstellungen öffnen", "เปิดการตั้งค่า")
    }
    public var previousWeek: String { L("Previous week", "前の週", "上一週", "上一周", "이전 주", "Semaine précédente", "Vorherige Woche", "สัปดาห์ก่อน") }
    public var nextWeek: String { L("Next week", "次の週", "下一週", "下一周", "다음 주", "Semaine suivante", "Nächste Woche", "สัปดาห์ถัดไป") }
    public var notOffered: String {
        L("Not offered on this plan", "このプランでは提供されていません", "此方案未提供", "此套餐未提供",
          "이 요금제에서는 제공되지 않음", "Non inclus dans cette offre", "In diesem Tarif nicht enthalten", "แพ็กเกจนี้ไม่มี")
    }
    public var refresh: String { L("Refresh", "更新", "重新整理", "刷新", "새로 고침", "Actualiser", "Aktualisieren", "รีเฟรช") }
    public var refreshing: String { L("Refreshing…", "更新中…", "正在重新整理…", "正在刷新…", "새로 고치는 중…", "Actualisation…", "Wird aktualisiert…", "กำลังรีเฟรช…") }
    public var settings: String { L("Settings", "設定", "設定", "设置", "설정", "Réglages", "Einstellungen", "การตั้งค่า") }
    public var quit: String { L("Quit", "終了", "結束", "退出", "종료", "Quitter", "Beenden", "ออก") }
    public var never: String { L("Never", "未取得", "尚未取得", "尚未获取", "없음", "Jamais", "Noch nie", "ยังไม่มี") }

    public func lastUpdated(_ text: String) -> String {
        fill(L("Updated %1", "最終更新：%1", "最後更新：%1", "最后更新：%1", "마지막 업데이트: %1", "Mis à jour : %1", "Aktualisiert: %1", "อัปเดตล่าสุด: %1"), text)
    }
    public func resetLine(_ time: String, remaining: String?) -> String {
        guard let remaining else {
            return fill(L("Resets %1", "リセット：%1", "重置：%1", "重置：%1", "초기화: %1", "Réinitialisation : %1", "Zurücksetzung: %1", "รีเซ็ต: %1"), time)
        }
        return fill(L("Resets %1 (in %2)", "リセット：%1（あと%2）", "重置：%1（還有%2）", "重置：%1（还有%2）",
                      "초기화: %1 (%2 후)", "Réinitialisation : %1 (dans %2)", "Zurücksetzung: %1 (in %2)", "รีเซ็ต: %1 (อีก %2)"), time, remaining)
    }

    // Errors
    public var codexNotFound: String { L("Codex not found", "Codexが見つかりません", "找不到 Codex", "找不到 Codex", "Codex를 찾을 수 없음", "Codex introuvable", "Codex nicht gefunden", "ไม่พบ Codex") }
    public var codexNotSignedIn: String {
        L("Not signed in to Codex", "Codexにサインインしていません", "尚未登入 Codex", "尚未登录 Codex",
          "Codex에 로그인되어 있지 않음", "Non connecté à Codex", "Nicht bei Codex angemeldet", "ยังไม่ได้ลงชื่อเข้าใช้ Codex")
    }
    public var fetchTimedOut: String { L("No response", "応答がありません", "沒有回應", "没有响应", "응답 없음", "Aucune réponse", "Keine Antwort", "ไม่มีการตอบกลับ") }
    public var fetchFailed: String {
        L("Couldn't update", "更新できませんでした", "無法更新", "无法更新", "업데이트할 수 없음", "Mise à jour impossible", "Aktualisierung fehlgeschlagen", "อัปเดตไม่สำเร็จ")
    }
    public var showingLastValues: String {
        L("Showing last values", "前回の値を表示中", "顯示上次的數值", "显示上次的数值", "이전 값 표시 중", "Dernières valeurs affichées", "Letzte Werte werden angezeigt", "แสดงค่าล่าสุด")
    }
    public var signInCodex: String {
        L("Sign in to Codex in browser", "ブラウザでCodexにサインイン", "在瀏覽器中登入 Codex", "在浏览器中登录 Codex",
          "브라우저에서 Codex 로그인", "Se connecter à Codex dans le navigateur", "Im Browser bei Codex anmelden", "ลงชื่อเข้าใช้ Codex ในเบราว์เซอร์")
    }
    public var claudeNotSignedIn: String {
        L("Not signed in to Claude Code", "Claude Codeにログインしていません", "尚未登入 Claude Code", "尚未登录 Claude Code",
          "Claude Code에 로그인되어 있지 않음", "Non connecté à Claude Code", "Nicht bei Claude Code angemeldet", "ยังไม่ได้ลงชื่อเข้าใช้ Claude Code")
    }
    public var signInClaude: String {
        L("Sign in to Claude Code in browser", "ブラウザでClaude Codeにログイン", "在瀏覽器中登入 Claude Code", "在浏览器中登录 Claude Code",
          "브라우저에서 Claude Code 로그인", "Se connecter à Claude Code dans le navigateur", "Im Browser bei Claude Code anmelden", "ลงชื่อเข้าใช้ Claude Code ในเบราว์เซอร์")
    }
    public var claudeNotInstalled: String {
        L("Claude Code not found", "Claude Codeが見つかりません", "找不到 Claude Code", "找不到 Claude Code",
          "Claude Code를 찾을 수 없음", "Claude Code introuvable", "Claude Code nicht gefunden", "ไม่พบ Claude Code")
    }
    public var claudeNotLinked: String {
        L("Not connected to Claude Code", "Claude Codeと未連携", "尚未連結 Claude Code", "尚未关联 Claude Code",
          "Claude Code와 연결되지 않음", "Non relié à Claude Code", "Nicht mit Claude Code verbunden", "ยังไม่ได้เชื่อมต่อกับ Claude Code")
    }
    public var claudeWaiting: String {
        L("Shown after Claude Code's next response", "Claude Codeの次の応答で表示されます", "將在 Claude Code 下次回應後顯示", "将在 Claude Code 下次响应后显示",
          "Claude Code의 다음 응답 후 표시됨", "Affiché après la prochaine réponse de Claude Code",
          "Wird nach der nächsten Antwort von Claude Code angezeigt", "จะแสดงหลังจาก Claude Code ตอบครั้งถัดไป")
    }

    // Settings
    public var menuBarItems: String {
        L("Menu bar items", "メニューバー表示", "選單列項目", "菜单栏项目", "메뉴 막대 항목", "Éléments de la barre des menus", "Menüleistenobjekte", "รายการในแถบเมนู")
    }
    public var reorderHint: String {
        L("Hold ⌘ and drag to reorder", "⌘を押しながらドラッグで並べ替え", "按住 ⌘ 並拖移以重新排序", "按住 ⌘ 并拖动以重新排序",
          "⌘를 누른 채 드래그하여 순서 변경", "Maintenez ⌘ et faites glisser pour réorganiser", "Zum Umordnen ⌘ gedrückt halten und ziehen", "กด ⌘ ค้างไว้แล้วลากเพื่อจัดลำดับ")
    }
    public var keepOneHint: String {
        L("At least one item stays visible", "最低1つは表示されます", "至少會顯示一個項目", "至少会显示一个项目",
          "최소 한 개 항목은 표시됨", "Au moins un élément reste visible", "Mindestens ein Objekt bleibt sichtbar", "จะแสดงอย่างน้อยหนึ่งรายการ")
    }
    public var numbers: String { L("Numbers", "数値", "數值", "数值", "숫자", "Valeurs", "Werte", "ตัวเลข") }
    public var language: String { L("Language", "言語", "語言", "语言", "언어", "Langue", "Sprache", "ภาษา") }
    public var automatic: String { L("Automatic", "自動", "自動", "自动", "자동", "Automatique", "Automatisch", "อัตโนมัติ") }
    public var launchAtLogin: String {
        L("Launch at login", "ログイン時に起動", "登入時開啟", "登录时打开", "로그인 시 실행", "Ouvrir à la connexion", "Bei der Anmeldung öffnen", "เปิดเมื่อเข้าสู่ระบบ")
    }
    public var connections: String { L("Connections", "接続", "連線", "连接", "연결", "Connexions", "Verbindungen", "การเชื่อมต่อ") }
    public var connected: String { L("Connected", "接続済み", "已連線", "已连接", "연결됨", "Connecté", "Verbunden", "เชื่อมต่อแล้ว") }
    public var notConnected: String { L("Not connected", "未接続", "未連線", "未连接", "연결 안 됨", "Non connecté", "Nicht verbunden", "ยังไม่ได้เชื่อมต่อ") }

    // Updates
    public func updateAvailable(_ v: String) -> String {
        fill(L("Version %1 is available", "新しいバージョン v%1 があります", "有新版本 v%1", "有新版本 v%1",
               "새 버전 v%1 사용 가능", "La version %1 est disponible", "Version %1 ist verfügbar", "มีเวอร์ชันใหม่ %1"), v)
    }
    public var updateNow: String { L("Update", "アップデート", "更新", "更新", "업데이트", "Mettre à jour", "Aktualisieren", "อัปเดต") }
    public var updating: String { L("Updating…", "アップデート中…", "正在更新…", "正在更新…", "업데이트 중…", "Mise à jour…", "Wird aktualisiert…", "กำลังอัปเดต…") }
    public var updateFailed: String {
        L("Update failed", "アップデートできませんでした", "更新失敗", "更新失败", "업데이트 실패", "Échec de la mise à jour", "Aktualisierung fehlgeschlagen", "อัปเดตไม่สำเร็จ")
    }
    public var upToDate: String { L("Up to date", "最新です", "已是最新版本", "已是最新版本", "최신 버전", "À jour", "Aktuell", "เป็นเวอร์ชันล่าสุด") }
    public var checkingForUpdates: String {
        L("Checking…", "確認中…", "正在檢查…", "正在检查…", "확인 중…", "Vérification…", "Wird geprüft…", "กำลังตรวจสอบ…")
    }
    public var signingIn: String {
        L("Signing in…", "サインイン中…", "正在登入…", "正在登录…", "로그인 중…", "Connexion…", "Anmeldung läuft…", "กำลังลงชื่อเข้าใช้…")
    }
    public var checkForUpdates: String { L("Check", "確認", "檢查", "检查", "확인", "Vérifier", "Prüfen", "ตรวจสอบ") }
    public var version: String { L("Version", "バージョン", "版本", "版本", "버전", "Version", "Version", "เวอร์ชัน") }

    // GitHub Actions
    public var privateFreeQuota: String {
        L("Free usage (private repos)", "無料枠（非公開リポジトリ）", "免費額度（私人存放庫）", "免费额度（私有仓库）",
          "무료 사용량 (비공개 저장소)", "Utilisation gratuite (dépôts privés)", "Kostenloses Kontingent (private Repos)", "โควตาฟรี (รีโพส่วนตัว)")
    }
    public var publicReposFree: String {
        L("Public repositories are free with no limit", "公開リポジトリは無料・上限なし", "公開存放庫免費且無上限", "公开仓库免费且无上限",
          "공개 저장소는 무료이며 제한 없음", "Les dépôts publics sont gratuits et illimités", "Öffentliche Repos sind kostenlos und unbegrenzt", "รีโพสาธารณะใช้ฟรีไม่จำกัด")
    }
    public var githubDelay: String {
        L("GitHub's totals can lag by a few hours", "GitHubの集計は数時間遅れることがあります", "GitHub 的統計可能延遲數小時", "GitHub 的统计可能延迟数小时",
          "GitHub 집계는 몇 시간 늦을 수 있음", "Les totaux GitHub peuvent avoir quelques heures de retard", "GitHub-Summen können einige Stunden verzögert sein", "ยอดของ GitHub อาจช้าไม่กี่ชั่วโมง")
    }
    public func privateFreeQuotaWithBudget(_ amount: String) -> String {
        fill(L("Free + %1 budget (private repos)", "無料枠＋予算%1（非公開リポジトリ）", "免費額度＋預算 %1（私人存放庫）",
               "免费额度＋预算 %1（私有仓库）", "무료 + 예산 %1 (비공개 저장소)", "Gratuit + budget %1 (dépôts privés)",
               "Gratis + Budget %1 (private Repos)", "ฟรี + งบ %1 (รีโพส่วนตัว)"), amount)
    }
    public var legendFree: String { L("Free", "無料枠", "免費額度", "免费额度", "무료", "Gratuit", "Gratis", "ฟรี") }
    public var legendBudget: String { L("Budget", "予算", "預算", "预算", "예산", "Budget", "Budget", "งบ") }
    public func budgetRowTitle(_ amount: String) -> String {
        fill(L("Budget (%1)", "予算（%1）", "預算（%1）", "预算（%1）", "예산 (%1)", "Budget (%1)", "Budget (%1)", "งบ (%1)"), amount)
    }
    public func budgetSpent(_ used: String, _ total: String) -> String {
        fill(L("Spent %1 of %2", "使用額：%1 / %2", "已用 %1 / %2", "已用 %1 / %2", "사용액: %1 / %2",
               "Dépensé : %1 sur %2", "Ausgegeben: %1 von %2", "ใช้ไป %1 จาก %2"), used, total)
    }
    public var budgetUsedUp: String {
        L("Free usage and budget are used up", "無料枠と予算を使い切りました", "免費額度與預算已用完", "免费额度和预算已用完",
          "무료 사용량과 예산을 모두 사용함", "Utilisation gratuite et budget épuisés", "Kostenloses Kontingent und Budget aufgebraucht",
          "ใช้โควตาฟรีและงบหมดแล้ว")
    }
    public var monthlyBudget: String {
        L("Monthly Actions budget (optional)", "Actionsの月の予算（任意）", "Actions 每月預算（選填）", "Actions 每月预算（可选）",
          "Actions 월 예산 (선택)", "Budget mensuel Actions (facultatif)", "Monatliches Actions-Budget (optional)", "งบ Actions รายเดือน (ไม่บังคับ)")
    }
    public var budgetHelp: String {
        L("Same amount as your Actions budget on GitHub. Leave empty if you have none.",
          "GitHubで設定したActionsの予算と同じ額。設定していなければ空欄のまま。",
          "與你在 GitHub 設定的 Actions 預算相同。未設定則留空。", "与你在 GitHub 设置的 Actions 预算相同。未设置则留空。",
          "GitHub에서 설정한 Actions 예산과 같은 금액. 없으면 비워 두세요.",
          "Même montant que votre budget Actions sur GitHub. Laissez vide si vous n’en avez pas.",
          "Gleicher Betrag wie das Actions-Budget auf GitHub. Leer lassen, wenn keines festgelegt ist.",
          "จำนวนเดียวกับงบ Actions ที่ตั้งไว้ใน GitHub เว้นว่างไว้หากไม่ได้ตั้ง")
    }
    public var freeQuotaUsedUp: String {
        L("Free usage is used up", "無料枠を使い切りました", "免費額度已用完", "免费额度已用完",
          "무료 사용량을 모두 사용함", "Utilisation gratuite épuisée", "Kostenloses Kontingent aufgebraucht", "ใช้โควตาฟรีหมดแล้ว")
    }
    public var githubNotConnected: String {
        L("Not connected to GitHub", "GitHubと未連携", "尚未連結 GitHub", "尚未关联 GitHub",
          "GitHub와 연결되지 않음", "Non relié à GitHub", "Nicht mit GitHub verbunden", "ยังไม่ได้เชื่อมต่อกับ GitHub")
    }
    public var connectGitHub: String {
        L("Connect GitHub", "GitHubと連携", "連結 GitHub", "关联 GitHub", "GitHub 연결", "Relier GitHub", "Mit GitHub verbinden", "เชื่อมต่อ GitHub")
    }
    public func githubEnterCode(_ code: String) -> String {
        fill(L("Enter %1 in the browser (copied)", "ブラウザで %1 を入力（コピー済み）", "請在瀏覽器輸入 %1（已複製）", "请在浏览器中输入 %1（已复制）",
               "브라우저에 %1 입력 (복사됨)", "Saisissez %1 dans le navigateur (copié)", "%1 im Browser eingeben (kopiert)", "ป้อน %1 ในเบราว์เซอร์ (คัดลอกแล้ว)"), code)
    }
    public var githubUnknownPlan: String {
        L("This plan's free usage isn't known", "このプランの無料枠が分からないため表示できません", "無法得知此方案的免費額度", "无法得知此套餐的免费额度",
          "이 요금제의 무료 사용량을 알 수 없음", "Utilisation gratuite inconnue pour cette offre", "Kostenloses Kontingent dieses Tarifs unbekannt", "ไม่ทราบโควตาฟรีของแพ็กเกจนี้")
    }
    public var githubTooManyRepos: String {
        L("Too many public repositories to check", "公開リポジトリが多すぎて確認できません", "公開存放庫過多，無法確認", "公开仓库过多，无法确认",
          "공개 저장소가 너무 많아 확인할 수 없음", "Trop de dépôts publics à vérifier", "Zu viele öffentliche Repos zum Prüfen", "มีรีโพสาธารณะมากเกินกว่าจะตรวจสอบ")
    }

    public var pausedHidden: String {
        L("Paused (hidden)", "表示OFFのため停止中", "已暫停（已隱藏）", "已暂停（已隐藏）", "일시 정지됨 (숨김)", "En pause (masqué)", "Pausiert (ausgeblendet)", "หยุดชั่วคราว (ซ่อนอยู่)")
    }
    public var connect: String { L("Connect", "連携する", "連結", "关联", "연결", "Relier", "Verbinden", "เชื่อมต่อ") }
    public var disconnect: String { L("Disconnect", "連携を解除", "取消連結", "取消关联", "연결 해제", "Délier", "Trennen", "ยกเลิกการเชื่อมต่อ") }
    public var replacedByUser: String {
        L("statusLine was changed to another command", "statusLineが別の設定に変更されています", "statusLine 已改為其他指令", "statusLine 已改为其他命令",
          "statusLine이 다른 명령으로 변경됨", "statusLine a été remplacé par une autre commande",
          "statusLine wurde auf einen anderen Befehl geändert", "statusLine ถูกเปลี่ยนเป็นคำสั่งอื่นแล้ว")
    }
    public var launchAtLoginNeedsApproval: String {
        L("Allow it in System Settings > General > Login Items", "システム設定 > 一般 > ログイン項目で許可してください",
          "請在「系統設定」>「一般」>「登入項目」中允許", "请在“系统设置”>“通用”>“登录项”中允许",
          "시스템 설정 > 일반 > 로그인 항목에서 허용하세요", "Autorisez-la dans Réglages Système > Général > Ouverture",
          "Unter Systemeinstellungen > Allgemein > Anmeldeobjekte erlauben", "อนุญาตใน การตั้งค่าระบบ > ทั่วไป > รายการเข้าสู่ระบบ")
    }

    public func itemName(_ id: ItemID) -> String {
        "\(id.provider.displayName) \(id.window.letter) (\(windowTitle(id.window)))"
    }

    // Claude link confirmation
    public var linkTitle: String {
        L("Connect to Claude Code?", "Claude Codeと連携しますか？", "要連結 Claude Code 嗎？", "要关联 Claude Code 吗？",
          "Claude Code와 연결할까요?", "Relier à Claude Code ?", "Mit Claude Code verbinden?", "เชื่อมต่อกับ Claude Code หรือไม่")
    }
    public func linkMessage(existing: String?, settingsPath: String) -> String {
        let keep = existing.map {
            fill(L("Your current statusLine (%1) keeps showing as before.", "現在のstatusLine（%1）はそのまま表示されます。",
                   "目前的 statusLine（%1）會照常顯示。", "当前的 statusLine（%1）会照常显示。",
                   "현재 statusLine(%1)은 그대로 표시됩니다.", "Votre statusLine actuel (%1) reste affiché comme avant.",
                   "Die aktuelle statusLine (%1) wird weiterhin angezeigt.", "statusLine ปัจจุบัน (%1) จะยังแสดงเหมือนเดิม"), $0)
        } ?? ""
        return fill(L(
            "To receive usage limits, TSAI UsageBar changes statusLine in %1 to its relay command. %2\nThe previous setting is backed up and restored when you disconnect or uninstall.",
            "利用枠を受け取るため、%1 の statusLine をTSAI UsageBarの中継コマンドに変更します。%2\n変更前の設定はバックアップし、連携解除やアンインストールで元に戻します。",
            "為了接收用量上限，TSAI UsageBar 會將 %1 中的 statusLine 改為其轉送指令。%2\n原本的設定會備份，並在取消連結或解除安裝時還原。",
            "为了接收用量上限，TSAI UsageBar 会将 %1 中的 statusLine 改为其转发命令。%2\n原来的设置会备份，并在取消关联或卸载时恢复。",
            "사용 한도를 받기 위해 TSAI UsageBar가 %1의 statusLine을 중계 명령으로 변경합니다. %2\n이전 설정은 백업되며, 연결 해제나 제거 시 복원됩니다.",
            "Pour recevoir les limites d’utilisation, TSAI UsageBar remplace le statusLine de %1 par sa commande relais. %2\nLe réglage précédent est sauvegardé, puis restauré si vous déliez ou désinstallez l’app.",
            "Um Nutzungslimits zu empfangen, ändert TSAI UsageBar die statusLine in %1 auf seinen Weiterleitungsbefehl. %2\nDie vorherige Einstellung wird gesichert und beim Trennen oder Deinstallieren wiederhergestellt.",
            "เพื่อรับข้อมูลขีดจำกัดการใช้งาน TSAI UsageBar จะเปลี่ยน statusLine ใน %1 เป็นคำสั่งส่งต่อของแอป %2\nการตั้งค่าเดิมจะถูกสำรองไว้และกู้คืนเมื่อยกเลิกการเชื่อมต่อหรือถอนการติดตั้ง"
        ), settingsPath, keep)
    }
    public var cancel: String { L("Cancel", "キャンセル", "取消", "取消", "취소", "Annuler", "Abbrechen", "ยกเลิก") }
    public var linkFailed: String {
        L("Couldn't connect", "連携できませんでした", "無法連結", "无法关联", "연결할 수 없음", "Impossible de relier", "Verbindung fehlgeschlagen", "เชื่อมต่อไม่สำเร็จ")
    }
    public var settingsUnreadable: String {
        L("Couldn't read Claude Code settings. Nothing was changed.", "Claude Codeの設定ファイルを読み取れません。変更していません。",
          "無法讀取 Claude Code 設定，未做任何變更。", "无法读取 Claude Code 设置，未做任何更改。",
          "Claude Code 설정을 읽을 수 없습니다. 아무것도 변경하지 않았습니다.", "Impossible de lire les réglages de Claude Code. Rien n’a été modifié.",
          "Claude-Code-Einstellungen konnten nicht gelesen werden. Es wurde nichts geändert.", "อ่านการตั้งค่า Claude Code ไม่ได้ ไม่มีการเปลี่ยนแปลงใด ๆ")
    }
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
        f.unitsStyle = .abbreviated
        f.zeroFormattingBehavior = .dropAll
        return f.string(from: max(60, minutes * 60)) ?? ""
    }

    public func clock(_ date: Date, now: Date) -> String { reset(date, now: now) }
}
