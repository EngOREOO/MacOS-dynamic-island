import AppKit
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

    // island geometry (shared with the window for hit-testing)
    let idleSize = CGSize(width: 190, height: 30)
    let compactSize = CGSize(width: 300, height: 34)
    let expandedSize = CGSize(width: 360, height: 172)
    let notificationSize = CGSize(width: 340, height: 84)

    var currentSize: CGSize {
        switch mode {
        case .idle: return idleSize
        case .compact: return compactSize
        case .expanded: return expandedSize
        case .notification: return notificationSize
        }
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
