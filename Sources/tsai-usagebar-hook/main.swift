import Foundation
import UsageCore

// Relay between Claude Code's statusLine and TSAI UsageBar.
//
//   tsai-usagebar-hook statusline   Read statusLine JSON on stdin, store rate limits,
//                                   then run the user's original status line command.
//   tsai-usagebar-hook link|unlink|status
//
// It stores only rate-limit percentages and reset times. Session, transcript and
// workspace fields are never written anywhere.

let paths = AppPaths()
let args = CommandLine.arguments.dropFirst()

func storeClaudeLimits(from input: Data) {
    guard let windows = try? ClaudeStatusLineParser.parseWindows(input), !windows.isEmpty else { return }
    let url = paths.snapshotURL(.claude)
    let existing = SnapshotStore.load(url)
    let merged = SnapshotStore.merge(windows, into: existing, at: Date())
    if let existing, existing.windows == merged.windows, existing.reportedKinds == merged.reportedKinds,
       merged.fetchedAt.timeIntervalSince(existing.fetchedAt) < 30 {
        return // unchanged and recent: skip the write and the wake-up
    }
    try? paths.ensureDirectory()
    try? SnapshotStore.save(merged, to: url)
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFNotificationName(NotifyName.claudeUpdated as CFString),
                                         nil, nil, true)
}

/// Runs the user's original status line with the same input. Uses posix_spawn and
/// waitpid directly: Foundation's Process adds tens of milliseconds of wait latency.
func runOriginal(_ command: String, input: Data) -> Int32 {
    var fds: [Int32] = [0, 0]
    guard pipe(&fds) == 0 else { return 0 }
    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_adddup2(&actions, fds[0], STDIN_FILENO)
    posix_spawn_file_actions_addclose(&actions, fds[0])
    posix_spawn_file_actions_addclose(&actions, fds[1])
    var pid: pid_t = 0
    let argv: [UnsafeMutablePointer<CChar>?] = [strdup("/bin/sh"), strdup("-c"), strdup(command), nil]
    defer { argv.forEach { free($0) } }
    let rc = posix_spawn(&pid, "/bin/sh", &actions, nil, argv, environ)
    close(fds[0])
    guard rc == 0 else { close(fds[1]); return 0 }
    signal(SIGPIPE, SIG_IGN)
    input.withUnsafeBytes { raw in
        var offset = 0
        while offset < raw.count {
            let n = write(fds[1], raw.baseAddress! + offset, raw.count - offset)
            if n <= 0 { break }
            offset += n
        }
    }
    close(fds[1])
    var status: Int32 = 0
    while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
    return (status & 0x7f) == 0 ? (status >> 8) & 0xff : 1
}

switch args.first {
case "statusline":
    let input = FileHandle.standardInput.readDataToEndOfFile()
    storeClaudeLimits(from: input)
    let link = StatusLineLink(paths: paths)
    if let original = link.originalCommand() {
        exit(runOriginal(original, input: input))
    }
    exit(0)

case "link":
    do {
        try StatusLineLink(paths: paths).link()
        print("linked")
    } catch {
        FileHandle.standardError.write(Data("link failed: \(error)\n".utf8))
        exit(1)
    }

case "unlink":
    do {
        try StatusLineLink(paths: paths).unlink()
        print("unlinked")
    } catch {
        FileHandle.standardError.write(Data("unlink failed: \(error)\n".utf8))
        exit(1)
    }

case "status":
    switch StatusLineLink(paths: paths).state() {
    case .linked: print("linked")
    case .notLinked: print("not-linked")
    case .replacedByUser: print("replaced-by-user")
    }

default:
    FileHandle.standardError.write(Data("usage: tsai-usagebar-hook statusline|link|unlink|status\n".utf8))
    exit(2)
}
