import SwiftUI
import UsageCore

/// One window in a panel: title, percent, bar, and reset or status text.
/// `bar` replaces the standard bar (GitHub draws free usage and budget in two colours).
struct WindowRow<Bar: View>: View {
    let kind: WindowKind
    let title: String
    let display: WindowDisplay
    let offered: Bool
    let stale: Bool
    @ObservedObject var settings: AppSettings
    let now: Date
    @ViewBuilder var bar: () -> Bar

    private var s: Strings { settings.strings }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Long titles (some languages, a budget) wrap instead of being cut off.
                Text(title).font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if let p = display.percent(mode: settings.displayMode) {
                    Text("\(p)%").font(.subheadline.monospacedDigit().weight(.semibold))
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            bar()
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
        let remaining = date.timeIntervalSince(now)
        return s.resetLine(tt.reset(date, now: now), remaining: tt.duration(remaining))
    }
}

extension WindowRow where Bar == AnyView {
    /// The standard bar.
    init(kind: WindowKind, title: String, display: WindowDisplay, offered: Bool, stale: Bool,
         settings: AppSettings, now: Date) {
        let mode = settings.displayMode
        self.init(kind: kind, title: title, display: display, offered: offered, stale: stale, settings: settings, now: now) {
            AnyView(UsageBar(fraction: display.percent(mode: mode).map { Double($0) / 100 })
                .opacity(stale ? 0.5 : 1))
        }
    }
}

/// Window rows of a source with the standard title and bar.
struct StandardWindowRows<Source: UsageSource>: View {
    @ObservedObject var source: Source
    @ObservedObject var settings: AppSettings
    let now: Date

    var body: some View {
        ForEach(source.provider.windows, id: \.self) { kind in
            WindowRow(kind: kind, title: settings.strings.windowTitle(kind), display: source.display(kind, now: now),
                      offered: source.status.snapshot?.offers(kind) ?? true, stale: source.status.isStale,
                      settings: settings, now: now)
        }
    }
}

/// Per-day share of the 7-day window (services whose history the app records).
struct WeeklyUsageSection: View {
    let log: DailyUsageLog
    let offered: Bool
    @ObservedObject var settings: AppSettings
    let now: Date

    var body: some View {
        if offered {
            Divider()
            DailyChart(title: settings.strings.dailyWeeklyTitle, note: nil, emptyText: settings.strings.dailyNoData,
                       strings: settings.strings, lang: settings.appLanguage, now: now) { end in
                log.values(endingAt: end)
            } earliest: {
                log.firstDay
            }
        }
    }
}
