import AppKit
import UsageCore

/// Draws a provider silhouette as a template image that fills like a battery gauge:
/// the left part, proportional to the shown percentage, is solid and the rest is faint.
/// The label is cut out of the solid part and drawn solid over the faint part, so it keeps
/// full contrast everywhere. Template images follow light/dark menu bars automatically.
@MainActor
enum IconRenderer {
    static let height: CGFloat = 18
    /// Opacity of the unfilled part of the silhouette.
    static let emptyAlpha: CGFloat = 0.32
    private static var cache: [String: NSImage] = [:]

    /// `fill` is 0...100, or nil when there is no value (whole silhouette faint).
    static func image(provider: Provider, label: String, fill: Int?) -> NSImage {
        let key = "\(provider.rawValue)|\(label)|\(fill.map(String.init) ?? "-")"
        if let img = cache[key] { return img }
        let img = render(provider: provider, label: label, fill: fill)
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

    static func render(provider: Provider, label: String, fill: Int?) -> NSImage {
        let text = textSize(label)
        let shape: (CGFloat) -> (NSBezierPath, CGRect)
        let padding: CGFloat
        switch provider {
        case .claude: shape = claudeShape; padding = 13
        case .codex: shape = codexShape; padding = 12
        case .github: shape = githubShape; padding = 10
        }
        // Size the silhouette to the label; "H100%" must fit without clipping.
        let width = ceil(text.width + padding)
        let (path, textBox) = shape(width)
        let fraction = CGFloat(min(100, max(0, fill ?? 0))) / 100
        let img = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let origin = CGPoint(x: textBox.midX - text.width / 2, y: textBox.midY - text.height / 2)
            let attrs: [NSAttributedString.Key: Any] = [.font: font(), .foregroundColor: NSColor.black]
            let filledRect = CGRect(x: 0, y: 0, width: width * fraction, height: height)
            let emptyRect = CGRect(x: width * fraction, y: 0, width: width * (1 - fraction), height: height)

            // Faint part: dim silhouette with solid text.
            ctx.saveGState()
            ctx.clip(to: emptyRect)
            NSColor.black.withAlphaComponent(emptyAlpha).setFill()
            path.fill()
            (label as NSString).draw(at: origin, withAttributes: attrs)
            ctx.restoreGState()

            // Filled part: solid silhouette with the text cut out.
            if fraction > 0 {
                ctx.saveGState()
                ctx.clip(to: filledRect)
                NSColor.black.setFill()
                path.fill()
                ctx.setBlendMode(.destinationOut)
                (label as NSString).draw(at: origin, withAttributes: attrs)
                ctx.restoreGState()
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "\(provider.displayName) \(label)"
        return img
    }

    /// Pixel creature without legs: a tall block body with short side arms, the same
    /// height as the cloud and cat icons so the three line up (owner's choice).
    static func claudeShape(_ w: CGFloat) -> (NSBezierPath, CGRect) {
        let arm: CGFloat = 2.5
        let bodyX = arm, bodyW = w - arm * 2
        let bodyTop: CGFloat = 0.5, bodyBottom: CGFloat = 17.5
        let path = NSBezierPath()
        path.append(NSBezierPath(roundedRect: CGRect(x: bodyX, y: bodyTop, width: bodyW, height: bodyBottom - bodyTop),
                                 xRadius: 1, yRadius: 1))
        // Arms
        path.append(NSBezierPath(roundedRect: CGRect(x: 0, y: 9.5, width: arm + 1, height: 3.5), xRadius: 0.6, yRadius: 0.6))
        path.append(NSBezierPath(roundedRect: CGRect(x: w - arm - 1, y: 9.5, width: arm + 1, height: 3.5), xRadius: 0.6, yRadius: 0.6))
        let textBox = CGRect(x: bodyX, y: 5, width: bodyW, height: 11)
        return (path, textBox)
    }

    /// Cat head (Octocat-like silhouette): a rounded face with two pointed ears.
    static func githubShape(_ w: CGFloat) -> (NSBezierPath, CGRect) {
        let path = NSBezierPath()
        let faceTop: CGFloat = 4
        path.append(NSBezierPath(roundedRect: CGRect(x: 0, y: faceTop, width: w, height: 18 - faceTop - 0.5),
                                 xRadius: 6, yRadius: 6))
        // Ears rise from the upper corners and lean slightly outward.
        let left = NSBezierPath()
        left.move(to: CGPoint(x: 1.2, y: faceTop + 4))
        left.line(to: CGPoint(x: 2.2, y: 0.3))
        left.line(to: CGPoint(x: 8.5, y: faceTop + 0.5))
        left.close()
        let right = NSBezierPath()
        // Same winding as the left ear (mirroring reverses it), so the union stays solid.
        right.move(to: CGPoint(x: w - 1.2, y: faceTop + 4))
        right.line(to: CGPoint(x: w - 8.5, y: faceTop + 0.5))
        right.line(to: CGPoint(x: w - 2.2, y: 0.3))
        right.close()
        path.append(left)
        path.append(right)
        path.windingRule = .nonZero
        return (path, CGRect(x: 0, y: faceTop + 0.5, width: w, height: 18 - faceTop - 1))
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
