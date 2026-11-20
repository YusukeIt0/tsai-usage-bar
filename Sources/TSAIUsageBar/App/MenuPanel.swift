import AppKit
import SwiftUI

/// A panel that opens directly below a menu bar item, like system menus and Control Center,
/// instead of NSPopover (whose arrow and spacing push the content further down).
/// Closes on a click elsewhere, Esc, or when another app becomes active.
@MainActor
final class MenuPanel {
    private var panel: KeyablePanel?
    private var anchorTop: CGFloat = 0
    private var anchorX: CGFloat = 0
    private var screen: NSScreen?
    private var eventMonitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var resizeObserver: NSObjectProtocol?
    private var onClose: (() -> Void)?

    var isShown: Bool { panel?.isVisible == true }

    func show<V: View>(_ view: V, below button: NSStatusBarButton, onClose: @escaping () -> Void) {
        close()
        guard let buttonWindow = button.window else { return }
        self.onClose = onClose
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        screen = buttonWindow.screen ?? NSScreen.main
        anchorTop = buttonRect.minY - 4
        anchorX = buttonRect.minX

        let host = NSHostingController(rootView: view)
        host.sizingOptions = [.preferredContentSize]

        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true

        let container = NSViewController()
        container.view = effect
        container.addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: effect.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        let p = KeyablePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .popUpMenu
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        p.contentViewController = container
        p.onEscape = { [weak self] in self?.close() }
        panel = p

        reposition(size: host.view.fittingSize)
        p.orderFrontRegardless()
        p.makeKey()

        // Keep the top edge under the menu bar when the content height changes.
        resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: p, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let p = self.panel else { return }
                if abs(p.frame.maxY - self.anchorTop) > 0.5 { self.reposition(size: p.frame.size) }
            }
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) { eventMonitors.append(m) }
        observers.append(NotificationCenter.default.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        })
    }

    func close() {
        guard let p = panel else { return }
        panel = nil
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        resizeObserver = nil
        p.orderOut(nil)
        let cb = onClose
        onClose = nil
        cb?()
    }

    /// PNG of the panel exactly as drawn (buttons and symbols included), with its rounded
    /// corners. The menu material comes out opaque, since what is behind the panel isn't drawn.
    /// Needs no screen recording permission: only this app's own view is drawn.
    func snapshotPNG() -> Data? {
        guard let view = panel?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let size = view.bounds.size
        let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        guard let out else { return nil }
        out.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 10, yRadius: 10).addClip()
        rep.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return out.representation(using: .png, properties: [:])
    }

    private func reposition(size: NSSize) {
        guard let p = panel else { return }
        let visible = screen?.visibleFrame ?? .zero
        var x = anchorX
        if x + size.width > visible.maxX - 8 { x = visible.maxX - 8 - size.width }
        x = max(visible.minX + 8, x)
        p.setFrame(NSRect(x: x, y: anchorTop - size.height, width: size.width, height: size.height), display: true)
    }
}

/// Borderless panels can't become key by default; the popover needs it for buttons and Esc.
final class KeyablePanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}
