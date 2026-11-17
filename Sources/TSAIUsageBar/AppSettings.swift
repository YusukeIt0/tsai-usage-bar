import Foundation
import ServiceManagement
import UsageCore

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

/// User preferences, stored in UserDefaults so they survive updates and restarts.
@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var enabledItems: Set<ItemID> { didSet { save() } }
    @Published var displayMode: DisplayMode { didSet { save() } }
    @Published var language: LanguageSetting { didSet { save() } }
    /// Providers whose default item has been chosen once (H, or W when H is not offered).
    @Published var initializedProviders: Set<Provider> { didSet { save() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let keys = defaults.stringArray(forKey: "enabledItems")
        enabledItems = Set((keys ?? []).compactMap { k in ItemID.allCases.first { $0.key == k } })
        displayMode = DisplayMode(rawValue: defaults.string(forKey: "displayMode") ?? "") ?? .remaining
        language = LanguageSetting(storedValue: defaults.string(forKey: "language") ?? "") ?? .automatic
        initializedProviders = Set((defaults.stringArray(forKey: "initializedProviders") ?? [])
            .compactMap(Provider.init(rawValue:)))
    }

    var appLanguage: AppLanguage { AppLanguage.resolve(language) }
    var strings: Strings { Strings(appLanguage) }

    private func save() {
        defaults.set(ItemID.allCases.filter { enabledItems.contains($0) }.map(\.key), forKey: "enabledItems")
        defaults.set(displayMode.rawValue, forKey: "displayMode")
        defaults.set(language.storedValue, forKey: "language")
        defaults.set(Provider.allCases.filter { initializedProviders.contains($0) }.map(\.rawValue),
                     forKey: "initializedProviders")
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("TSAI UsageBar: login item change failed: \(error.localizedDescription)")
            }
        }
    }

    var launchAtLoginNeedsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }
}
