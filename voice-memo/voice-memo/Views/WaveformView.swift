import SwiftUI

struct WaveformView: View {
    let samples: [Float]  // 0...1
    var color: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                guard !samples.isEmpty else { return }
                let buckets = max(40, Int(size.width / 3))
                let stride = max(1, samples.count / buckets)
                let mid = size.height / 2
                var x: CGFloat = 0
                let barWidth = size.width / CGFloat(buckets)

                for b in 0..<buckets {
                    let start = b * stride
                    let end = min(samples.count, start + stride)
                    guard start < end else { break }
                    var peak: Float = 0
                    for j in start..<end { peak = max(peak, samples[j]) }
                    let h = max(2, CGFloat(peak) * size.height)
                    let rect = CGRect(x: x, y: mid - h / 2, width: max(1, barWidth - 1), height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
                    x += barWidth
                }
            }
        }
    }
}
