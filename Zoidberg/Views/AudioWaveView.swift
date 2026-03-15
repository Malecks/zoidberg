import SwiftUI

struct AudioWaveView: View {
    let level: Float
    private let barCount = 7

    // Each bar tracks its own smoothed level
    @State private var barLevels: [Float] = Array(repeating: 0, count: 7)

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                WaveBar(level: barLevels[i], index: i)
            }
        }
        .frame(width: 30, height: 22)
        .onChange(of: level) { _, newLevel in
            for i in 0..<barCount {
                barLevels[i] = newLevel
            }
        }
    }
}

private struct WaveBar: View {
    let level: Float
    let index: Int

    private static let multipliers: [CGFloat] = [0.25, 0.5, 1.0, 0.75, 1.0, 0.5, 0.25]
    private let base: CGFloat = 2
    private let maxExtra: CGFloat = 20

    private var barHeight: CGFloat {
        let spike = Self.multipliers[index % Self.multipliers.count]
        return base + maxExtra * CGFloat(level) * spike
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.red.opacity(0.9))
            .frame(width: 2, height: max(base, barHeight))
            .animation(.linear(duration: 0.04), value: level)
    }
}
