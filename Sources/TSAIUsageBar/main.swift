import AppKit

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
