import SwiftUI
import UsageCore

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
