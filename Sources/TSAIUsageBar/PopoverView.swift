import SwiftUI
import UsageCore

/// Small panel for one provider: both windows as bars, reset times, and status.
struct PopoverView: View {
    let provider: Provider
    @ObservedObject var model: UsageModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var updates: UpdateChecker
    var openSettings: () -> Void

    private var s: Strings { settings.strings }
    private var status: ProviderStatus { model.status(provider) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(provider.displayName).font(.headline)

            ForEach(provider.windows, id: \.self) { kind in
                windowRow(kind)
            }
            if provider == .github { budgetRow }

            if let notice = noticeText {
                notice
            }

            if provider == .github, model.githubLogin != nil {
                Divider()
                DailyChart(title: s.dailyMonthlyTitle, note: s.githubDailyNote,
                           emptyText: model.githubDailyFailed && !model.githubDailyLoading ? s.fetchFailed : s.loading,
                           strings: s, lang: settings.appLanguage, now: model.now) { end in
                    DailyChart.days(endingAt: end).map { d in
                        (d, model.githubDaily.percent(DailyUsageLog.dayKey(d), budgetUSD: model.githubBudgetUSD))
                    }
                } earliest: {
                    GitHubDailyCache.utcKey(Date().addingTimeInterval(-728 * 86_400))
                } onShow: { days in
                    model.loadGitHubDays(days.map { DailyUsageLog.dayKey($0) })
                }
            }

            if provider == .codex, let credits = status.snapshot?.resetCredits, credits.available > 0 {
                Divider()
                VStack(alignment: .leading, spacing: 2) {
                    Label(s.resetCreditsLine(credits.available), systemImage: "ticket")
                        .font(.caption.weight(.semibold))
                    if let expiry = credits.earliestExpiry {
                        Text(s.resetCreditsExpiry(TimeText(settings.appLanguage).reset(expiry, now: model.now)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if provider != .github, status.snapshot?.offers(.sevenDay) != false {
                Divider()
                DailyChart(title: s.dailyWeeklyTitle, note: nil, emptyText: s.dailyNoData, strings: s,
                           lang: settings.appLanguage, now: model.now) { end in
                    (model.daily[provider] ?? DailyUsageLog()).values(endingAt: end)
                } earliest: {
                    model.daily[provider]?.firstDay
                }
            }


            if updates.updateAvailable, let v = updates.latest {
                UpdateRow(text: s.updateAvailable(v.description), updates: updates, strings: s)
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 280)
    }

    // MARK: Rows

    @ViewBuilder
    private func windowRow(_ kind: WindowKind) -> some View {
        let display = model.display(ItemID(provider, kind))
        let offered = status.snapshot?.offers(kind) ?? true
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Long titles (some languages, a budget) wrap instead of being cut off.
                Text(kind == .month ? monthTitle : s.windowTitle(kind)).font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if let p = display.percent(mode: settings.displayMode) {
                    Text("\(p)%").font(.subheadline.monospacedDigit().weight(.semibold))
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            if kind == .month, let split = budgetSplit {
                // Free usage and budget in different colours, so the mix is visible at a glance.
                SplitUsageBar(free: split.free, budget: split.budget)
                    .opacity(model.isStale(provider) ? 0.5 : 1)
                HStack(spacing: 10) {
                    LegendDot(color: SplitUsageBar.freeColor, text: s.legendFree)
                    LegendDot(color: SplitUsageBar.budgetColor, text: s.legendBudget)
                }
            } else {
                UsageBar(fraction: display.percent(mode: settings.displayMode).map { Double($0) / 100 })
                    .opacity(model.isStale(provider) ? 0.5 : 1)
            }
            Group {
                switch display {
                case .value(_, let reset):
                    if let reset { Text(resetText(reset)) } else { EmptyView() }
                case .resetPassed:
                    Text(s.resetNewWindowOnNextUse)
                case .awaitingUpdateAfterReset:
                    Text(s.awaitingAfterReset)
                case .unavailable:
                    Text(offered ? s.unavailable : s.notOffered)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// Reset time plus remaining time for both windows, e.g. "18:40 (in 2h 15m)" or
    /// "Nov 23, 9:00 (in 5d 3h)".
    private func resetText(_ date: Date) -> String {
        let tt = TimeText(settings.appLanguage)
        let remaining = date.timeIntervalSince(model.now)
        return s.resetLine(tt.reset(date, now: model.now),
                           remaining: tt.duration(remaining))
    }

    /// Free and budget parts of the GitHub month bar, when a budget is set.
    private var budgetSplit: (free: Double, budget: Double)? {
        guard provider == .github, let w = status.snapshot?.windows[.month],
              case .value = model.display(ItemID(.github, .month)) else { return nil }
        return BudgetBarSplit.parts(w, budgetUSD: model.githubBudgetUSD, mode: settings.displayMode)
    }

    /// With a budget: remaining/used of the budget alone, and the amount billed against it.
    @ViewBuilder
    private var budgetRow: some View {
        if let budget = model.githubBudgetUSD, let w = status.snapshot?.windows[.month],
           let used = GitHubActionsUsage.budgetPercent(w, budgetUSD: budget), let charged = w.chargedAmount {
            let shown = settings.displayMode == .used ? used : 100 - used
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(s.budgetRowTitle(USDText.format(budget))).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(shown.rounded()))%").font(.subheadline.monospacedDigit().weight(.semibold))
                }
                UsageBar(fraction: shown / 100, color: SplitUsageBar.budgetColor) // same colour as the budget part
                    .opacity(model.isStale(.github) ? 0.5 : 1)
                Text(s.budgetSpent(USDText.money(charged), USDText.format(budget)))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// "Free usage (private repos)", or with the budget the person entered.
    private var monthTitle: String {
        guard let budget = model.githubBudgetUSD else { return s.privateFreeQuota }
        return s.privateFreeQuotaWithBudget(USDText.format(budget))
    }

    // MARK: Notices

    private var noticeText: AnyView? {
        switch provider {
        case .codex:
            guard let e = status.lastError else { return nil }
            let message: String
            switch e {
            case .notFound: message = s.codexNotFound
            case .notSignedIn: message = s.codexNotSignedIn
            case .timedOut: message = s.fetchTimedOut
            case .failed: message = s.fetchFailed
            }
            return AnyView(VStack(alignment: .leading, spacing: 6) {
                Label(status.snapshot != nil ? "\(message) · \(s.showingLastValues)" : message,
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                if e == .notSignedIn {
                    Button(model.codexSigningIn ? s.signingIn : s.signInCodex) { model.signInCodex() }
                        .disabled(model.codexSigningIn)
                        .controlSize(.small)
                }
            })
        case .claude:
            if model.claudeLink != .linked {
                return AnyView(VStack(alignment: .leading, spacing: 6) {
                    Label(s.claudeNotLinked, systemImage: "link").font(.caption).foregroundStyle(.secondary)
                    Button(s.connect) { openSettings() }.controlSize(.small)
                })
            }
            if model.claudeAuth == .signedOut {
                return AnyView(VStack(alignment: .leading, spacing: 6) {
                    Label(s.claudeNotSignedIn, systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(.caption).foregroundStyle(.orange)
                    Button(s.signInClaude) { ClaudeAuth.startLogin() }.controlSize(.small)
                })
            }
            if status.snapshot == nil {
                return AnyView(Text(s.claudeWaiting).font(.caption).foregroundStyle(.secondary))
            }
            return nil
        case .github:
            return AnyView(githubNotice)
        }
    }

    @ViewBuilder
    private var githubNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            if case .value(let used, _) = model.display(ItemID(.github, .month)), used >= 100 {
                Label(model.githubBudgetUSD == nil ? s.freeQuotaUsedUp : s.budgetUsedUp, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
            switch model.githubError {
            case .some(.notConnected):
                Label(s.githubNotConnected, systemImage: "link").font(.caption).foregroundStyle(.secondary)
                Button(s.connect) { openSettings() }.controlSize(.small)
            case .some(.unknownPlan):
                Label(s.githubUnknownPlan, systemImage: "questionmark.circle").font(.caption).foregroundStyle(.secondary)
            case .some(.tooManyRepositories):
                Label(s.githubTooManyRepos, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            case .some(.failed):
                Label(status.snapshot != nil ? "\(s.fetchFailed) · \(s.showingLastValues)" : s.fetchFailed,
                      systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            case .none:
                EmptyView()
            }
            Text("\(s.publicReposFree)\n\(s.githubDelay)").font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if status.isFetching {
                Text(s.refreshing).font(.caption).foregroundStyle(.secondary)
            } else {
                Text(s.lastUpdated(status.snapshot.map {
                    TimeText(settings.appLanguage).clock($0.fetchedAt, now: model.now)
                } ?? s.never))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.manualRefresh(provider) } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help(s.refresh)
                .disabled(status.isFetching)
            Button { openSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help(s.settings)
        }
    }
}

/// Horizontal bar. Nil shows an empty track (no guessed value).
struct UsageBar: View {
    let fraction: Double?
    var color: Color? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                if let fraction {
                    Capsule().fill(color.map { $0.opacity(0.85) } ?? Color.primary.opacity(0.75))
                        .frame(width: max(fraction > 0 ? 4 : 0, geo.size.width * min(1, max(0, fraction))))
                }
            }
        }
        .frame(height: 8)
        .accessibilityValue(fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
    }
}

/// "Version x is available [Update]" — shared by the popover and settings.
struct UpdateRow: View {
    let text: String
    @ObservedObject var updates: UpdateChecker
    let strings: Strings

    var body: some View {
        HStack {
            Label(text, systemImage: "arrow.down.circle")
                .font(.caption)
            Spacer()
            switch updates.installState {
            case .installing:
                Text(strings.updating).font(.caption).foregroundStyle(.secondary)
            case .failed:
                Button(strings.updateNow) { updates.installUpdate() }.controlSize(.small)
            case .idle:
                Button(strings.updateNow) { updates.installUpdate() }.controlSize(.small)
            }
        }
        if updates.installState == .failed {
            Text(strings.updateFailed).font(.caption).foregroundStyle(.orange)
        }
    }
}

/// Short dollar amounts such as "$10" or "$12.5".
enum USDText {
    static func format(_ value: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return "$" + (f.string(from: NSNumber(value: value)) ?? String(value))
    }

    /// Money with cents: "$3.30".
    static func money(_ value: Double) -> String { String(format: "$%.2f", value) }
}

/// Seven bars, one per local day, with buttons to step back and forward a week.
/// Days without data are drawn as an empty outline, never as zero.
struct DailyChart: View {
    let title: String
    let note: String?
    let emptyText: String
    let strings: Strings
    let lang: AppLanguage
    let now: Date
    let values: (Date) -> [(day: Date, percent: Double?)]
    let earliest: () -> String?
    /// Called with the shown days, so data can be loaded on demand.
    var onShow: (([Date]) -> Void)? = nil
    @State private var weeksBack = 0

    /// Seven local calendar days ending at `end`.
    static func days(endingAt end: Date) -> [Date] {
        (0..<7).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Calendar.current.startOfDay(for: end)) }
    }

    private var end: Date {
        Calendar.current.date(byAdding: .day, value: -7 * weeksBack, to: Calendar.current.startOfDay(for: now)) ?? now
    }

    var body: some View {
        let rows = values(end)
        let maxValue = max(10, rows.compactMap(\.percent).max() ?? 0)
        let start = rows.first?.day ?? end
        let canGoBack = earliest().map { DailyUsageLog.dayKey(start) > $0 } ?? false
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title).font(.caption.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button { weeksBack += 1 } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless).disabled(!canGoBack).help(strings.previousWeek)
                // Fixed width so the arrows stay in place while stepping through weeks.
                Text(rangeText(start, end)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 84)
                Button { weeksBack -= 1 } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless).disabled(weeksBack == 0).help(strings.nextWeek)
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(spacing: 3) {
                        Text(row.percent.map(DailyUsageLog.barLabel) ?? "")
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(height: 11)
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(Color.primary.opacity(row.percent == nil ? 0.15 : 0), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.primary.opacity(0.75))
                                .frame(height: row.percent.map { max($0 > 0 ? 2 : 0, 54 * $0 / maxValue) } ?? 0)
                            if row.percent == 0 {
                                // Recorded but nothing used: a thin baseline, unlike days without data.
                                Rectangle().fill(Color.primary.opacity(0.35)).frame(height: 1)
                            }
                        }
                        .frame(height: 54)
                        Text(weekday(row.day))
                            .font(.system(size: 9, weight: Calendar.current.isDate(row.day, inSameDayAs: now) ? .bold : .regular))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .help(row.percent.map { "\(dayText(row.day)): \(String(format: "%.1f", $0))%" } ?? dayText(row.day))
                }
            }
            if let text = rows.allSatisfy({ $0.percent == nil }) ? emptyText : note {
                Text(text).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .task(id: weeksBack) { onShow?(Self.days(endingAt: end)) }
    }

    private func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = lang.locale
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }
    private func weekday(_ d: Date) -> String { formatter("EEEEE").string(from: d) }
    private func dayText(_ d: Date) -> String { formatter("MMMdEEE").string(from: d) }
    private func rangeText(_ a: Date, _ b: Date) -> String {
        let f = formatter("Md")
        return "\(f.string(from: a))–\(f.string(from: b))"
    }
}

/// A bar with two coloured parts from the left: free usage, then budget.
struct SplitUsageBar: View {
    let free: Double
    let budget: Double
    static let freeColor = Color.blue
    static let budgetColor = Color.orange

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                HStack(spacing: 0) {
                    Rectangle().fill(Self.freeColor.opacity(0.85)).frame(width: w * min(1, max(0, free)))
                    Rectangle().fill(Self.budgetColor.opacity(0.85)).frame(width: w * min(1, max(0, budget)))
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 8)
    }
}

struct LegendDot: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.85)).frame(width: 8, height: 8)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
