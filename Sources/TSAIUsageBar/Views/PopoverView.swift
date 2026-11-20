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
    /// PNG of the panel as shown, from the window that holds it.
    var capturePanel: () -> Data? = { nil }

    /// Result of the last camera press, shown in place of "Updated" for a moment.
    @State private var screenshot: PanelScreenshot.Outcome?
    @State private var clearScreenshot: Task<Void, Never>?

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
            if let screenshot {
                Text(screenshotText(screenshot))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if status.isFetching {
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
            Button { takeScreenshot() } label: { Image(systemName: screenshotIcon) }
                .buttonStyle(.borderless)
                .help(s.screenshot)
            Button { openSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help(s.settings)
        }
    }

    private var screenshotIcon: String {
        switch screenshot {
        case nil: "camera"
        case .saved: "checkmark"
        case .notSaved: "exclamationmark.triangle"
        }
    }

    private func screenshotText(_ outcome: PanelScreenshot.Outcome) -> String {
        switch outcome {
        case .saved(let folder): s.screenshotSaved(folder)
        case .notSaved(let folder): s.screenshotNotSaved(folder)
        }
    }

    /// Captures the panel as it looks now (before the footer changes to show the result).
    private func takeScreenshot() {
        guard let png = capturePanel() else { return }
        Task {
            let outcome = await PanelScreenshot.save(png, service: provider.displayName)
            screenshot = outcome
            clearScreenshot?.cancel()
            clearScreenshot = Task {
                try? await Task.sleep(for: .seconds(3))
                if !Task.isCancelled { screenshot = nil }
            }
        }
    }
}
