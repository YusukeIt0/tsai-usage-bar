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
                CodexSettingsRow(source: model.codex, active: model.isActive(.codex), settings: settings)
                ResetCreditNotifyRow(settings: settings, notifier: notifier)
                ClaudeSettingsRow(source: model.claude, active: model.isActive(.claude), settings: settings, linkError: $linkError)
                GitHubSettingsRow(source: model.github, active: model.isActive(.github), settings: settings)
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
}
