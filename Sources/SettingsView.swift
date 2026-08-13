import SwiftUI

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var state: IslandState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                Text("Position").font(.headline)
                slider("Distance from top", value: $state.topOffset, range: 0...60, unit: "px")
                slider("Horizontal shift", value: $state.xOffset, range: -300...300, unit: "px")
            }
            Divider()
            Group {
                Text("Idle pill").font(.headline)
                slider("Width", value: $state.idleW, range: 120...320, unit: "px")
                slider("Height", value: $state.idleH, range: 22...48, unit: "px")
            }
            Divider()
            Group {
                Text("Now Playing pill").font(.headline)
                slider("Width", value: $state.compactW, range: 200...460, unit: "px")
                slider("Height", value: $state.compactH, range: 24...52, unit: "px")
            }
            Divider()
            Group {
                Text("Expanded card").font(.headline)
                slider("Width", value: $state.expandedW, range: 280...520, unit: "px")
                slider("Height", value: $state.expandedH, range: 130...260, unit: "px")
            }
            Divider()
            HStack {
                Spacer()
                Button("Reset to defaults") { state.resetGeometry() }
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.system(size: 12))
                Spacer()
                Text("\(Int(value.wrappedValue.rounded())) \(unit)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Slider(value: value, in: range)
                .controlSize(.small)
        }
    }
}
