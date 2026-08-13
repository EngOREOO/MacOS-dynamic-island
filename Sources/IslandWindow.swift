import SwiftUI
import AppKit
import Combine

// MARK: - Window

final class IslandWindow: NSPanel {
    private let state = IslandState()
    private var cancellables = Set<AnyCancellable>()

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
        // Reposition/resize the panel whenever the user drags a settings slider.
        state.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] in self?.positionOnScreen() }
            .store(in: &cancellables)
        startMouseMonitor()
    }

    @objc private func positionOnScreen() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.frame
        // Panel must fit the largest island state plus the top offset.
        let size = CGSize(
            width: max(state.expandedW, state.notificationSize.width, state.compactW, 440) + 80,
            height: state.topOffset + state.expandedH + 16
        )
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
        let x = frame.midX - size.width / 2 + state.xOffset
        let y = frame.maxY - state.topOffset - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}
