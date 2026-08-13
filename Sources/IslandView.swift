import SwiftUI
import AppKit

// MARK: - Island shape
// Flush with the top edge of the screen: square top corners, rounded bottom
// corners — the island reads as a physical extension of the notch.

struct IslandShape: Shape {
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(bottomRadius, rect.height / 2, rect.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - Waveform

struct WaveformView: View {
    var active: Bool
    var barCount: Int = 4
    var color: Color = .green

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !active)) { context in
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(width: 2.5, height: barHeight(index: i, at: context.date))
                }
            }
            .frame(height: 14)
        }
    }

    private func barHeight(index: Int, at date: Date) -> CGFloat {
        guard active else { return 3 }
        let t = date.timeIntervalSinceReferenceDate
        let v = sin(t * 3.2 + Double(index) * 1.4) * 0.5 + 0.5
        return 3 + v * 9
    }
}

// MARK: - Battery label — percent + green bolt while charging

struct BatteryLabel: View {
    @ObservedObject var state: IslandState
    var size: CGFloat = 11

    var body: some View {
        HStack(spacing: 3) {
            if state.charging {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.green)
            }
            Text(state.battery)
        }
        .font(.system(size: size, weight: .medium))
    }
}

// MARK: - Island View

struct IslandView: View {
    @ObservedObject var state: IslandState

    private var currentSize: CGSize { state.currentSize }

    private var bottomRadius: CGFloat {
        switch state.mode {
        case .idle, .compact:
            return currentSize.height / 2
        case .expanded:
            return 20
        case .notification:
            return state.activeNotification?.level != nil ? currentSize.height / 2 : 22
        }
    }

    private let morphSpring = Animation.spring(response: 0.42, dampingFraction: 0.72)

    var body: some View {
        ZStack(alignment: .top) {
            IslandShape(bottomRadius: bottomRadius)
                .fill(Color.black)
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
            content
                .clipShape(IslandShape(bottomRadius: bottomRadius))
        }
        .frame(width: currentSize.width, height: currentSize.height, alignment: .top)
        .contentShape(IslandShape(bottomRadius: bottomRadius))
        .onHover { inside in
            withAnimation(morphSpring) {
                state.setHovering(inside)
            }
        }
        // swipe across the island to skip tracks (left = next, right = previous)
        .gesture(
            DragGesture(minimumDistance: 25)
                .onEnded { value in
                    let dx = value.translation.width
                    guard abs(dx) > abs(value.translation.height), abs(dx) > 40 else { return }
                    if dx < 0 { state.next() } else { state.prev() }
                }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .offset(x: state.xOffset)
        .padding(.top, state.topOffset)
        .onAppear { state.start() }
        .animation(morphSpring, value: state.mode)
    }

    @ViewBuilder
    private var content: some View {
        switch state.mode {
        case .idle:
            idleContent
        case .compact:
            compactContent
        case .expanded:
            expandedContent
        case .notification:
            notificationContent
        }
    }

    // MARK: idle pill — clock

    private var idleContent: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.green).frame(width: 5, height: 5)
            Text(state.time, style: .time)
            Spacer()
            BatteryLabel(state: state)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.white.opacity(0.85))
        .padding(.horizontal, 14)
        .frame(height: state.idleSize.height)
    }

    // MARK: compact pill — artwork + title + waveform (iPhone style)

    private var compactContent: some View {
        HStack(spacing: 8) {
            artworkView(size: 22)
            Text(state.track?.title ?? "")
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.system(size: 11, weight: .medium))
            Spacer(minLength: 4)
            WaveformView(active: state.track?.isPlaying ?? false)
        }
        .foregroundColor(.white.opacity(0.9))
        .padding(.horizontal, 10)
        .frame(height: state.compactSize.height)
    }

    // MARK: notification — track glance / HUD / system event card

    @ViewBuilder
    private var notificationContent: some View {
        let n = state.activeNotification
        if n?.isTrack ?? true {
            // track change: full media card, same as hover
            expandedContent
        } else if let level = n?.level {
            hudContent(icon: n?.icon ?? "speaker.wave.2.fill", level: level)
        } else {
            eventCard(n)
        }
    }

    // MARK: HUD — icon + thick glow level bar, nothing else (Alcove style)

    private func hudContent(icon: String, level: Double) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.white)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule()
                        .fill(Self.glowColor(level))
                        .frame(width: max(8, geo.size.width * CGFloat(level)))
                }
            }
            .frame(height: 12)
        }
        .padding(.horizontal, 22)
        .frame(width: state.notificationSize.width, height: state.notificationSize.height)
    }

    /// Glow theme: green at low levels, shading through orange to red at 100%.
    private static func glowColor(_ level: Double) -> Color {
        Color(hue: (1 - min(max(level, 0), 1)) * 0.33, saturation: 0.85, brightness: 0.95)
    }

    // MARK: system event card — icon tile + title + subtitle

    private func eventCard(_ n: IslandNotification?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: n?.icon ?? "bell.fill")
                .font(.system(size: 22))
                .foregroundColor(n?.accent ?? .white)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill((n?.accent ?? .white).opacity(0.15))
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(n?.title ?? "")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(n?.subtitle ?? "")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text("Notification")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(width: state.notificationSize.width, height: state.notificationSize.height)
    }

    // MARK: expanded — Alcove-style now playing card

    private var expandedContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                artworkView(size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.track?.title ?? "Nothing playing")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(state.track?.artist ?? state.time.formatted(date: .complete, time: .omitted))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if state.track != nil {
                    WaveformView(active: state.track?.isPlaying ?? false,
                                 color: .white.opacity(0.9))
                }
            }

            Spacer(minLength: 8)

            if let track = state.track, track.duration > 0 {
                SeekBarView(track: track, onSeek: { state.seek(to: $0) })
                Spacer(minLength: 8)
            }

            HStack {
                Button { state.openSettings() } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                Spacer()
                HStack(spacing: 34) {
                    Button { state.prev() } label: {
                        Image(systemName: "backward.fill").font(.system(size: 18))
                    }
                    Button { state.togglePlay() } label: {
                        Image(systemName: (state.track?.isPlaying ?? false) ? "pause.fill" : "play.fill")
                            .font(.system(size: 22))
                    }
                    Button { state.next() } label: {
                        Image(systemName: "forward.fill").font(.system(size: 18))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(state.track == nil ? .gray : .white)
                Spacer()
                Button { NSApp.terminate(nil) } label: {
                    Image(systemName: "power")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: state.expandedSize.width, height: state.expandedSize.height)
    }

    // MARK: shared

    @ViewBuilder
    private func artworkView(size: CGFloat) -> some View {
        if let img = state.track?.artwork {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
        } else {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color.white.opacity(0.12))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4))
                        .foregroundColor(.white.opacity(0.6))
                }
        }
    }
}
