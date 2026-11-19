import SwiftUI
import UsageCore

/// Small panel for one provider. The service's own part (windows, notices, extra sections)
/// comes from its folder under Providers; this view adds the shared header and footer.
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

            switch provider {
            case .claude: ClaudePanel(source: model.claude, settings: settings, now: model.now, openSettings: openSettings)
            case .codex: CodexPanel(source: model.codex, settings: settings, now: model.now)
            case .github: GitHubPanel(source: model.github, settings: settings, now: model.now, openSettings: openSettings)
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
