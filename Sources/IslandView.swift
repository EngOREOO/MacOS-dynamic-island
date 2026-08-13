import SwiftUI
import AppKit

// MARK: - Waveform

struct WaveformView: View {
    var active: Bool
    var barCount: Int = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.25, paused: !active)) { context in
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.green)
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

// MARK: - Island View

struct IslandView: View {
    @ObservedObject var state: IslandState

    private var currentSize: CGSize { state.currentSize }

    private var cornerRadius: CGFloat {
        switch state.mode {
        case .idle, .compact: return currentSize.height / 2
        case .expanded, .notification: return 26
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black)
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
            content
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .frame(width: currentSize.width, height: currentSize.height, alignment: .top)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onHover { inside in
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                state.setHovering(inside)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .offset(x: state.xOffset)
        .padding(.top, state.topOffset)
        .onAppear { state.start() }
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: state.mode)
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
            Text(state.battery)
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

    // MARK: notification pop — track change or system event

    private var notificationContent: some View {
        let n = state.activeNotification
        let isTrack = n?.isTrack ?? true
        return HStack(spacing: 12) {
            if isTrack {
                artworkView(size: 52)
            } else {
                Image(systemName: n?.icon ?? "bell.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 52, height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(isTrack ? "Now Playing" : "Notification")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(n?.title ?? state.track?.title ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(n?.subtitle ?? state.track?.artist ?? "")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isTrack {
                WaveformView(active: state.track?.isPlaying ?? false)
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .frame(height: state.notificationSize.height)
    }

    // MARK: expanded — full media controls

    private var expandedContent: some View {
        VStack(spacing: 9) {
            HStack(spacing: 12) {
                artworkView(size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.track?.title ?? "Nothing playing")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(state.track?.artist ?? state.time.formatted(date: .complete, time: .omitted))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    if let track = state.track, !track.sourceApp.isEmpty {
                        Text(track.sourceApp)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }
                }
                Spacer()
            }

            HStack(spacing: 28) {
                Button { state.prev() } label: {
                    Image(systemName: "backward.fill").font(.system(size: 16))
                }
                Button { state.togglePlay() } label: {
                    Image(systemName: (state.track?.isPlaying ?? false) ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                }
                Button { state.next() } label: {
                    Image(systemName: "forward.fill").font(.system(size: 16))
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(state.track == nil ? .gray : .white)
            .disabled(state.track == nil)

            if let track = state.track, track.duration > 0 {
                SeekBarView(track: track, onSeek: { state.seek(to: $0) })
            }

            HStack {
                Text(state.time, style: .time)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                Text(state.battery)
                    .font(.system(size: 11))
                Spacer()
                Button { state.openSettings() } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                Button { NSApp.terminate(nil) } label: {
                    Image(systemName: "power")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .foregroundColor(.white.opacity(0.7))
        }
        .padding(14)
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
