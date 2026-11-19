import SwiftUI
import UsageCore

/// GitHub Actions' part of its panel: the month window (split by colour with a budget),
/// the budget on its own, notices, and the per-day chart.
struct GitHubPanel: View {
    @ObservedObject var source: GitHubSource
    @ObservedObject var settings: AppSettings
    let now: Date
    let openSettings: () -> Void

    private var s: Strings { settings.strings }
    private var stale: Bool { source.status.isStale }

    var body: some View {
        ForEach(source.provider.windows, id: \.self) { kind in
            WindowRow(kind: kind, title: kind == .month ? monthTitle : s.windowTitle(kind),
                      display: source.display(kind, now: now), offered: source.status.snapshot?.offers(kind) ?? true,
                      stale: stale, settings: settings, now: now) {
                if kind == .month, let split = budgetSplit {
                    // Free usage and budget in different colours, so the mix is visible at a glance.
                    SplitUsageBar(free: split.free, budget: split.budget)
                        .opacity(stale ? 0.5 : 1)
                    HStack(spacing: 10) {
                        LegendDot(color: SplitUsageBar.freeColor, text: s.legendFree)
                        LegendDot(color: SplitUsageBar.budgetColor, text: s.legendBudget)
                    }
                } else {
                    UsageBar(fraction: source.display(kind, now: now).percent(mode: settings.displayMode).map { Double($0) / 100 })
                        .opacity(stale ? 0.5 : 1)
                }
            }
        }
        budgetRow
        notice
        if source.login != nil {
            Divider()
            DailyChart(title: s.dailyMonthlyTitle, note: s.githubDailyNote,
                       emptyText: source.dailyFailed && !source.dailyLoading ? s.fetchFailed : s.loading,
                       strings: s, lang: settings.appLanguage, now: now) { end in
                DailyChart.days(endingAt: end).map { d in
                    (d, source.daily.percent(DailyUsageLog.dayKey(d), budgetUSD: source.budgetUSD))
                }
            } earliest: {
                GitHubDailyCache.utcKey(Date().addingTimeInterval(-728 * 86_400))
            } onShow: { days in
                source.loadDays(days.map { DailyUsageLog.dayKey($0) })
            }
        }
    }

    /// "Free usage (private repos)", or with the budget the person entered.
    private var monthTitle: String {
        guard let budget = source.budgetUSD else { return s.privateFreeQuota }
        return s.privateFreeQuotaWithBudget(USDText.format(budget))
    }

    /// Free and budget parts of the month bar, when a budget is set.
    private var budgetSplit: (free: Double, budget: Double)? {
        guard let w = source.status.snapshot?.windows[.month], case .value = source.display(.month, now: now) else { return nil }
        return BudgetBarSplit.parts(w, budgetUSD: source.budgetUSD, mode: settings.displayMode)
    }

    /// With a budget: remaining/used of the budget alone, and the amount billed against it.
    @ViewBuilder
    private var budgetRow: some View {
        if let budget = source.budgetUSD, let w = source.status.snapshot?.windows[.month],
           let used = GitHubActionsUsage.budgetPercent(w, budgetUSD: budget), let charged = w.chargedAmount {
            let shown = settings.displayMode == .used ? used : 100 - used
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(s.budgetRowTitle(USDText.format(budget))).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(shown.rounded()))%").font(.subheadline.monospacedDigit().weight(.semibold))
                }
                UsageBar(fraction: shown / 100, color: SplitUsageBar.budgetColor) // same colour as the budget part
                    .opacity(stale ? 0.5 : 1)
                Text(s.budgetSpent(USDText.money(charged), USDText.format(budget)))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var notice: some View {
        VStack(alignment: .leading, spacing: 6) {
            if case .value(let used, _) = source.display(.month, now: now), used >= 100 {
                Label(source.budgetUSD == nil ? s.freeQuotaUsedUp : s.budgetUsedUp, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
            switch source.status.lastError {
            case .some(.notSignedIn):
                Label(s.githubNotConnected, systemImage: "link").font(.caption).foregroundStyle(.secondary)
                Button(s.connect) { openSettings() }.controlSize(.small)
            case .some(.unknownPlan):
                Label(s.githubUnknownPlan, systemImage: "questionmark.circle").font(.caption).foregroundStyle(.secondary)
            case .some(.tooManyRepositories):
                Label(s.githubTooManyRepos, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            case .some(.failed), .some(.timedOut), .some(.notInstalled):
                Label(source.status.snapshot != nil ? "\(s.fetchFailed) · \(s.showingLastValues)" : s.fetchFailed,
                      systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            case .none:
                EmptyView()
            }
            if source.login != nil {
                Button(s.setBudgetOnGitHub) { NSWorkspace.shared.open(GitHubSource.budgetsURL) }
                    .controlSize(.small)
            }
            Text("\(s.publicReposFree)\n\(s.githubDelay)").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// GitHub's row in Settings: connect/disconnect and the optional monthly budget.
struct GitHubSettingsRow: View {
    @ObservedObject var source: GitHubSource
    let active: Bool
    @ObservedObject var settings: AppSettings
    @State private var budgetText = ""

    private var s: Strings { settings.strings }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("GitHub Actions")
                Spacer()
                if source.deviceCode != nil {
                    Button(s.cancel) { source.cancelConnect() }
                } else if let login = source.login {
                    Text(active ? "\(s.connected) (\(login))" : s.pausedHidden).foregroundStyle(.secondary)
                    Button(s.disconnect) { source.disconnect() }
                } else {
                    Button(s.connectGitHub) { source.connect() }
                }
            }
            if let code = source.deviceCode {
                Text(s.githubEnterCode(code)).font(.caption.monospaced()).textSelection(.enabled)
            } else if source.connectError != nil {
                Text(s.linkFailed).font(.caption).foregroundStyle(.orange)
            }
            if source.login != nil {
                HStack {
                    Text(s.monthlyBudget).font(.caption)
                    Spacer()
                    Text("$").foregroundStyle(.secondary)
                    TextField("", text: $budgetText, prompt: Text("0"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                        .onSubmit { applyBudget() }
                        .onChange(of: budgetText) { _, _ in applyBudget() }
                }
                Text(s.budgetHelp).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            budgetText = settings.githubBudgetUSD.map { USDText.format($0).replacingOccurrences(of: "$", with: "") } ?? ""
        }
    }

    /// Empty or zero means no budget. Only plain numbers up to 100,000 USD are accepted.
    private func applyBudget() {
        let t = budgetText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
        if t.isEmpty { settings.githubBudgetUSD = nil; return }
        guard let v = Double(t), v.isFinite, v >= 0, v <= 100_000 else { return }
        settings.githubBudgetUSD = v > 0 ? v : nil
    }
}
