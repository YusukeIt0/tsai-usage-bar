import SwiftUI
import UsageCore

/// Codex's part of its panel: windows, read errors, limit-reset credits, daily chart.
struct CodexPanel: View {
    @ObservedObject var source: CodexSource
    @ObservedObject var settings: AppSettings
    let now: Date

    private var s: Strings { settings.strings }

    var body: some View {
        StandardWindowRows(source: source, settings: settings, now: now)
        if let e = source.status.lastError {
            VStack(alignment: .leading, spacing: 6) {
                Label(source.status.snapshot != nil ? "\(message(e)) · \(s.showingLastValues)" : message(e),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                if e == .notSignedIn {
                    Button(source.signingIn ? s.signingIn : s.signInCodex) { source.signIn() }
                        .disabled(source.signingIn)
                        .controlSize(.small)
                }
            }
        }
        if let credits = source.status.snapshot?.resetCredits, credits.available > 0 {
            Divider()
            VStack(alignment: .leading, spacing: 2) {
                Label(s.resetCreditsLine(credits.available), systemImage: "ticket")
                    .font(.caption.weight(.semibold))
                if let expiry = credits.earliestExpiry {
                    Text(s.resetCreditsExpiry(TimeText(settings.appLanguage).reset(expiry, now: now)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        WeeklyUsageSection(log: source.daily, offered: source.status.snapshot?.offers(.sevenDay) != false,
                           settings: settings, now: now)
    }

    private func message(_ e: ProviderError) -> String {
        switch e {
        case .notInstalled: return s.codexNotFound
        case .notSignedIn: return s.codexNotSignedIn
        case .timedOut: return s.fetchTimedOut
        case .failed, .unknownPlan, .tooManyRepositories: return s.fetchFailed
        }
    }
}

/// Codex's row in Settings: connection state and sign-in.
struct CodexSettingsRow: View {
    @ObservedObject var source: CodexSource
    let active: Bool
    @ObservedObject var settings: AppSettings

    private var s: Strings { settings.strings }

    var body: some View {
        HStack {
            Text("Codex")
            Spacer()
            if !active {
                Text(s.pausedHidden).foregroundStyle(.secondary)
            } else {
                switch source.status.lastError {
                case .some(.notInstalled):
                    Text(s.codexNotFound).foregroundStyle(.secondary)
                case .some(.notSignedIn):
                    Button(source.signingIn ? s.signingIn : s.signInCodex) { source.signIn() }
                        .disabled(source.signingIn)
                case .some:
                    Text(s.fetchFailed).foregroundStyle(.orange)
                case .none:
                    Text(source.status.snapshot != nil ? s.connected : s.notConnected).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Codex reset-credit notifications. Asks macOS for permission when turned on.
struct ResetCreditNotifyRow: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var notifier: Notifier

    private var s: Strings { settings.strings }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(s.notifyResetCredits, isOn: Binding(
                get: { settings.notifyResetCredits },
                set: { on in
                    settings.notifyResetCredits = on
                    if on, notifier.permission != .allowed { notifier.requestPermission() }
                }))
                .font(.caption)
            if settings.notifyResetCredits, notifier.permission == .denied {
                HStack {
                    Text(s.notificationsDenied).font(.caption).foregroundStyle(.orange)
                    Spacer()
                    Button(s.openSystemSettings) { notifier.openSystemSettings() }.controlSize(.small)
                }
            }
        }
        .onAppear { notifier.refreshPermission() }
    }
}
