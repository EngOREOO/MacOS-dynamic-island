import SwiftUI
import AppKit

// MARK: - Window

final class IslandWindow: NSPanel {
    private let state = IslandState()

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovable = false
        ignoresMouseEvents = true
        contentView = NSHostingView(rootView: IslandView(state: state))
        positionOnScreen()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(positionOnScreen),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        startMouseMonitor()
    }

    @objc private func positionOnScreen() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame
        let size = CGSize(width: 440, height: 210)
        let origin = CGPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height)
        setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// Only capture the mouse when the pointer is actually over the visible island;
    /// everywhere else in the panel region, clicks/hover pass through to apps below.
    private func startMouseMonitor() {
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] _ in
            self?.updateMouseCapture()
        }
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.updateMouseCapture()
        }
    }

    private func updateMouseCapture() {
        let over = islandScreenFrame().contains(NSEvent.mouseLocation)
        if over == ignoresMouseEvents {
            ignoresMouseEvents = !over
        }
    }

    private func islandScreenFrame() -> NSRect {
        let size = state.currentSize
        // island is top-centered in the panel, 3px below the panel's top edge
        let x = frame.midX - size.width / 2
        let y = frame.maxY - 13 - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}
