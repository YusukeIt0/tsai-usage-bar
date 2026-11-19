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

            if provider == .github, model.github.login != nil {
                Divider()
                DailyChart(title: s.dailyMonthlyTitle, note: s.githubDailyNote,
                           emptyText: model.github.dailyFailed && !model.github.dailyLoading ? s.fetchFailed : s.loading,
                           strings: s, lang: settings.appLanguage, now: model.now) { end in
                    DailyChart.days(endingAt: end).map { d in
                        (d, model.github.daily.percent(DailyUsageLog.dayKey(d), budgetUSD: model.github.budgetUSD))
                    }
                } earliest: {
                    GitHubDailyCache.utcKey(Date().addingTimeInterval(-728 * 86_400))
                } onShow: { days in
                    model.github.loadDays(days.map { DailyUsageLog.dayKey($0) })
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
                    (model.dailyLog(provider) ?? DailyUsageLog()).values(endingAt: end)
                } earliest: {
                    model.dailyLog(provider)?.firstDay
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
        return BudgetBarSplit.parts(w, budgetUSD: model.github.budgetUSD, mode: settings.displayMode)
    }

    /// With a budget: remaining/used of the budget alone, and the amount billed against it.
    @ViewBuilder
    private var budgetRow: some View {
        if let budget = model.github.budgetUSD, let w = status.snapshot?.windows[.month],
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
        guard let budget = model.github.budgetUSD else { return s.privateFreeQuota }
        return s.privateFreeQuotaWithBudget(USDText.format(budget))
    }

    // MARK: Notices

    private var noticeText: AnyView? {
        switch provider {
        case .codex:
            guard let e = status.lastError else { return nil }
            let message: String
            switch e {
            case .notInstalled: message = s.codexNotFound
            case .notSignedIn: message = s.codexNotSignedIn
            case .timedOut: message = s.fetchTimedOut
            case .failed, .unknownPlan, .tooManyRepositories: message = s.fetchFailed
            }
            return AnyView(VStack(alignment: .leading, spacing: 6) {
                Label(status.snapshot != nil ? "\(message) · \(s.showingLastValues)" : message,
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                if e == .notSignedIn {
                    Button(model.codex.signingIn ? s.signingIn : s.signInCodex) { model.codex.signIn() }
                        .disabled(model.codex.signingIn)
                        .controlSize(.small)
                }
            })
        case .claude:
            if model.claude.linkState != .linked {
                return AnyView(VStack(alignment: .leading, spacing: 6) {
                    Label(s.claudeNotLinked, systemImage: "link").font(.caption).foregroundStyle(.secondary)
                    Button(s.connect) { openSettings() }.controlSize(.small)
                })
            }
            if model.claude.auth == .signedOut {
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
                Label(model.github.budgetUSD == nil ? s.freeQuotaUsedUp : s.budgetUsedUp, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
            switch model.github.status.lastError {
            case .some(.notSignedIn):
                Label(s.githubNotConnected, systemImage: "link").font(.caption).foregroundStyle(.secondary)
                Button(s.connect) { openSettings() }.controlSize(.small)
            case .some(.unknownPlan):
                Label(s.githubUnknownPlan, systemImage: "questionmark.circle").font(.caption).foregroundStyle(.secondary)
            case .some(.tooManyRepositories):
                Label(s.githubTooManyRepos, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            case .some(.failed), .some(.timedOut), .some(.notInstalled):
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
