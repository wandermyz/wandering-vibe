import SwiftUI

/// Card shown after tapping a cell / spot on the History map.
struct SpotDetailCard: View {
    var detail: HistoryModel.SpotDetail
    var range: ClosedRange<Date>
    var onClose: () -> Void

    var body: some View {
        let s = detail.stats
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(detail.placeName ?? "Selected spot").font(.headline).lineLimit(1)
                verdict(s)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                }
            }
            row("Samples", "\(s.count) · \(s.sessions.count) pass\(s.sessions.count == 1 ? "" : "es")")
            row("Median / P90", "\(LatencyScale.format(ms: s.median)) / \(LatencyScale.format(ms: s.p90))")
            row("Jitter", LatencyScale.format(ms: s.jitterMs))
            row("No internet", String(format: "%.0f%%", s.failRate * 100),
                color: s.failures > 0 ? Color(uiColor: LatencyScale.purple) : .primary)
            row("Radio seen", radioMix(s))
            if let last = s.lastSeen {
                row("Last pass", last.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
            }
            passesStrip(s.passes.suffix(8))
                .frame(height: 36)
                .padding(.top, 4)
            Text("each column group = one pass through this spot · ~\(Int(detail.radiusMeters)) m radius")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func verdict(_ s: SpotStats) -> some View {
        let (text, color): (String, Color) = {
            if s.failRate > 0.1 || (s.p90 ?? 0) >= 1000 { return ("bad", .red) }
            if (s.p90 ?? 0) >= 400 { return ("shaky", .orange) }
            return ("good", .green)
        }()
        return Text(text).font(.caption.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(color)
    }

    private func row(_ k: String, _ v: String, color: Color = .primary) -> some View {
        HStack {
            Text(k).foregroundStyle(.secondary)
            Spacer()
            Text(v).fontWeight(.semibold).monospacedDigit().foregroundStyle(color)
        }
    }

    private func radioMix(_ s: SpotStats) -> String {
        let total = max(1, s.count)
        return s.radios.sorted { $0.value > $1.value }
            .map { "\($0.key.badge) \($0.value * 100 / total)%" }
            .joined(separator: " · ")
    }

    private func passesStrip(_ passes: ArraySlice<[Int?]>) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(passes.enumerated()), id: \.offset) { _, pass in
                Sparkline(values: Array(pass.suffix(12)))
                    .frame(width: CGFloat(min(pass.count, 12)) * 5)
            }
            Spacer(minLength: 0)
        }
    }
}
