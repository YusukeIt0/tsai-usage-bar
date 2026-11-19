import SwiftUI
import UsageCore

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
