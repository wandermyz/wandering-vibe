import SwiftUI

extension Color {
    init(latencyMs ms: Int?) { self.init(uiColor: LatencyScale.color(ms: ms)) }
}

/// Small coloured legend for the latency scale.
struct LatencyLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            item(LatencyScale.green, "<150")
            item(LatencyScale.yellow, "<400")
            item(LatencyScale.orange, "<1s")
            item(LatencyScale.red, "≥1s")
            item(LatencyScale.purple, "no internet")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func item(_ c: UIColor, _ label: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 2).fill(Color(uiColor: c)).frame(width: 16, height: 7)
            Text(label)
        }
    }
}

/// Bar strip of recent probe latencies (log scale); failures are full-height purple.
struct Sparkline: View {
    var values: [Int?]
    /// Fixed number of bar slots (values are right-aligned); nil = one slot per value.
    var slots: Int? = nil

    var body: some View {
        Canvas { ctx, size in
            guard !values.isEmpty else { return }
            let n = max(slots ?? values.count, values.count)
            let w = size.width / CGFloat(n)
            let offset = n - values.count
            for (j, v) in values.enumerated() {
                let i = j + offset
                let h: CGFloat
                if let v {
                    // 20 ms → ~10%, 4 s → 100%
                    let f = (log10(Double(max(v, 20))) - log10(20.0)) / (log10(4000.0) - log10(20.0))
                    h = size.height * CGFloat(min(1, max(0.08, f)))
                } else {
                    h = size.height
                }
                let rect = CGRect(x: CGFloat(i) * w, y: size.height - h, width: max(1, w * 0.7), height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(Color(latencyMs: v)))
            }
        }
    }
}

struct StatTile: View {
    var value: String
    var label: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).monospacedDigit().foregroundStyle(color)
            Text(label.uppercased()).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

extension Radio {
    var badge: String { self == .unknown ? "—" : label }
}
