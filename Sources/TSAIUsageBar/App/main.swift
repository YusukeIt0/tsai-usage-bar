import AppKit
import UsageCore

MainActor.assumeIsolated {
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--render-icons"), i + 1 < args.count {
        IconPreview.run(outputDir: args[i + 1])
        exit(0)
    }
    if let i = args.firstIndex(of: "--render-ui"), i + 1 < args.count {
        UIPreview.run(outputDir: args[i + 1])
        exit(0)
    }
    // CI: checks that the language files shipped in this build are complete.
    if args.contains("--check-languages") {
        guard let dir = LanguageCatalog.bundledDirectory() else {
            print("language files not found")
            exit(1)
        }
        let problems = LanguageCatalog.problems(directory: dir)
        problems.forEach { print($0) }
        print("\(LanguageCatalog.main.languages.count) languages in \(dir.path), \(problems.count) problems")
        exit(problems.isEmpty ? 0 : 1)
    }
    // Developer aid: reads every service once with the real clients.
    if args.contains("--check-sources") {
        exit(SourceCheck.run())
    }
    // Developer aids for checking notification permission across builds.
    if args.contains("--notification-test") || args.contains("--notification-status") {
        NotificationCheck.run(post: args.contains("--notification-test"))
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
