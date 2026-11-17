import AppKit
import UsageCore

/// Draws a provider silhouette with the label cut out of it, as a template image.
/// Template images follow light/dark menu bars and the highlighted state automatically,
/// and the cut-out text always has the menu bar's own contrast against the silhouette.
@MainActor
enum IconRenderer {
    static let height: CGFloat = 18
    private static var cache: [String: NSImage] = [:]

    static func image(provider: Provider, label: String) -> NSImage {
        let key = "\(provider.rawValue)|\(label)"
        if let img = cache[key] { return img }
        let img = render(provider: provider, label: label)
        if cache.count > 64 { cache.removeAll() }
        cache[key] = img
        return img
    }

    static func font() -> NSFont {
        let base = NSFont.systemFont(ofSize: 10.5, weight: .heavy, width: .condensed)
        let desc = base.fontDescriptor.addingAttributes([
            .featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]],
        ])
        return NSFont(descriptor: desc, size: 10.5) ?? base
    }

    static func textSize(_ label: String) -> CGSize {
        (label as NSString).size(withAttributes: [.font: font()])
    }

    static func render(provider: Provider, label: String) -> NSImage {
        let text = textSize(label)
        let shape: (CGFloat) -> (NSBezierPath, CGRect) = provider == .claude ? claudeShape : codexShape
        // Size the silhouette to the label; "H100%" must fit without clipping.
        let width = ceil(provider == .claude ? text.width + 13 : text.width + 12)
        let (path, textBox) = shape(width)
        let img = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            NSColor.black.setFill()
            path.fill()
            ctx.setBlendMode(.destinationOut)
            let origin = CGPoint(x: textBox.midX - text.width / 2,
                                 y: textBox.midY - text.height / 2)
            (label as NSString).draw(at: origin, withAttributes: [.font: font(), .foregroundColor: NSColor.black])
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "\(provider.displayName) \(label)"
        return img
    }

    /// Pixel creature: block body, short side arms, four legs.
    static func claudeShape(_ w: CGFloat) -> (NSBezierPath, CGRect) {
        let arm: CGFloat = 2.5
        let bodyX = arm, bodyW = w - arm * 2
        let bodyTop: CGFloat = 0.5, bodyBottom: CGFloat = 14.5
        let path = NSBezierPath()
        path.append(NSBezierPath(roundedRect: CGRect(x: bodyX, y: bodyTop, width: bodyW, height: bodyBottom - bodyTop),
                                 xRadius: 1, yRadius: 1))
        // Arms
        path.append(NSBezierPath(roundedRect: CGRect(x: 0, y: 8.5, width: arm + 1, height: 3.5), xRadius: 0.6, yRadius: 0.6))
        path.append(NSBezierPath(roundedRect: CGRect(x: w - arm - 1, y: 8.5, width: arm + 1, height: 3.5), xRadius: 0.6, yRadius: 0.6))
        // Legs at the reference proportions
        let legW: CGFloat = 2.3
        for f in [0.08, 0.25, 0.65, 0.82] as [CGFloat] {
            let x = bodyX + bodyW * f
            path.append(NSBezierPath(roundedRect: CGRect(x: x, y: bodyBottom - 1, width: legW, height: 18 - bodyBottom + 0.5),
                                     xRadius: 0.5, yRadius: 0.5))
        }
        let textBox = CGRect(x: bodyX, y: bodyTop, width: bodyW, height: bodyBottom - bodyTop)
        return (path, textBox)
    }

    /// Cloud: a wide rounded base with two bumps on top.
    static func codexShape(_ w: CGFloat) -> (NSBezierPath, CGRect) {
        let path = NSBezierPath()
        path.append(NSBezierPath(roundedRect: CGRect(x: 0, y: 5, width: w, height: 12.5), xRadius: 6, yRadius: 6))
        path.append(NSBezierPath(ovalIn: CGRect(x: w * 0.36 - 6.5, y: 0.5, width: 13, height: 13)))
        path.append(NSBezierPath(ovalIn: CGRect(x: w * 0.66 - 5.5, y: 2, width: 11, height: 11)))
        path.windingRule = .nonZero
        let textBox = CGRect(x: 0, y: 5, width: w, height: 11)
        return (path, textBox)
    }
}
