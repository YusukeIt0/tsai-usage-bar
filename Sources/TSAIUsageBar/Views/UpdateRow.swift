import SwiftUI
import UsageCore

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
