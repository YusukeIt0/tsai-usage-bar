import AppKit
import SwiftUI
import UsageCore

/// Claude Code's part of its panel: windows, connection notices, daily chart.
struct ClaudePanel: View {
    @ObservedObject var source: ClaudeSource
    @ObservedObject var settings: AppSettings
    let now: Date
    let openSettings: () -> Void

    private var s: Strings { settings.strings }

    var body: some View {
        StandardWindowRows(source: source, settings: settings, now: now)
        if source.linkState != .linked {
            VStack(alignment: .leading, spacing: 6) {
                Label(s.claudeNotLinked, systemImage: "link").font(.caption).foregroundStyle(.secondary)
                Button(s.connect) { openSettings() }.controlSize(.small)
            }
        } else if source.auth == .signedOut {
            VStack(alignment: .leading, spacing: 6) {
                Label(s.claudeNotSignedIn, systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.caption).foregroundStyle(.orange)
                Button(s.signInClaude) { ClaudeAuth.startLogin() }.controlSize(.small)
            }
        } else if source.status.snapshot == nil {
            Text(s.claudeWaiting).font(.caption).foregroundStyle(.secondary)
        }
        WeeklyUsageSection(log: source.daily, offered: source.status.snapshot?.offers(.sevenDay) != false,
                           settings: settings, now: now)
    }
}

/// Claude Code's row in Settings: connect/disconnect the statusLine relay, sign-in state.
struct ClaudeSettingsRow: View {
    @ObservedObject var source: ClaudeSource
    let active: Bool
    @ObservedObject var settings: AppSettings
    /// Shown below the connection rows.
    @Binding var linkError: String?

    private var s: Strings { settings.strings }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Claude Code")
                Spacer()
                switch source.linkState {
                case .linked:
                    Text(active ? s.connected : s.pausedHidden).foregroundStyle(.secondary)
                    Button(s.disconnect) { unlink() }
                case .notLinked:
                    Button(s.connect) { confirmLink() }
                case .replacedByUser:
                    Button(s.connect) { confirmLink() }
                }
            }
            if source.linkState == .replacedByUser {
                Text(s.replacedByUser).font(.caption).foregroundStyle(.secondary)
            }
            switch source.auth {
            case .signedOut:
                HStack {
                    Text(s.claudeNotSignedIn).font(.caption).foregroundStyle(.orange)
                    Spacer()
                    Button(s.signInClaude) { ClaudeAuth.startLogin() }
                }
            case .notInstalled:
                Text(s.claudeNotInstalled).font(.caption).foregroundStyle(.secondary)
            default:
                EmptyView()
            }
        }
    }

    private func confirmLink() {
        linkError = nil
        let link = StatusLineLink(paths: source.paths)
        let alert = NSAlert()
        alert.messageText = s.linkTitle
        alert.informativeText = s.linkMessage(existing: link.existingStatusLineCommand(),
                                              settingsPath: link.settingsURL.path
                                                .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
        alert.addButton(withTitle: s.connect)
        alert.addButton(withTitle: s.cancel)
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try source.link()
        } catch StatusLineLink.LinkError.settingsUnreadable, StatusLineLink.LinkError.settingsNotObject {
            linkError = s.settingsUnreadable
        } catch {
            linkError = s.linkFailed
        }
    }

    private func unlink() {
        linkError = nil
        do { try source.unlink() } catch { linkError = s.linkFailed }
    }
}
