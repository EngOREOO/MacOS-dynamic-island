import SwiftUI

// MARK: - Seek bar

struct SeekBarView: View {
    let track: Track
    let onSeek: (Double) -> Void

    @State private var scrubValue: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let value = scrubValue ?? track.progress
            HStack(spacing: 8) {
                Text(format(value))
                Slider(
                    value: Binding(
                        get: { value },
                        set: { scrubValue = $0 }
                    ),
                    in: 0...track.duration,
                    onEditingChanged: { editing in
                        if !editing, let v = scrubValue {
                            onSeek(v)
                            scrubValue = nil
                        }
                    }
                )
                .controlSize(.small)
                .tint(.white)
                Text("-" + format(max(track.duration - value, 0)))
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
