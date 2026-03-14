import SwiftUI

struct AudioWaveView: View {
    let level: Float
    let barCount = 5

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { i in
                WaveBar(level: level, index: i, total: barCount)
            }
        }
        .frame(width: 28, height: 18)
    }
}

private struct WaveBar: View {
    let level: Float
    let index: Int
    let total: Int

    // Fixed per-bar multipliers for spiky variance
    private static let multipliers: [CGFloat] = [0.5, 0.9, 0.35, 1.0, 0.6]

    private var barHeight: CGFloat {
        let base: CGFloat = 3
        let maxExtra: CGFloat = 18
        let centeredness = 1.0 - abs(CGFloat(index) - CGFloat(total - 1) / 2) / (CGFloat(total) / 2)
        let sensitivity = 0.3 + centeredness * 0.7
        let spike = Self.multipliers[index % Self.multipliers.count]
        return base + maxExtra * CGFloat(level) * sensitivity * spike
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.red.opacity(0.9))
            .frame(width: 3, height: max(base, barHeight))
            .animation(.easeOut(duration: 0.08), value: level)
    }

    private let base: CGFloat = 3
}
