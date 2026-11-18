import AppKit
import UsageCore

/// Developer aid: `TSAIUsageBar --render-icons <dir>` writes the menu bar icons on light
/// and dark backgrounds at 2x so their legibility can be checked without the menu bar.
@MainActor
enum IconPreview {
    static func run(outputDir: String) {
        // Each service with its own letters, as in the menu bar.
        func labels(_ p: Provider) -> [(String, Int?)] {
            p == .github
                ? [("M100%", 100), ("M75%", 75), ("M42%", 42), ("M18%", 18), ("M5%", 5), ("M0%", 0), ("M—", nil)]
                : [("H100%", 100), ("H75%", 75), ("W42%", 42), ("H18%", 18), ("W5%", 5), ("H0%", 0), ("H—", nil)]
        }
        for (name, bg, fg) in [("light", NSColor(white: 0.93, alpha: 1), NSColor.black),
                               ("dark", NSColor(white: 0.17, alpha: 1), NSColor.white)] {
            let rows = Provider.allCases.map { p in labels(p).map { IconRenderer.image(provider: p, label: $0.0, fill: $0.1) } }
            let gap: CGFloat = 8
            let width = rows.map { $0.reduce(gap) { $0 + $1.size.width + gap } }.max() ?? 100
            let height = CGFloat(rows.count) * (IconRenderer.height + 6) + 6
            let scale: CGFloat = 4
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = NSSize(width: width, height: height)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            bg.setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
            for (r, row) in rows.enumerated() {
                var x = gap
                let y = height - CGFloat(r + 1) * (IconRenderer.height + 6)
                for img in row {
                    // Tint the template like the menu bar does.
                    let tinted = NSImage(size: img.size, flipped: false) { rect in
                        img.draw(in: rect)
                        fg.withAlphaComponent(0.85).set()
                        rect.fill(using: .sourceAtop)
                        return true
                    }
                    tinted.draw(in: NSRect(x: x, y: y, width: img.size.width, height: img.size.height))
                    x += img.size.width + gap
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            let url = URL(fileURLWithPath: outputDir).appendingPathComponent("icons-\(name).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
}

import SwiftUI

/// Developer aid: `TSAIUsageBar --render-ui <dir>` writes the popover and settings screens
/// in Japanese and English using the values currently stored on this Mac.
@MainActor
enum UIPreview {
    static func run(outputDir: String) {
        let defaults = UserDefaults(suiteName: "tsai-usagebar-preview")!
        defaults.removePersistentDomain(forName: "tsai-usagebar-preview")
        let settings = AppSettings(defaults: defaults)
        settings.enabledItems = [ItemID(.claude, .fiveHour), ItemID(.codex, .sevenDay)]
        let model = UsageModel()
        let updates = UpdateChecker(defaults: defaults)
        for lang in AppLanguage.allCases {
            let setting = LanguageSetting.fixed(lang)
            settings.language = setting
            for appearance in ["light", "dark"] {
                let scheme: ColorScheme = appearance == "light" ? .light : .dark
                for p in Provider.allCases {
                    save(PopoverView(provider: p, model: model, settings: settings, updates: updates, openSettings: {}),
                         scheme: scheme, to: "\(outputDir)/popover-\(p.rawValue)-\(lang.rawValue)-\(appearance).png")
                }
            }
            save(SettingsView(model: model, settings: settings, updates: updates, notifier: Notifier()), scheme: .light, to: "\(outputDir)/settings-\(lang.rawValue).png")
        }
    }

    static func save<V: View>(_ view: V, scheme: ColorScheme, to path: String) {
        let content = view
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, scheme)
        let r = ImageRenderer(content: content)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
