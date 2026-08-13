import SwiftUI

// MARK: - Seek bar

struct SeekBarView: View {
    let track: Track
    let onSeek: (Double) -> Void

    @State private var scrubValue: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 8) {
                Text(format(scrubValue ?? track.progress))
                Slider(
                    value: Binding(
                        get: { scrubValue ?? track.progress },
                        set: { scrubValue = $0 }
                    ),
                    in: 0...track.duration,
                    onEditingChanged: { editing in
                        if !editing, let value = scrubValue {
                            onSeek(value)
                            scrubValue = nil
                        }
                    }
                )
                .controlSize(.small)
                Text(format(track.duration))
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundColor(.white.opacity(0.7))
        }
    }

    private func format(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
