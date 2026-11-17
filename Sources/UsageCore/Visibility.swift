import Foundation

/// Decides which menu bar items appear.
public enum ItemVisibility {
    /// Enabled items, minus windows the provider's latest official reply does not offer
    /// (for example, plans without a 5-hour limit). Never empty, so settings stay reachable.
    public static func visible(enabled: Set<ItemID>, snapshots: [Provider: ProviderSnapshot]) -> [ItemID] {
        let offered = ItemID.allCases.filter { id in
            enabled.contains(id) && snapshots[id.provider]?.offers(id.window) != false
        }
        if !offered.isEmpty { return offered }
        if let firstEnabled = ItemID.allCases.first(where: { enabled.contains($0) }) { return [firstEnabled] }
        return [ItemID(.claude, .fiveHour)]
    }

    /// Providers to keep updating. A provider whose items are all turned off is paused
    /// (no Codex queries, no stored Claude values). A provider that has not reported yet
    /// stays active so its available windows can be learned.
    public static func activeProviders(enabled: Set<ItemID>, initialized: Set<Provider>) -> Set<Provider> {
        Set(Provider.allCases.filter { p in
            !initialized.contains(p) || enabled.contains { $0.provider == p }
        })
    }

    /// The item turned on the first time a provider reports data: its 5-hour window,
    /// or the 7-day window when the plan has no 5-hour limit.
    public static func defaultItem(for provider: Provider, snapshot: ProviderSnapshot) -> ItemID? {
        let reported = snapshot.reportedKinds ?? []
        if reported.contains(.fiveHour) { return ItemID(provider, .fiveHour) }
        if reported.contains(.sevenDay) { return ItemID(provider, .sevenDay) }
        return nil
    }
}
