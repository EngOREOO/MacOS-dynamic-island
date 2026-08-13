import AppKit
import SwiftUI
import IOKit.ps

// MARK: - State

enum IslandMode: Equatable {
    case idle          // slim pill: clock
    case compact       // pill with artwork + waveform
    case expanded      // hover: full controls
    case notification  // transient pop (track change / system event)
}

struct IslandNotification {
    var icon: String        // SF Symbol name
    var title: String
    var subtitle: String
    var isTrack = false     // track pops render artwork + waveform instead of the icon
    var duration: Double = 4.0
    var accent: Color = .white
}

final class IslandState: ObservableObject {
    @Published var mode: IslandMode = .idle
    @Published var track: Track?
    @Published var battery: String = ""
    @Published var charging = false
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
    var notificationSize: CGSize { expandedSize } // events pop as the full card

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
        topOffset = 0; xOffset = 6
        idleW = 183; idleH = 31
        compactW = 218; compactH = 27
        expandedW = 296; expandedH = 210
    }

    init() {
        topOffset = Self.load("topOffset", 0)
        xOffset = Self.load("xOffset", 6)
        idleW = Self.load("idleW", 183)
        idleH = Self.load("idleH", 31)
        compactW = Self.load("compactW", 218)
        compactH = Self.load("compactH", 27)
        expandedW = Self.load("expandedW", 296)
        expandedH = Self.load("expandedH", 210)
    }

    private var timer: Timer?
    private var started = false
    private var notificationWorkItem: DispatchWorkItem?

    // MARK: notification hub

    @Published var activeNotification: IslandNotification?
    private var notifQueue: [IslandNotification] = []
    private var lastPlugged: Bool?
    private var lowBatteryWarned = false

    /// Enqueue a pop. Pops show one at a time, in order.
    func notify(icon: String, title: String, subtitle: String, isTrack: Bool = false,
                duration: Double = 4.0, accent: Color = .white) {
        notifQueue.append(IslandNotification(icon: icon, title: title, subtitle: subtitle,
                                             isTrack: isTrack, duration: duration, accent: accent))
        drainQueue()
    }

    private func drainQueue() {
        guard activeNotification == nil, !notifQueue.isEmpty else { return }
        let next = notifQueue.removeFirst()
        activeNotification = next
        mode = .notification
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.activeNotification = nil
            self.notificationWorkItem = nil
            self.updateMode()
            self.drainQueue()
        }
        notificationWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + next.duration, execute: work)
    }

    private func startEventSources() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.notify(icon: "lock.fill", title: "Screen Locked", subtitle: "See you soon", accent: .blue)
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.notify(icon: "lock.open.fill", title: "Welcome Back", subtitle: "Screen unlocked", accent: .blue)
        }
        // Fires the instant any power source changes (charger in/out, capacity…)
        // — no waiting for the 2s poll, so plug/unplug pops feel immediate.
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let state = Unmanaged<IslandState>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { state.checkPowerSource() }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    func start() {
        guard !started else { return }
        started = true
        refresh(initial: true)
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        startEventSources()
    }

    func setHovering(_ h: Bool) {
        hovering = h
        updateMode()
    }

    private func refresh(initial: Bool = false) {
        time = Date()
        checkPowerSource()
        MediaController.fetchTrack { [weak self] newTrack in
            guard let self else { return }
            let trackChanged = newTrack?.title != self.track?.title || newTrack?.artist != self.track?.artist
            self.track = newTrack
            if trackChanged, let t = newTrack, !initial {
                // quick glance — pop for a beat, then tuck away
                self.notify(icon: "music.note", title: t.title, subtitle: t.artist, isTrack: true, duration: 1.0)
            }
            self.updateMode()
        }
    }

    private func checkPowerSource() {
        guard let info = powerSource() else { battery = ""; return }
        battery = "\(info.capacity)%"
        charging = info.pluggedIn

        if let last = lastPlugged, last != info.pluggedIn {
            notify(
                icon: info.pluggedIn ? "bolt.fill" : "bolt.slash.fill",
                title: info.pluggedIn ? "Charger Connected" : "Charger Removed",
                subtitle: "Battery \(info.capacity)%",
                accent: info.pluggedIn ? .green : .orange
            )
        }
        lastPlugged = info.pluggedIn

        if info.capacity <= 20 && !info.pluggedIn && !lowBatteryWarned {
            lowBatteryWarned = true
            notify(icon: "battery.25", title: "Low Battery", subtitle: "\(info.capacity)% remaining", accent: .red)
        }
        if info.capacity > 25 || info.pluggedIn { lowBatteryWarned = false }
    }

    private func updateMode() {
        if activeNotification != nil {
            return // stay in notification mode until the pop dismisses
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
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 560),
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

    private func powerSource() -> (capacity: Int, pluggedIn: Bool)? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
              let capacity = desc[kIOPSCurrentCapacityKey] as? Int else { return nil }
        // NB: on a MacBook the listed source IS the battery, so its Type is
        // "InternalBattery" — the charger-attach signal lives in Power Source State.
        let pluggedIn = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        return (capacity, pluggedIn)
    }
}
