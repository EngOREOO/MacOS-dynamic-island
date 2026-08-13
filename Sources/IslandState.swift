import AppKit
import SwiftUI
import IOKit.ps

// MARK: - State

enum IslandMode: Equatable {
    case idle          // slim pill: clock
    case compact       // pill with artwork + waveform
    case expanded      // hover: full controls
    case notification  // transient pop (track change)
}

final class IslandState: ObservableObject {
    @Published var mode: IslandMode = .idle
    @Published var track: Track?
    @Published var battery: String = ""
    @Published var time: Date = Date()
    @Published var hovering = false

    // MARK: user-adjustable geometry (persisted)

    @Published var topOffset: Double { didSet { save("topOffset", topOffset) } }
    @Published var xOffset: Double { didSet { save("xOffset", xOffset) } }
    @Published var idleW: Double { didSet { save("idleW", idleW) } }
    @Published var idleH: Double { didSet { save("idleH", idleH) } }
    @Published var compactW: Double { didSet { save("compactW", compactW) } }
    @Published var compactH: Double { didSet { save("compactH", compactH) } }
    @Published var expandedW: Double { didSet { save("expandedW", expandedW) } }
    @Published var expandedH: Double { didSet { save("expandedH", expandedH) } }

    // island geometry (shared with the window for hit-testing)
    var idleSize: CGSize { CGSize(width: idleW, height: idleH) }
    var compactSize: CGSize { CGSize(width: compactW, height: compactH) }
    var expandedSize: CGSize { CGSize(width: expandedW, height: expandedH) }
    var notificationSize: CGSize { CGSize(width: min(expandedW, 340), height: 84) }

    var currentSize: CGSize {
        switch mode {
        case .idle: return idleSize
        case .compact: return compactSize
        case .expanded: return expandedSize
        case .notification: return notificationSize
        }
    }

    private func save(_ key: String, _ value: Double) {
        UserDefaults.standard.set(value, forKey: "island." + key)
    }

    private static func load(_ key: String, _ fallback: Double) -> Double {
        let v = UserDefaults.standard.double(forKey: "island." + key)
        return v == 0 ? fallback : v
    }

    func resetGeometry() {
        topOffset = 13; xOffset = 0
        idleW = 190; idleH = 30
        compactW = 300; compactH = 34
        expandedW = 360; expandedH = 172
    }

    init() {
        topOffset = Self.load("topOffset", 13)
        xOffset = Self.load("xOffset", 0)
        idleW = Self.load("idleW", 190)
        idleH = Self.load("idleH", 30)
        compactW = Self.load("compactW", 300)
        compactH = Self.load("compactH", 34)
        expandedW = Self.load("expandedW", 360)
        expandedH = Self.load("expandedH", 172)
    }

    private var timer: Timer?
    private var started = false
    private var notificationWorkItem: DispatchWorkItem?

    func start() {
        guard !started else { return }
        started = true
        refresh(initial: true)
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func setHovering(_ h: Bool) {
        hovering = h
        updateMode()
    }

    private func refresh(initial: Bool = false) {
        time = Date()
        battery = batteryInfo()
        MediaController.fetchTrack { [weak self] newTrack in
            guard let self else { return }
            let trackChanged = newTrack?.title != self.track?.title || newTrack?.artist != self.track?.artist
            self.track = newTrack
            if trackChanged, newTrack != nil, !initial {
                self.showNotification()
            }
            self.updateMode()
        }
    }

    private func showNotification() {
        notificationWorkItem?.cancel()
        mode = .notification
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.notificationWorkItem = nil
            self.updateMode()
        }
        notificationWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    private func updateMode() {
        if case .notification = mode, notificationWorkItem != nil {
            return // stay until the work item fires
        }
        if hovering {
            mode = .expanded
        } else {
            mode = track != nil ? .compact : .idle
        }
    }

    // MARK: settings window

    private var settingsWindow: NSWindow?

    func openSettings() {
        if let w = settingsWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 470),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Dynamic Island Settings"
        w.contentView = NSHostingView(rootView: SettingsView(state: self))
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = w
    }

    // MARK: controls

    func togglePlay() { MediaController.command("toggle"); refreshSoon() }
    func next() { MediaController.command("next"); refreshSoon() }
    func prev() { MediaController.command("prev"); refreshSoon() }
    func seek(to seconds: Double) { MediaController.seek(to: seconds); refreshSoon() }

    private func refreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.refresh() }
    }

    private func batteryInfo() -> String {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
              let capacity = desc[kIOPSCurrentCapacityKey] as? Int else { return "" }
        let charging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
        return "\(capacity)%\(charging ? " ⚡" : "")"
    }
}
