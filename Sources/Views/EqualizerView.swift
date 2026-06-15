import SwiftUI

/// Small animated equalizer bars shown on the currently-playing track.
/// When paused the bars freeze at a low level.
struct EqualizerView: View {
    var playing: Bool
    var color: Color = .white

    private let bars = 4
    @State private var phase = false

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<bars, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: 2.5, height: height(for: i))
                    .animation(
                        playing
                        ? .easeInOut(duration: 0.42 + Double(i) * 0.07)
                            .repeatForever(autoreverses: true)
                        : .default,
                        value: phase
                    )
            }
        }
        .frame(width: 18, height: 16)
        .onAppear { phase = true }
    }

    private func height(for i: Int) -> CGFloat {
        guard playing else { return 4 }
        // Alternating tall/short on each phase, varied per bar.
        let tall: [CGFloat] = [14, 9, 16, 7]
        let short: [CGFloat] = [5, 15, 6, 13]
        return phase ? tall[i % tall.count] : short[i % short.count]
    }
}
