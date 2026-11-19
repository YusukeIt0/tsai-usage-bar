import Foundation

/// Language choice in Settings: automatic, or one of the supported languages.
/// The TripSurf website's eight languages, plus pt-BR, id, es and ru.
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
    case ptBR = "pt-br"
    case id
    case es
    case ru

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
        case .ptBR: return "Português (Brasil)"
        case .id: return "Bahasa Indonesia"
        case .es: return "Español"
        case .ru: return "Русский"
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
        case .ptBR: return Locale(identifier: "pt_BR")
        case .id: return Locale(identifier: "id_ID")
        case .es: return Locale(identifier: "es")
        case .ru: return Locale(identifier: "ru_RU")
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
        if base == "pt" { return .ptBR }      // any Portuguese uses the Brazilian translation
        if base == "in" { return .id }        // legacy code for Indonesian
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
                   _ ko: String, _ fr: String, _ de: String, _ th: String,
                   _ ptBR: String, _ id: String, _ es: String, _ ru: String) -> String {
        switch lang {
        case .ptBR: return ptBR
        case .id: return id
        case .es: return es
        case .ru: return ru
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
        case .fiveHour: return L("5 hours", "5時間", "5小時", "5小时", "5시간", "5 heures", "5 Stunden", "5 ชั่วโมง", "5 horas", "5 jam", "5 horas", "5 часов")
        case .sevenDay: return L("7 days", "7日間", "7天", "7天", "7일", "7 jours", "7 Tage", "7 วัน", "7 dias", "7 hari", "7 días", "7 дней")
        case .month: return L("This month", "今月", "本月", "本月", "이번 달", "Ce mois-ci", "Diesen Monat", "เดือนนี้", "Este mês", "Bulan ini", "Este mes", "Этот месяц")
        }
    }

    public func modeCaption(_ mode: DisplayMode) -> String {
        mode == .remaining
            ? L("Remaining", "残量", "剩餘", "剩余", "남은 양", "Restant", "Verbleibend", "คงเหลือ", "Restante", "Sisa", "Restante", "Осталось")
            : L("Used", "使用率", "已使用", "已使用", "사용량", "Utilisé", "Verbraucht", "ใช้ไป", "Usado", "Terpakai", "Usado", "Использовано")
    }

    public var unavailable: String { L("No data", "データなし", "無資料", "无数据", "데이터 없음", "Aucune donnée", "Keine Daten", "ไม่มีข้อมูล", "Sem dados", "Tidak ada data", "Sin datos", "Нет данных") }
    public var awaitingAfterReset: String {
        L("Reset passed · waiting for update", "リセット済み・更新待ち", "已重置・等待更新", "已重置・等待更新",
          "초기화됨 · 업데이트 대기 중", "Réinitialisé · en attente de mise à jour", "Zurückgesetzt · warte auf Aktualisierung", "รีเซ็ตแล้ว · กำลังรอข้อมูลใหม่", "Redefinido · aguardando atualização", "Sudah direset · menunggu pembaruan", "Restablecido · esperando actualización", "Сброшено · ожидание обновления")
    }
    public var resetNewWindowOnNextUse: String {
        L("Reset · a new window starts on next use", "リセット済み・次の利用で新しい枠が始まります",
          "已重置・下次使用時開始新的額度", "已重置・下次使用时开始新的额度",
          "초기화됨 · 다음 사용 시 새 기간 시작", "Réinitialisé · une nouvelle période démarre à la prochaine utilisation",
          "Zurückgesetzt · neues Zeitfenster beginnt bei nächster Nutzung", "รีเซ็ตแล้ว · ช่วงใหม่จะเริ่มเมื่อใช้งานครั้งถัดไป", "Redefinido · um novo período começa no próximo uso", "Direset · periode baru dimulai saat digunakan lagi", "Restablecido · un nuevo periodo empieza con el próximo uso", "Сброшено · новый период начнётся при следующем использовании")
    }
    /// Chart titles say what the percentages are of, so bar labels like "12%" are clear.
    public var dailyWeeklyTitle: String {
        L("Daily (% of week)", "日別（週間枠の％）", "每日（每週額度％）", "每日（每周额度％）",
          "일별 (주간 한도 %)", "Par jour (% semaine)", "Täglich (% Woche)", "รายวัน (% ของสัปดาห์)", "Diário (% da semana)", "Harian (% minggu)", "Diario (% semana)", "По дням (% недели)")
    }
    public var dailyMonthlyTitle: String {
        L("Daily (% of month)", "日別（月間枠の％）", "每日（每月額度％）", "每日（每月额度％）",
          "일별 (월간 한도 %)", "Par jour (% mois)", "Täglich (% Monat)", "รายวัน (% ของเดือน)", "Diário (% do mês)", "Harian (% bulan)", "Diario (% mes)", "По дням (% месяца)")
    }
    public var dailyNoData: String {
        L("Recorded from the day this version started", "このバージョンを使い始めた日から記録されます", "從開始使用此版本的那天起記錄",
          "从开始使用此版本的那天起记录", "이 버전을 사용하기 시작한 날부터 기록됨", "Enregistré à partir du premier jour d’utilisation de cette version",
          "Wird ab dem ersten Tag mit dieser Version aufgezeichnet", "บันทึกตั้งแต่วันที่เริ่มใช้เวอร์ชันนี้", "Registrado desde o dia em que você começou a usar esta versão", "Dicatat sejak hari versi ini mulai digunakan", "Se registra desde el día en que empezaste a usar esta versión", "Записывается с первого дня использования этой версии")
    }
    public var githubDailyNote: String {
        L("Dates are UTC", "日付はUTC", "日期為 UTC", "日期为 UTC", "날짜는 UTC 기준", "Dates en UTC", "Daten in UTC", "วันที่ตาม UTC", "Datas em UTC", "Tanggal dalam UTC", "Fechas en UTC", "Даты по UTC")
    }
    public var loading: String { L("Loading…", "読み込み中…", "載入中…", "加载中…", "불러오는 중…", "Chargement…", "Wird geladen…", "กำลังโหลด…", "Carregando…", "Memuat…", "Cargando…", "Загрузка…") }
    // Codex limit-reset credits
    public func resetCreditsLine(_ count: Int) -> String {
        fill(L("Limit resets: %1 left", "上限のリセット：残り%1回", "額度重置：剩餘 %1 次", "额度重置：剩余 %1 次",
               "한도 초기화: %1회 남음", "Réinitialisations de limite : %1 restante(s)", "Limit-Zurücksetzungen: %1 übrig",
               "รีเซ็ตขีดจำกัด: เหลือ %1 ครั้ง", "Redefinições de limite: %1 restante(s)", "Reset batas: sisa %1", "Restablecimientos de límite: quedan %1", "Сбросы лимита: осталось %1"), String(count))
    }
    public func resetCreditsExpiry(_ date: String) -> String {
        fill(L("Earliest expiry: %1", "最短の期限：%1", "最早到期：%1", "最早到期：%1", "가장 빠른 만료: %1",
               "Première expiration : %1", "Frühester Ablauf: %1", "หมดอายุเร็วสุด: %1", "Vence primeiro em: %1", "Kedaluwarsa paling awal: %1", "Primer vencimiento: %1", "Ближайший срок: %1"), date)
    }
    public func resetCreditArrived(_ remaining: Int) -> String {
        fill(L("A limit reset arrived (%1 left)", "上限のリセットが届きました（残り%1回）", "收到額度重置（剩餘 %1 次）",
               "收到额度重置（剩余 %1 次）", "한도 초기화가 도착했습니다 (%1회 남음)", "Une réinitialisation de limite est arrivée (%1 restante(s))",
               "Eine Limit-Zurücksetzung ist eingetroffen (%1 übrig)", "ได้รับการรีเซ็ตขีดจำกัดแล้ว (เหลือ %1 ครั้ง)", "Chegou uma redefinição de limite (%1 restante(s))", "Reset batas diterima (sisa %1)", "Llegó un restablecimiento de límite (quedan %1)", "Получен сброс лимита (осталось %1)"), String(remaining))
    }
    public var notifyResetCredits: String {
        L("Notify when a limit reset arrives", "上限のリセットが届いたら通知", "收到額度重置時通知", "收到额度重置时通知",
          "한도 초기화가 도착하면 알림", "Notifier à l’arrivée d’une réinitialisation de limite",
          "Benachrichtigen, wenn eine Limit-Zurücksetzung eintrifft", "แจ้งเตือนเมื่อได้รับการรีเซ็ตขีดจำกัด", "Notificar quando chegar uma redefinição de limite", "Beri tahu saat reset batas diterima", "Avisar cuando llegue un restablecimiento de límite", "Уведомлять о новом сбросе лимита")
    }
    public var notificationsDenied: String {
        L("Notifications are not allowed", "通知が許可されていません", "未允許通知", "未允许通知",
          "알림이 허용되지 않음", "Notifications non autorisées", "Mitteilungen sind nicht erlaubt", "ไม่ได้อนุญาตการแจ้งเตือน", "Notificações não permitidas", "Notifikasi tidak diizinkan", "Notificaciones no permitidas", "Уведомления не разрешены")
    }
    public var openSystemSettings: String {
        L("Open Settings", "設定を開く", "打開設定", "打开设置", "설정 열기", "Ouvrir les réglages", "Einstellungen öffnen", "เปิดการตั้งค่า", "Abrir Ajustes", "Buka Pengaturan", "Abrir Ajustes", "Открыть настройки")
    }
    public var previousWeek: String { L("Previous week", "前の週", "上一週", "上一周", "이전 주", "Semaine précédente", "Vorherige Woche", "สัปดาห์ก่อน", "Semana anterior", "Minggu sebelumnya", "Semana anterior", "Предыдущая неделя") }
    public var nextWeek: String { L("Next week", "次の週", "下一週", "下一周", "다음 주", "Semaine suivante", "Nächste Woche", "สัปดาห์ถัดไป", "Próxima semana", "Minggu berikutnya", "Semana siguiente", "Следующая неделя") }
    public var notOffered: String {
        L("Not offered on this plan", "このプランでは提供されていません", "此方案未提供", "此套餐未提供",
          "이 요금제에서는 제공되지 않음", "Non inclus dans cette offre", "In diesem Tarif nicht enthalten", "แพ็กเกจนี้ไม่มี", "Não incluído neste plano", "Tidak tersedia di paket ini", "No incluido en este plan", "Нет в этом тарифе")
    }
    public var refresh: String { L("Refresh", "更新", "重新整理", "刷新", "새로 고침", "Actualiser", "Aktualisieren", "รีเฟรช", "Atualizar", "Segarkan", "Actualizar", "Обновить") }
    public var refreshing: String { L("Refreshing…", "更新中…", "正在重新整理…", "正在刷新…", "새로 고치는 중…", "Actualisation…", "Wird aktualisiert…", "กำลังรีเฟรช…", "Atualizando…", "Menyegarkan…", "Actualizando…", "Обновление…") }
    public var settings: String { L("Settings", "設定", "設定", "设置", "설정", "Réglages", "Einstellungen", "การตั้งค่า", "Ajustes", "Pengaturan", "Ajustes", "Настройки") }
    public var quit: String { L("Quit", "終了", "結束", "退出", "종료", "Quitter", "Beenden", "ออก", "Sair", "Keluar", "Salir", "Завершить") }
    public var never: String { L("Never", "未取得", "尚未取得", "尚未获取", "없음", "Jamais", "Noch nie", "ยังไม่มี", "Nunca", "Belum pernah", "Nunca", "Никогда") }

    public func lastUpdated(_ text: String) -> String {
        fill(L("Updated %1", "最終更新：%1", "最後更新：%1", "最后更新：%1", "마지막 업데이트: %1", "Mis à jour : %1", "Aktualisiert: %1", "อัปเดตล่าสุด: %1", "Atualizado: %1", "Diperbarui: %1", "Actualizado: %1", "Обновлено: %1"), text)
    }
    public func resetLine(_ time: String, remaining: String?) -> String {
        guard let remaining else {
            return fill(L("Resets %1", "リセット：%1", "重置：%1", "重置：%1", "초기화: %1", "Réinitialisation : %1", "Zurücksetzung: %1", "รีเซ็ต: %1", "Redefine: %1", "Reset: %1", "Se restablece: %1", "Сброс: %1"), time)
        }
        return fill(L("Resets %1 (in %2)", "リセット：%1（あと%2）", "重置：%1（還有%2）", "重置：%1（还有%2）",
                      "초기화: %1 (%2 후)", "Réinitialisation : %1 (dans %2)", "Zurücksetzung: %1 (in %2)", "รีเซ็ต: %1 (อีก %2)", "Redefine: %1 (em %2)", "Reset: %1 (dalam %2)", "Se restablece: %1 (en %2)", "Сброс: %1 (через %2)"), time, remaining)
    }

    // Errors
    public var codexNotFound: String { L("Codex not found", "Codexが見つかりません", "找不到 Codex", "找不到 Codex", "Codex를 찾을 수 없음", "Codex introuvable", "Codex nicht gefunden", "ไม่พบ Codex", "Codex não encontrado", "Codex tidak ditemukan", "No se encontró Codex", "Codex не найден") }
    public var codexNotSignedIn: String {
        L("Not signed in to Codex", "Codexにサインインしていません", "尚未登入 Codex", "尚未登录 Codex",
          "Codex에 로그인되어 있지 않음", "Non connecté à Codex", "Nicht bei Codex angemeldet", "ยังไม่ได้ลงชื่อเข้าใช้ Codex", "Sem login no Codex", "Belum masuk ke Codex", "Sin sesión en Codex", "Вход в Codex не выполнен")
    }
    public var fetchTimedOut: String { L("No response", "応答がありません", "沒有回應", "没有响应", "응답 없음", "Aucune réponse", "Keine Antwort", "ไม่มีการตอบกลับ", "Sem resposta", "Tidak ada respons", "Sin respuesta", "Нет ответа") }
    public var fetchFailed: String {
        L("Couldn't update", "更新できませんでした", "無法更新", "无法更新", "업데이트할 수 없음", "Mise à jour impossible", "Aktualisierung fehlgeschlagen", "อัปเดตไม่สำเร็จ", "Não foi possível atualizar", "Tidak dapat memperbarui", "No se pudo actualizar", "Не удалось обновить")
    }
    public var showingLastValues: String {
        L("Showing last values", "前回の値を表示中", "顯示上次的數值", "显示上次的数值", "이전 값 표시 중", "Dernières valeurs affichées", "Letzte Werte werden angezeigt", "แสดงค่าล่าสุด", "Mostrando os últimos valores", "Menampilkan nilai terakhir", "Mostrando los últimos valores", "Показаны последние значения")
    }
    public var signInCodex: String {
        L("Sign in to Codex in browser", "ブラウザでCodexにサインイン", "在瀏覽器中登入 Codex", "在浏览器中登录 Codex",
          "브라우저에서 Codex 로그인", "Se connecter à Codex dans le navigateur", "Im Browser bei Codex anmelden", "ลงชื่อเข้าใช้ Codex ในเบราว์เซอร์", "Entrar no Codex pelo navegador", "Masuk ke Codex di browser", "Iniciar sesión en Codex en el navegador", "Войти в Codex в браузере")
    }
    public var claudeNotSignedIn: String {
        L("Not signed in to Claude Code", "Claude Codeにログインしていません", "尚未登入 Claude Code", "尚未登录 Claude Code",
          "Claude Code에 로그인되어 있지 않음", "Non connecté à Claude Code", "Nicht bei Claude Code angemeldet", "ยังไม่ได้ลงชื่อเข้าใช้ Claude Code", "Sem login no Claude Code", "Belum masuk ke Claude Code", "Sin sesión en Claude Code", "Вход в Claude Code не выполнен")
    }
    public var signInClaude: String {
        L("Sign in to Claude Code in browser", "ブラウザでClaude Codeにログイン", "在瀏覽器中登入 Claude Code", "在浏览器中登录 Claude Code",
          "브라우저에서 Claude Code 로그인", "Se connecter à Claude Code dans le navigateur", "Im Browser bei Claude Code anmelden", "ลงชื่อเข้าใช้ Claude Code ในเบราว์เซอร์", "Entrar no Claude Code pelo navegador", "Masuk ke Claude Code di browser", "Iniciar sesión en Claude Code en el navegador", "Войти в Claude Code в браузере")
    }
    public var claudeNotInstalled: String {
        L("Claude Code not found", "Claude Codeが見つかりません", "找不到 Claude Code", "找不到 Claude Code",
          "Claude Code를 찾을 수 없음", "Claude Code introuvable", "Claude Code nicht gefunden", "ไม่พบ Claude Code", "Claude Code não encontrado", "Claude Code tidak ditemukan", "No se encontró Claude Code", "Claude Code не найден")
    }
    public var claudeNotLinked: String {
        L("Not connected to Claude Code", "Claude Codeと未連携", "尚未連結 Claude Code", "尚未关联 Claude Code",
          "Claude Code와 연결되지 않음", "Non relié à Claude Code", "Nicht mit Claude Code verbunden", "ยังไม่ได้เชื่อมต่อกับ Claude Code", "Não conectado ao Claude Code", "Belum terhubung ke Claude Code", "No conectado a Claude Code", "Не подключено к Claude Code")
    }
    public var claudeWaiting: String {
        L("Shown after Claude Code's next response", "Claude Codeの次の応答で表示されます", "將在 Claude Code 下次回應後顯示", "将在 Claude Code 下次响应后显示",
          "Claude Code의 다음 응답 후 표시됨", "Affiché après la prochaine réponse de Claude Code",
          "Wird nach der nächsten Antwort von Claude Code angezeigt", "จะแสดงหลังจาก Claude Code ตอบครั้งถัดไป", "Aparece após a próxima resposta do Claude Code", "Ditampilkan setelah respons Claude Code berikutnya", "Se muestra tras la próxima respuesta de Claude Code", "Появится после следующего ответа Claude Code")
    }

    // Settings
    public var menuBarItems: String {
        L("Menu bar items", "メニューバー表示", "選單列項目", "菜单栏项目", "메뉴 막대 항목", "Éléments de la barre des menus", "Menüleistenobjekte", "รายการในแถบเมนู", "Itens da barra de menus", "Item bar menu", "Elementos de la barra de menús", "Объекты в строке меню")
    }
    public var reorderHint: String {
        L("Hold ⌘ and drag to reorder", "⌘を押しながらドラッグで並べ替え", "按住 ⌘ 並拖移以重新排序", "按住 ⌘ 并拖动以重新排序",
          "⌘를 누른 채 드래그하여 순서 변경", "Maintenez ⌘ et faites glisser pour réorganiser", "Zum Umordnen ⌘ gedrückt halten und ziehen", "กด ⌘ ค้างไว้แล้วลากเพื่อจัดลำดับ", "Segure ⌘ e arraste para reordenar", "Tahan ⌘ dan seret untuk mengurutkan", "Mantén ⌘ y arrastra para reordenar", "Удерживайте ⌘ и перетащите для упорядочивания")
    }
    public var keepOneHint: String {
        L("At least one item stays visible", "最低1つは表示されます", "至少會顯示一個項目", "至少会显示一个项目",
          "최소 한 개 항목은 표시됨", "Au moins un élément reste visible", "Mindestens ein Objekt bleibt sichtbar", "จะแสดงอย่างน้อยหนึ่งรายการ", "Pelo menos um item fica visível", "Setidaknya satu item tetap terlihat", "Al menos un elemento sigue visible", "Хотя бы один объект остаётся видимым")
    }
    public var numbers: String { L("Numbers", "数値", "數值", "数值", "숫자", "Valeurs", "Werte", "ตัวเลข", "Números", "Angka", "Números", "Числа") }
    public var language: String { L("Language", "言語", "語言", "语言", "언어", "Langue", "Sprache", "ภาษา", "Idioma", "Bahasa", "Idioma", "Язык") }
    public var automatic: String { L("Automatic", "自動", "自動", "自动", "자동", "Automatique", "Automatisch", "อัตโนมัติ", "Automático", "Otomatis", "Automático", "Автоматически") }
    public var launchAtLogin: String {
        L("Launch at login", "ログイン時に起動", "登入時開啟", "登录时打开", "로그인 시 실행", "Ouvrir à la connexion", "Bei der Anmeldung öffnen", "เปิดเมื่อเข้าสู่ระบบ", "Abrir ao iniciar sessão", "Buka saat masuk", "Abrir al iniciar sesión", "Открывать при входе")
    }
    public var connections: String { L("Connections", "接続", "連線", "连接", "연결", "Connexions", "Verbindungen", "การเชื่อมต่อ", "Conexões", "Koneksi", "Conexiones", "Подключения") }
    public var connected: String { L("Connected", "接続済み", "已連線", "已连接", "연결됨", "Connecté", "Verbunden", "เชื่อมต่อแล้ว", "Conectado", "Terhubung", "Conectado", "Подключено") }
    public var notConnected: String { L("Not connected", "未接続", "未連線", "未连接", "연결 안 됨", "Non connecté", "Nicht verbunden", "ยังไม่ได้เชื่อมต่อ", "Não conectado", "Belum terhubung", "No conectado", "Не подключено") }

    // Updates
    public func updateAvailable(_ v: String) -> String {
        fill(L("Version %1 is available", "新しいバージョン v%1 があります", "有新版本 v%1", "有新版本 v%1",
               "새 버전 v%1 사용 가능", "La version %1 est disponible", "Version %1 ist verfügbar", "มีเวอร์ชันใหม่ %1", "A versão %1 está disponível", "Versi %1 tersedia", "La versión %1 está disponible", "Доступна версия %1"), v)
    }
    public var updateNow: String { L("Update", "アップデート", "更新", "更新", "업데이트", "Mettre à jour", "Aktualisieren", "อัปเดต", "Atualizar", "Perbarui", "Actualizar", "Обновить") }
    public var updating: String { L("Updating…", "アップデート中…", "正在更新…", "正在更新…", "업데이트 중…", "Mise à jour…", "Wird aktualisiert…", "กำลังอัปเดต…", "Atualizando…", "Memperbarui…", "Actualizando…", "Обновление…") }
    public var updateFailed: String {
        L("Update failed", "アップデートできませんでした", "更新失敗", "更新失败", "업데이트 실패", "Échec de la mise à jour", "Aktualisierung fehlgeschlagen", "อัปเดตไม่สำเร็จ", "Falha na atualização", "Pembaruan gagal", "Error al actualizar", "Не удалось обновить")
    }
    public var upToDate: String { L("Up to date", "最新です", "已是最新版本", "已是最新版本", "최신 버전", "À jour", "Aktuell", "เป็นเวอร์ชันล่าสุด", "Atualizado", "Terbaru", "Actualizado", "Последняя версия") }
    public var checkingForUpdates: String {
        L("Checking…", "確認中…", "正在檢查…", "正在检查…", "확인 중…", "Vérification…", "Wird geprüft…", "กำลังตรวจสอบ…", "Verificando…", "Memeriksa…", "Comprobando…", "Проверка…")
    }
    public var signingIn: String {
        L("Signing in…", "サインイン中…", "正在登入…", "正在登录…", "로그인 중…", "Connexion…", "Anmeldung läuft…", "กำลังลงชื่อเข้าใช้…", "Entrando…", "Sedang masuk…", "Iniciando sesión…", "Вход…")
    }
    public var checkForUpdates: String { L("Check", "確認", "檢查", "检查", "확인", "Vérifier", "Prüfen", "ตรวจสอบ", "Verificar", "Periksa", "Comprobar", "Проверить") }
    public var version: String { L("Version", "バージョン", "版本", "版本", "버전", "Version", "Version", "เวอร์ชัน", "Versão", "Versi", "Versión", "Версия") }

    // GitHub Actions
    public var privateFreeQuota: String {
        L("Free usage (private repos)", "無料枠（非公開リポジトリ）", "免費額度（私人存放庫）", "免费额度（私有仓库）",
          "무료 사용량 (비공개 저장소)", "Utilisation gratuite (dépôts privés)", "Kostenloses Kontingent (private Repos)", "โควตาฟรี (รีโพส่วนตัว)", "Uso gratuito (repos privados)", "Kuota gratis (repo privat)", "Uso gratuito (repos privados)", "Бесплатный лимит (частные репозитории)")
    }
    public var publicReposFree: String {
        L("Public repositories are free with no limit", "公開リポジトリは無料・上限なし", "公開存放庫免費且無上限", "公开仓库免费且无上限",
          "공개 저장소는 무료이며 제한 없음", "Les dépôts publics sont gratuits et illimités", "Öffentliche Repos sind kostenlos und unbegrenzt", "รีโพสาธารณะใช้ฟรีไม่จำกัด", "Repositórios públicos são gratuitos e ilimitados", "Repo publik gratis tanpa batas", "Los repositorios públicos son gratuitos e ilimitados", "Публичные репозитории бесплатны и без ограничений")
    }
    public var githubDelay: String {
        L("GitHub's totals can lag by a few hours", "GitHubの集計は数時間遅れることがあります", "GitHub 的統計可能延遲數小時", "GitHub 的统计可能延迟数小时",
          "GitHub 집계는 몇 시간 늦을 수 있음", "Les totaux GitHub peuvent avoir quelques heures de retard", "GitHub-Summen können einige Stunden verzögert sein", "ยอดของ GitHub อาจช้าไม่กี่ชั่วโมง", "Os totais do GitHub podem atrasar algumas horas", "Total GitHub bisa terlambat beberapa jam", "Los totales de GitHub pueden retrasarse unas horas", "Данные GitHub могут запаздывать на несколько часов")
    }
    public func privateFreeQuotaWithBudget(_ amount: String) -> String {
        fill(L("Free + %1 budget (private repos)", "無料枠＋予算%1（非公開リポジトリ）", "免費額度＋預算 %1（私人存放庫）",
               "免费额度＋预算 %1（私有仓库）", "무료 + 예산 %1 (비공개 저장소)", "Gratuit + budget %1 (dépôts privés)",
               "Gratis + Budget %1 (private Repos)", "ฟรี + งบ %1 (รีโพส่วนตัว)", "Grátis + orçamento %1 (privados)", "Gratis + anggaran %1 (repo privat)", "Gratis + presupuesto %1 (privados)", "Бесплатно + бюджет %1 (частные)"), amount)
    }
    public var legendFree: String { L("Free", "無料枠", "免費額度", "免费额度", "무료", "Gratuit", "Gratis", "ฟรี", "Grátis", "Gratis", "Gratis", "Бесплатно") }
    public var legendBudget: String { L("Budget", "予算", "預算", "预算", "예산", "Budget", "Budget", "งบ", "Orçamento", "Anggaran", "Presupuesto", "Бюджет") }
    public func budgetRowTitle(_ amount: String) -> String {
        fill(L("Budget (%1)", "予算（%1）", "預算（%1）", "预算（%1）", "예산 (%1)", "Budget (%1)", "Budget (%1)", "งบ (%1)", "Orçamento (%1)", "Anggaran (%1)", "Presupuesto (%1)", "Бюджет (%1)"), amount)
    }
    public func budgetSpent(_ used: String, _ total: String) -> String {
        fill(L("Spent %1 of %2", "使用額：%1 / %2", "已用 %1 / %2", "已用 %1 / %2", "사용액: %1 / %2",
               "Dépensé : %1 sur %2", "Ausgegeben: %1 von %2", "ใช้ไป %1 จาก %2", "Gasto: %1 de %2", "Terpakai %1 dari %2", "Gastado: %1 de %2", "Потрачено %1 из %2"), used, total)
    }
    public var budgetUsedUp: String {
        L("Free usage and budget are used up", "無料枠と予算を使い切りました", "免費額度與預算已用完", "免费额度和预算已用完",
          "무료 사용량과 예산을 모두 사용함", "Utilisation gratuite et budget épuisés", "Kostenloses Kontingent und Budget aufgebraucht",
          "ใช้โควตาฟรีและงบหมดแล้ว", "Uso gratuito e orçamento esgotados", "Kuota gratis dan anggaran habis", "Uso gratuito y presupuesto agotados", "Бесплатный лимит и бюджет исчерпаны")
    }
    public var monthlyBudget: String {
        L("Monthly Actions budget (optional)", "Actionsの月の予算（任意）", "Actions 每月預算（選填）", "Actions 每月预算（可选）",
          "Actions 월 예산 (선택)", "Budget mensuel Actions (facultatif)", "Monatliches Actions-Budget (optional)", "งบ Actions รายเดือน (ไม่บังคับ)", "Orçamento mensal do Actions (opcional)", "Anggaran Actions bulanan (opsional)", "Presupuesto mensual de Actions (opcional)", "Месячный бюджет Actions (необязательно)")
    }
    public var budgetHelp: String {
        L("Same amount as your Actions budget on GitHub. Leave empty if you have none.",
          "GitHubで設定したActionsの予算と同じ額。設定していなければ空欄のまま。",
          "與你在 GitHub 設定的 Actions 預算相同。未設定則留空。", "与你在 GitHub 设置的 Actions 预算相同。未设置则留空。",
          "GitHub에서 설정한 Actions 예산과 같은 금액. 없으면 비워 두세요.",
          "Même montant que votre budget Actions sur GitHub. Laissez vide si vous n’en avez pas.",
          "Gleicher Betrag wie das Actions-Budget auf GitHub. Leer lassen, wenn keines festgelegt ist.",
          "จำนวนเดียวกับงบ Actions ที่ตั้งไว้ใน GitHub เว้นว่างไว้หากไม่ได้ตั้ง", "O mesmo valor do seu orçamento do Actions no GitHub. Deixe em branco se não tiver.", "Jumlah yang sama dengan anggaran Actions Anda di GitHub. Kosongkan jika tidak ada.", "El mismo importe que tu presupuesto de Actions en GitHub. Déjalo vacío si no tienes.", "Та же сумма, что и бюджет Actions на GitHub. Оставьте пустым, если бюджета нет.")
    }
    public var freeQuotaUsedUp: String {
        L("Free usage is used up", "無料枠を使い切りました", "免費額度已用完", "免费额度已用完",
          "무료 사용량을 모두 사용함", "Utilisation gratuite épuisée", "Kostenloses Kontingent aufgebraucht", "ใช้โควตาฟรีหมดแล้ว", "Uso gratuito esgotado", "Kuota gratis habis", "Uso gratuito agotado", "Бесплатный лимит исчерпан")
    }
    public var githubNotConnected: String {
        L("Not connected to GitHub", "GitHubと未連携", "尚未連結 GitHub", "尚未关联 GitHub",
          "GitHub와 연결되지 않음", "Non relié à GitHub", "Nicht mit GitHub verbunden", "ยังไม่ได้เชื่อมต่อกับ GitHub", "Não conectado ao GitHub", "Belum terhubung ke GitHub", "No conectado a GitHub", "Не подключено к GitHub")
    }
    public var connectGitHub: String {
        L("Connect GitHub", "GitHubと連携", "連結 GitHub", "关联 GitHub", "GitHub 연결", "Relier GitHub", "Mit GitHub verbinden", "เชื่อมต่อ GitHub", "Conectar GitHub", "Hubungkan GitHub", "Conectar GitHub", "Подключить GitHub")
    }
    public func githubEnterCode(_ code: String) -> String {
        fill(L("Enter %1 in the browser (copied)", "ブラウザで %1 を入力（コピー済み）", "請在瀏覽器輸入 %1（已複製）", "请在浏览器中输入 %1（已复制）",
               "브라우저에 %1 입력 (복사됨)", "Saisissez %1 dans le navigateur (copié)", "%1 im Browser eingeben (kopiert)", "ป้อน %1 ในเบราว์เซอร์ (คัดลอกแล้ว)", "Digite %1 no navegador (copiado)", "Masukkan %1 di browser (sudah disalin)", "Introduce %1 en el navegador (copiado)", "Введите %1 в браузере (скопировано)"), code)
    }
    public var githubUnknownPlan: String {
        L("This plan's free usage isn't known", "このプランの無料枠が分からないため表示できません", "無法得知此方案的免費額度", "无法得知此套餐的免费额度",
          "이 요금제의 무료 사용량을 알 수 없음", "Utilisation gratuite inconnue pour cette offre", "Kostenloses Kontingent dieses Tarifs unbekannt", "ไม่ทราบโควตาฟรีของแพ็กเกจนี้", "Uso gratuito deste plano desconhecido", "Kuota gratis paket ini tidak diketahui", "Se desconoce el uso gratuito de este plan", "Бесплатный лимит этого тарифа неизвестен")
    }
    public var githubTooManyRepos: String {
        L("Too many public repositories to check", "公開リポジトリが多すぎて確認できません", "公開存放庫過多，無法確認", "公开仓库过多，无法确认",
          "공개 저장소가 너무 많아 확인할 수 없음", "Trop de dépôts publics à vérifier", "Zu viele öffentliche Repos zum Prüfen", "มีรีโพสาธารณะมากเกินกว่าจะตรวจสอบ", "Repositórios públicos demais para verificar", "Terlalu banyak repo publik untuk diperiksa", "Demasiados repositorios públicos para comprobar", "Слишком много публичных репозиториев для проверки")
    }

    public var pausedHidden: String {
        L("Paused (hidden)", "表示OFFのため停止中", "已暫停（已隱藏）", "已暂停（已隐藏）", "일시 정지됨 (숨김)", "En pause (masqué)", "Pausiert (ausgeblendet)", "หยุดชั่วคราว (ซ่อนอยู่)", "Pausado (oculto)", "Dijeda (disembunyikan)", "En pausa (oculto)", "Приостановлено (скрыто)")
    }
    public var connect: String { L("Connect", "連携する", "連結", "关联", "연결", "Relier", "Verbinden", "เชื่อมต่อ", "Conectar", "Hubungkan", "Conectar", "Подключить") }
    public var disconnect: String { L("Disconnect", "連携を解除", "取消連結", "取消关联", "연결 해제", "Délier", "Trennen", "ยกเลิกการเชื่อมต่อ", "Desconectar", "Putuskan", "Desconectar", "Отключить") }
    public var replacedByUser: String {
        L("statusLine was changed to another command", "statusLineが別の設定に変更されています", "statusLine 已改為其他指令", "statusLine 已改为其他命令",
          "statusLine이 다른 명령으로 변경됨", "statusLine a été remplacé par une autre commande",
          "statusLine wurde auf einen anderen Befehl geändert", "statusLine ถูกเปลี่ยนเป็นคำสั่งอื่นแล้ว", "O statusLine foi alterado para outro comando", "statusLine telah diubah ke perintah lain", "statusLine se cambió a otro comando", "statusLine изменён на другую команду")
    }
    public var launchAtLoginNeedsApproval: String {
        L("Allow it in System Settings > General > Login Items", "システム設定 > 一般 > ログイン項目で許可してください",
          "請在「系統設定」>「一般」>「登入項目」中允許", "请在“系统设置”>“通用”>“登录项”中允许",
          "시스템 설정 > 일반 > 로그인 항목에서 허용하세요", "Autorisez-la dans Réglages Système > Général > Ouverture",
          "Unter Systemeinstellungen > Allgemein > Anmeldeobjekte erlauben", "อนุญาตใน การตั้งค่าระบบ > ทั่วไป > รายการเข้าสู่ระบบ", "Permita em Ajustes do Sistema > Geral > Itens de Início", "Izinkan di Pengaturan Sistem > Umum > Item Masuk", "Permítelo en Ajustes del Sistema > General > Ítems de inicio", "Разрешите в Системных настройках > Основные > Объекты входа")
    }

    public func itemName(_ id: ItemID) -> String {
        "\(id.provider.displayName) \(id.window.letter) (\(windowTitle(id.window)))"
    }

    // Claude link confirmation
    public var linkTitle: String {
        L("Connect to Claude Code?", "Claude Codeと連携しますか？", "要連結 Claude Code 嗎？", "要关联 Claude Code 吗？",
          "Claude Code와 연결할까요?", "Relier à Claude Code ?", "Mit Claude Code verbinden?", "เชื่อมต่อกับ Claude Code หรือไม่", "Conectar ao Claude Code?", "Hubungkan ke Claude Code?", "¿Conectar con Claude Code?", "Подключиться к Claude Code?")
    }
    public func linkMessage(existing: String?, settingsPath: String) -> String {
        let keep = existing.map {
            fill(L("Your current statusLine (%1) keeps showing as before.", "現在のstatusLine（%1）はそのまま表示されます。",
                   "目前的 statusLine（%1）會照常顯示。", "当前的 statusLine（%1）会照常显示。",
                   "현재 statusLine(%1)은 그대로 표시됩니다.", "Votre statusLine actuel (%1) reste affiché comme avant.",
                   "Die aktuelle statusLine (%1) wird weiterhin angezeigt.", "statusLine ปัจจุบัน (%1) จะยังแสดงเหมือนเดิม", "O statusLine atual (%1) continua aparecendo como antes.", "statusLine Anda saat ini (%1) tetap tampil seperti sebelumnya.", "Tu statusLine actual (%1) se seguirá mostrando como antes.", "Текущий statusLine (%1) будет отображаться как прежде."), $0)
        } ?? ""
        return fill(L(
            "To receive usage limits, TSAI UsageBar changes statusLine in %1 to its relay command. %2\nThe previous setting is backed up and restored when you disconnect or uninstall.",
            "利用枠を受け取るため、%1 の statusLine をTSAI UsageBarの中継コマンドに変更します。%2\n変更前の設定はバックアップし、連携解除やアンインストールで元に戻します。",
            "為了接收用量上限，TSAI UsageBar 會將 %1 中的 statusLine 改為其轉送指令。%2\n原本的設定會備份，並在取消連結或解除安裝時還原。",
            "为了接收用量上限，TSAI UsageBar 会将 %1 中的 statusLine 改为其转发命令。%2\n原来的设置会备份，并在取消关联或卸载时恢复。",
            "사용 한도를 받기 위해 TSAI UsageBar가 %1의 statusLine을 중계 명령으로 변경합니다. %2\n이전 설정은 백업되며, 연결 해제나 제거 시 복원됩니다.",
            "Pour recevoir les limites d’utilisation, TSAI UsageBar remplace le statusLine de %1 par sa commande relais. %2\nLe réglage précédent est sauvegardé, puis restauré si vous déliez ou désinstallez l’app.",
            "Um Nutzungslimits zu empfangen, ändert TSAI UsageBar die statusLine in %1 auf seinen Weiterleitungsbefehl. %2\nDie vorherige Einstellung wird gesichert und beim Trennen oder Deinstallieren wiederhergestellt.",
            "เพื่อรับข้อมูลขีดจำกัดการใช้งาน TSAI UsageBar จะเปลี่ยน statusLine ใน %1 เป็นคำสั่งส่งต่อของแอป %2\nการตั้งค่าเดิมจะถูกสำรองไว้และกู้คืนเมื่อยกเลิกการเชื่อมต่อหรือถอนการติดตั้ง", "Para receber os limites de uso, o TSAI UsageBar altera o statusLine em %1 para o comando de retransmissão. %2\nO ajuste anterior é salvo e restaurado quando você desconectar ou desinstalar.", "Untuk menerima batas penggunaan, TSAI UsageBar mengubah statusLine di %1 ke perintah relai miliknya. %2\nPengaturan sebelumnya dicadangkan dan dipulihkan saat Anda memutuskan atau mencopot pemasangan.", "Para recibir los límites de uso, TSAI UsageBar cambia el statusLine de %1 a su comando de retransmisión. %2\nEl ajuste anterior se guarda y se restaura al desconectar o desinstalar.", "Чтобы получать лимиты использования, TSAI UsageBar заменяет statusLine в %1 на свою команду-ретранслятор. %2\nПрежняя настройка сохраняется и восстанавливается при отключении или удалении."
        ), settingsPath, keep)
    }
    public var cancel: String { L("Cancel", "キャンセル", "取消", "取消", "취소", "Annuler", "Abbrechen", "ยกเลิก", "Cancelar", "Batalkan", "Cancelar", "Отменить") }
    public var linkFailed: String {
        L("Couldn't connect", "連携できませんでした", "無法連結", "无法关联", "연결할 수 없음", "Impossible de relier", "Verbindung fehlgeschlagen", "เชื่อมต่อไม่สำเร็จ", "Não foi possível conectar", "Tidak dapat menghubungkan", "No se pudo conectar", "Не удалось подключиться")
    }
    public var settingsUnreadable: String {
        L("Couldn't read Claude Code settings. Nothing was changed.", "Claude Codeの設定ファイルを読み取れません。変更していません。",
          "無法讀取 Claude Code 設定，未做任何變更。", "无法读取 Claude Code 设置，未做任何更改。",
          "Claude Code 설정을 읽을 수 없습니다. 아무것도 변경하지 않았습니다.", "Impossible de lire les réglages de Claude Code. Rien n’a été modifié.",
          "Claude-Code-Einstellungen konnten nicht gelesen werden. Es wurde nichts geändert.", "อ่านการตั้งค่า Claude Code ไม่ได้ ไม่มีการเปลี่ยนแปลงใด ๆ", "Não foi possível ler os ajustes do Claude Code. Nada foi alterado.", "Tidak dapat membaca pengaturan Claude Code. Tidak ada yang diubah.", "No se pudieron leer los ajustes de Claude Code. No se cambió nada.", "Не удалось прочитать настройки Claude Code. Ничего не изменено.")
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
