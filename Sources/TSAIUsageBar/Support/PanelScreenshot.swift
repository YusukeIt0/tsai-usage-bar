import AppKit
import UsageCore

/// The panel's camera button: copies the panel's picture (see `MenuPanel.snapshotPNG`) to the
/// clipboard and saves it as a PNG where the Mac saves its own screenshots.
@MainActor
enum PanelScreenshot {
    enum Outcome: Equatable {
        case saved(folder: String)
        case notSaved(folder: String)
    }

    /// Copies the PNG to the clipboard and saves it.
    static func save(_ png: Data, service: String) async -> Outcome {
        copy(png)
        let folder = ScreenshotFile.folder(
            location: UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
            home: FileManager.default.homeDirectoryForCurrentUser,
            isDirectory: { url in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            })
        let folderName = FileManager.default.displayName(atPath: folder.path)
        // Off the main thread: the first save into Downloads or Desktop can wait on macOS's
        // folder-access prompt.
        let saved = await Task.detached(priority: .userInitiated) {
            let name = ScreenshotFile.name(service: service, date: Date()) { name in
                FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path)
            }
            return (try? png.write(to: folder.appendingPathComponent(name), options: .withoutOverwriting)) != nil
        }.value
        return saved ? .saved(folder: folderName) : .notSaved(folder: folderName)
    }

    private static func copy(_ png: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        pb.writeObjects([item])
    }
}
