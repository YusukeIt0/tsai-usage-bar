import AppKit
import SwiftUI
import UsageCore

struct SettingsView: View {
    @ObservedObject var model: UsageModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var updates: UpdateChecker
    @ObservedObject var notifier: Notifier
    @State private var linkError: String?
    @State private var launchAtLogin = false
    @State private var budgetText = ""

    private var s: Strings { settings.strings }

    var body: some View {
        Form {
            Section {
                ForEach(ItemID.allCases, id: \.self) { id in
                    itemToggle(id)
                }
            } header: {
                Text(s.menuBarItems)
            } footer: {
                Text("\(s.reorderHint)・\(s.keepOneHint)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker(s.numbers, selection: $settings.displayMode) {
                    Text(s.modeCaption(.remaining)).tag(DisplayMode.remaining)
                    Text(s.modeCaption(.used)).tag(DisplayMode.used)
                }
                .pickerStyle(.segmented)
                Picker(s.language, selection: $settings.language) {
                    Text(s.automatic).tag(LanguageSetting.automatic)
                    ForEach(LanguageCatalog.main.languages) { lang in
                        Text(lang.nativeName).tag(LanguageSetting.fixed(lang.code))
                    }
                }
                Toggle(s.launchAtLogin, isOn: Binding(
                    get: { launchAtLogin },
                    set: { settings.launchAtLogin = $0; launchAtLogin = settings.launchAtLogin }))
                if settings.launchAtLoginNeedsApproval {
                    Text(s.launchAtLoginNeedsApproval).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section(s.connections) {
                codexRow
                resetCreditNotifyRow
                claudeRow
                githubRow
                if let linkError {
                    Text(linkError).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                if updates.updateAvailable, let v = updates.latest {
                    UpdateRow(text: s.updateAvailable(v.description), updates: updates, strings: s)
                } else {
                    HStack {
                        Text("\(s.version) \(AppInfo.version)")
                        Spacer()
                        if updates.checking {
                            Text(s.checkingForUpdates).foregroundStyle(.secondary)
                        } else {
                            if updates.lastChecked != nil, !updates.checkFailed {
                                Text(s.upToDate).foregroundStyle(.secondary)
                            }
                            Button(s.checkForUpdates) { Task { await updates.check() } }
                        }
                    }
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button(s.quit) { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            launchAtLogin = settings.launchAtLogin
            budgetText = settings.githubBudgetUSD.map { USDText.format($0).replacingOccurrences(of: "$", with: "") } ?? ""
            model.claude.refreshLink()
            Task { await model.claude.refreshAuth() }
        }
    }

    // MARK: Items

    private func itemToggle(_ id: ItemID) -> some View {
        let isOn = settings.enabledItems.contains(id)
        let isLast = isOn && settings.enabledItems.count == 1
        let offered = model.status(id.provider).snapshot?.offers(id.window) ?? true
        return VStack(alignment: .leading, spacing: 2) {
            Toggle(s.itemName(id), isOn: Binding(
                get: { isOn },
                set: { on in
                    if on { settings.enabledItems.insert(id) } else if !isLast { settings.enabledItems.remove(id) }
                }))
            .disabled(isLast)
            if !offered {
                Text(s.notOffered).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Connections

    private var codexRow: some View {
        HStack {
            Text("Codex")
            Spacer()
            if !model.isActive(.codex) {
                Text(s.pausedHidden).foregroundStyle(.secondary)
            } else {
            switch model.codex.status.lastError {
            case .some(.notInstalled):
                Text(s.codexNotFound).foregroundStyle(.secondary)
            case .some(.notSignedIn):
                Button(model.codex.signingIn ? s.signingIn : s.signInCodex) { model.codex.signIn() }
                    .disabled(model.codex.signingIn)
            case .some:
                Text(s.fetchFailed).foregroundStyle(.orange)
            case .none:
                Text(model.codex.status.snapshot != nil ? s.connected : s.notConnected).foregroundStyle(.secondary)
            }
            }
        }
    }

    /// Codex reset-credit notifications. Asks macOS for permission when turned on.
    private var resetCreditNotifyRow: some View {
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

    private var claudeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Claude Code")
                Spacer()
                switch model.claude.linkState {
                case .linked:
                    Text(model.isActive(.claude) ? s.connected : s.pausedHidden).foregroundStyle(.secondary)
                    Button(s.disconnect) { unlink() }
                case .notLinked:
                    Button(s.connect) { confirmLink() }
                case .replacedByUser:
                    Button(s.connect) { confirmLink() }
                }
            }
            if model.claude.linkState == .replacedByUser {
                Text(s.replacedByUser).font(.caption).foregroundStyle(.secondary)
            }
            switch model.claude.auth {
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

    private var githubRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("GitHub Actions")
                Spacer()
                if model.github.deviceCode != nil {
                    Button(s.cancel) { model.github.cancelConnect() }
                } else if let login = model.github.login {
                    Text(model.isActive(.github) ? "\(s.connected) (\(login))" : s.pausedHidden).foregroundStyle(.secondary)
                    Button(s.disconnect) { model.github.disconnect() }
                } else {
                    Button(s.connectGitHub) { model.github.connect() }
                }
            }
            if let code = model.github.deviceCode {
                Text(s.githubEnterCode(code)).font(.caption.monospaced()).textSelection(.enabled)
            } else if model.github.connectError != nil {
                Text(s.linkFailed).font(.caption).foregroundStyle(.orange)
            }
            if model.github.login != nil {
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
    }

    /// Empty or zero means no budget. Only plain numbers up to 100,000 USD are accepted.
    private func applyBudget() {
        let t = budgetText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
        if t.isEmpty { settings.githubBudgetUSD = nil; return }
        guard let v = Double(t), v.isFinite, v >= 0, v <= 100_000 else { return }
        settings.githubBudgetUSD = v > 0 ? v : nil
    }

    private func confirmLink() {
        linkError = nil
        let link = StatusLineLink(paths: model.paths)
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
            try model.claude.link()
        } catch StatusLineLink.LinkError.settingsUnreadable, StatusLineLink.LinkError.settingsNotObject {
            linkError = s.settingsUnreadable
        } catch {
            linkError = s.linkFailed
        }
    }

    private func unlink() {
        linkError = nil
        do { try model.claude.unlink() } catch { linkError = s.linkFailed }
    }
}
