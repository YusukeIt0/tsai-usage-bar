import Foundation
import UsageCore

/// Developer aid: `TSAIUsageBar --check-sources` reads every service once through the real
/// clients (the same read-only requests the app makes) and prints what each source got.
/// Set `TSAI_USAGEBAR_SUPPORT_DIR` to keep the stored values away from the installed app.
/// GitHub then needs a token in that folder; delete a copied token afterwards, and note that
/// a refresh there (within 5 minutes of expiry) would leave the original token outdated.
@MainActor
enum SourceCheck {
    static func run() -> Int32 {
        let model = UsageModel()
        model.claude.reload()
        model.codex.refresh(force: true)
        model.github.refresh(force: true)
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline, model.sources.contains(where: { $0.status.isFetching }) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
        for source in model.sources {
            let s = source.status
            let windows = source.provider.windows.map { k -> String in
                guard let p = source.display(k, now: Date()).percent(mode: .used) else { return "\(k.letter) —" }
                return "\(k.letter) \(p)% used"
            }.joined(separator: ", ")
            let state = s.isFetching ? "still reading" : s.lastError.map { "error \($0)" } ?? "ok"
            let fetched = s.snapshot.map { "values from \($0.fetchedAt)" } ?? "no values"
            print("\(source.provider.displayName): \(state); \(windows); \(fetched)")
        }
        return model.sources.contains(where: { $0.status.isFetching }) ? 1 : 0
    }
}
