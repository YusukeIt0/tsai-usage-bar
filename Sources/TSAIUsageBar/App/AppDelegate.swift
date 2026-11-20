import AppKit
import Combine
import SwiftUI
import UsageCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    let model = UsageModel()
    let updates = UpdateChecker()
    let notifier = Notifier()
    private var items: [ItemID: NSStatusItem] = [:]
    private var renderedLabels: [ItemID: String] = [:]
    private let panel = MenuPanel()
    private var popoverProvider: Provider?
    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One status item per menu bar entry. The autosave name keeps the ⌘-drag order.
        for id in ItemID.allCases {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "tsai-usagebar.\(id.key)"
            item.behavior = []
            item.isVisible = false
            item.button?.target = self
            item.button?.action = #selector(itemClicked(_:))
            item.button?.identifier = NSUserInterfaceItemIdentifier(id.key)
            item.button?.imagePosition = .imageOnly
            items[id] = item
        }

        model.codex.onResetCreditArrived = { [weak self] remaining in
            guard let self else { return }
            self.notifier.postResetCreditArrived(remaining: remaining, strings: self.settings.strings)
        }
        notifier.refreshPermission()
        model.onSnapshotArrived = { [weak self] provider, snapshot in
            self?.applyDefaultItem(provider, snapshot)
        }
        for p in Provider.allCases {
            if let snap = model.status(p).snapshot { applyDefaultItem(p, snap) }
        }

        Publishers.Merge(model.objectWillChange, settings.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateItems() }
            .store(in: &cancellables)
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyActiveProviders() }
            .store(in: &cancellables)
        applyActiveProviders()

        updateItems()
        model.start()
        updates.start()
    }

    /// First data from a provider turns on its 5-hour item, or 7-day when 5-hour is not offered.
    private func applyActiveProviders() {
        model.codex.notifyResetCredits = settings.notifyResetCredits
        if model.github.budgetUSD != settings.githubBudgetUSD { model.github.budgetUSD = settings.githubBudgetUSD }
        model.setActiveProviders(ItemVisibility.activeProviders(enabled: settings.enabledItems,
                                                                initialized: settings.initializedProviders))
    }

    private func applyDefaultItem(_ provider: Provider, _ snapshot: ProviderSnapshot) {
        guard !settings.initializedProviders.contains(provider),
              let id = ItemVisibility.defaultItem(for: provider, snapshot: snapshot) else { return }
        settings.enabledItems.insert(id)
        settings.initializedProviders.insert(provider)
    }

    // MARK: Menu bar

    private func updateItems() {
        let snapshots = Dictionary(uniqueKeysWithValues: Provider.allCases.compactMap { p in
            model.status(p).snapshot.map { (p, $0) }
        })
        let visible = Set(ItemVisibility.visible(enabled: settings.enabledItems, snapshots: snapshots))
        for id in ItemID.allCases {
            guard let item = items[id] else { continue }
            let show = visible.contains(id)
            if item.isVisible != show { item.isVisible = show }
            guard show, let button = item.button else { continue }
            let display = model.display(id)
            let label = display.label(id.window, mode: settings.displayMode)
            let fill = display.percent(mode: settings.displayMode)
            let key = "\(label)|\(fill.map(String.init) ?? "-")"
            if renderedLabels[id] != key {
                button.image = IconRenderer.image(provider: id.provider, label: label, fill: fill)
                renderedLabels[id] = key
            }
            let stale = model.isStale(id.provider)
            if button.appearsDisabled != stale { button.appearsDisabled = stale }
            let tip = "\(id.provider.displayName) · \(settings.strings.windowTitle(id.window)) · \(settings.strings.modeCaption(settings.displayMode))"
            if button.toolTip != tip { button.toolTip = tip }
        }
    }

    @objc private func itemClicked(_ sender: NSStatusBarButton) {
        guard let key = sender.identifier?.rawValue,
              let id = ItemID.allCases.first(where: { $0.key == key }) else { return }
        if panel.isShown {
            let same = popoverProvider == id.provider
            panel.close()
            if same { return }
        }
        popoverProvider = id.provider
        let view = PopoverView(provider: id.provider, model: model, settings: settings, updates: updates,
                               openSettings: { [weak self] in
                                   self?.panel.close()
                                   self?.showSettings()
                               },
                               capturePanel: { [weak self] in self?.panel.snapshotPNG() })
        panel.show(view, below: sender) { [weak self] in
            self?.popoverProvider = nil
            self?.model.popoverDidClose()
        }
        model.popoverDidOpen(id.provider)
    }

    // MARK: Settings window

    func showSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(model: model, settings: settings, updates: updates, notifier: notifier))
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
            settings.$language
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.settingsWindow?.title = "TSAI UsageBar – \(self?.settings.strings.settings ?? "")" }
                .store(in: &cancellables)
        }
        settingsWindow?.title = "TSAI UsageBar – \(settings.strings.settings)"
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }
}
