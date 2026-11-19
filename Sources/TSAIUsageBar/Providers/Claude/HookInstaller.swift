import Foundation
import UsageCore

/// Copies the statusLine relay to a stable location so Claude Code keeps working even
/// if the app bundle is moved or replaced during an update.
enum HookInstaller {
    static func installIfNeeded(paths: AppPaths) {
        guard let source = Bundle.main.url(forAuxiliaryExecutable: "tsai-usagebar-hook") else { return }
        let dest = paths.installedHookURL
        let fm = FileManager.default
        if let a = try? Data(contentsOf: source), let b = try? Data(contentsOf: dest), a == b { return }
        do {
            try paths.ensureDirectory()
            try fm.createDirectory(at: paths.hookDirectory, withIntermediateDirectories: true)
            let tmp = paths.hookDirectory.appendingPathComponent(".hook.tmp")
            try? fm.removeItem(at: tmp)
            try fm.copyItem(at: source, to: tmp)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
            if fm.fileExists(atPath: dest.path) {
                _ = try fm.replaceItemAt(dest, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: dest)
            }
        } catch {
            NSLog("TSAI UsageBar: hook install failed: \(error.localizedDescription)")
        }
    }
}
