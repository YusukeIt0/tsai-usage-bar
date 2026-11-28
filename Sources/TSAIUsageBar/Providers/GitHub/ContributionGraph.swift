import SwiftUI
import UsageCore

/// The account's contribution graph in GitHub's style, 13 weeks at a time with ◀ ▶ to step
/// through the last year. Hovering a square shows its count and date the way GitHub does.
struct ContributionGraph: View {
    let calendar: ContributionCalendar
    let strings: Strings
    let lang: AppLanguage
    @Environment(\.colorScheme) private var scheme
    @State private var page = 0
    @State private var hovered: Hover?
    @State private var bubbleWidth: CGFloat = 0

    static let cell: CGFloat = 14
    static let gap: CGFloat = 3
    private static let labelWidth: CGFloat = 26
    private static let monthRow: CGFloat = 13

    private struct Hover: Equatable {
        var day: ContributionDay
        var column: Int
    }

    /// Developer aid for `--render-ui`: a date ("yyyy-MM-dd") on the latest page to draw as hovered.
    nonisolated(unsafe) static var previewHoverDate: String?

    init(calendar: ContributionCalendar, strings: Strings, lang: AppLanguage) {
        self.calendar = calendar
        self.strings = strings
        self.lang = lang
        if let date = Self.previewHoverDate {
            for (column, week) in calendar.page(0).enumerated() {
                if let day = week.first(where: { $0.date == date }) { _hovered = State(initialValue: Hover(day: day, column: column)) }
            }
        }
    }

    var body: some View {
        let weeks = calendar.page(page)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(strings.contributionsTitle).font(.caption.weight(.semibold))
                Spacer()
                Button { page += 1; hovered = nil } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless).disabled(page >= calendar.pageCount - 1).help(strings.earlier)
                Text(rangeText(weeks)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 84)
                Button { page -= 1; hovered = nil } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless).disabled(page == 0).help(strings.later)
            }
            HStack(alignment: .top, spacing: 4) {
                weekdayLabels
                VStack(alignment: .leading, spacing: 2) {
                    monthLabels(weeks)
                    grid(weeks)
                        .overlay(alignment: .topLeading) { bubble }
                }
            }
            HStack(spacing: 3) {
                Text(strings.contributionsTotal(ContributionCalendar.total(weeks)))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Text(strings.contributionsLess).font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { square(level: $0, size: 9) }
                Text(strings.contributionsMore).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .zIndex(1) // the bubble may reach above this section
    }

    // MARK: Parts

    /// Mon, Wed and Fri, as on GitHub, in the app's language.
    private var weekdayLabels: some View {
        let names = utcFormatter("EEE").shortStandaloneWeekdaySymbols ?? []
        return VStack(alignment: .leading, spacing: Self.gap) {
            Color.clear.frame(height: Self.monthRow + 2 - Self.gap)
            ForEach(0..<7, id: \.self) { i in
                Text([1, 3, 5].contains(i) && i < names.count ? names[i] : "")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: Self.labelWidth, height: Self.cell, alignment: .leading)
            }
        }
    }

    private func monthLabels(_ weeks: [[ContributionDay]]) -> some View {
        let names = utcFormatter("MMM").shortStandaloneMonthSymbols ?? []
        return ZStack(alignment: .topLeading) {
            Color.clear.frame(height: Self.monthRow)
            ForEach(ContributionCalendar.monthLabels(weeks), id: \.column) { label in
                Text(label.month - 1 < names.count ? names[label.month - 1] : "")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(x: CGFloat(label.column) * (Self.cell + Self.gap))
            }
        }
    }

    private func grid(_ weeks: [[ContributionDay]]) -> some View {
        HStack(alignment: .top, spacing: Self.gap) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { column, week in
                VStack(spacing: Self.gap) {
                    ForEach(0..<7, id: \.self) { weekday in
                        if let day = week.first(where: { $0.weekday == weekday }) {
                            square(level: day.level, size: Self.cell)
                                .onHover { inside in
                                    if inside { hovered = Hover(day: day, column: column) }
                                    else if hovered?.day == day { hovered = nil }
                                }
                        } else {
                            Color.clear.frame(width: Self.cell, height: Self.cell)
                        }
                    }
                }
            }
        }
    }

    private func square(level: Int, size: CGFloat) -> some View {
        let palette = scheme == .dark ? Self.darkPalette : Self.lightPalette
        return RoundedRectangle(cornerRadius: size * 0.2)
            .fill(palette[min(max(level, 0), 4)])
            .overlay(RoundedRectangle(cornerRadius: size * 0.2)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
            .frame(width: size, height: size)
    }

    /// GitHub-style dark bubble above the hovered square, kept inside the panel.
    @ViewBuilder
    private var bubble: some View {
        if let h = hovered {
            let weekday = CGFloat(h.day.weekday)
            let centre = CGFloat(h.column) * (Self.cell + Self.gap) + Self.cell / 2
            let gridWidth = CGFloat(Self.weeksShown) * (Self.cell + Self.gap) - Self.gap
            // The panel's content starts this far left of the grid.
            let leftRoom = Self.labelWidth + 4
            let x = min(max(centre - bubbleWidth / 2, -leftRoom), gridWidth - bubbleWidth)
            Text(text(h.day))
                .font(.caption)
                .foregroundStyle(.white)
                .fixedSize()
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(scheme == .dark ? Color(hex: 0x3d444d) : Color(hex: 0x25292e)))
                .background(GeometryReader { g in Color.clear.onAppear { bubbleWidth = g.size.width }
                    .onChange(of: g.size.width) { _, w in bubbleWidth = w } })
                .offset(x: x, y: weekday * (Self.cell + Self.gap) - 30)
                .allowsHitTesting(false)
                .opacity(bubbleWidth > 0 ? 1 : 0)
        }
    }

    private static var weeksShown: Int { ContributionCalendar.weeksPerPage }

    // MARK: Text

    private func text(_ day: ContributionDay) -> String {
        let date = day.utcDate.map { utcFormatter("MMMMd").string(from: $0) } ?? day.date
        return strings.contributionsOnDay(day.count, date: date)
    }

    private func rangeText(_ weeks: [[ContributionDay]]) -> String {
        guard let a = weeks.first?.first?.utcDate, let b = weeks.last?.last?.utcDate else { return "" }
        let f = utcFormatter("Md")
        return "\(f.string(from: a))–\(f.string(from: b))"
    }

    /// Calendar dates from GitHub are formatted as they are, without moving them to another time zone.
    private func utcFormatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = lang.locale
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    // MARK: Colours (GitHub's contribution palettes)

    static let lightPalette: [Color] = [0xeff2f5, 0xaceebb, 0x4ac26b, 0x2da44e, 0x116329].map(Color.init(hex:))
    static let darkPalette: [Color] = [0x151b23, 0x033a16, 0x196c2e, 0x2ea043, 0x56d364].map(Color.init(hex:))
}

extension Color {
    init(hex: Int) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: 1)
    }
}
