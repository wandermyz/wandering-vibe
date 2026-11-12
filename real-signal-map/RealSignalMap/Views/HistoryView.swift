import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var history: HistoryModel
    @State private var showCustom = false

    var body: some View {
        ZStack(alignment: .bottom) {
            SignalMapView(
                overlay: history.overlay,
                mode: .explore,
                highlight: history.detail?.coordinate,
                initialCenter: history.initialCenter,
                onRegionChange: { r, w in history.regionChanged(r, widthMeters: w) },
                onTap: { history.tap($0) })
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                if let d = history.detail {
                    SpotDetailCard(detail: d, range: history.range) { history.detail = nil }
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
                sheet
            }
            .animation(.snappy, value: history.detail?.id)
        }
        .onAppear { history.refreshAll() }
        .sheet(isPresented: $showCustom) { CustomRangeSheet() }
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(RangePreset.allCases) { p in
                        Button {
                            if p == .custom { showCustom = true } else { history.apply(p) }
                        } label: {
                            Text(p == .custom ? "Custom…" : p.rawValue)
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 11).padding(.vertical, 6)
                                .background(history.preset == p ? Color.primary : Color.secondary.opacity(0.15),
                                            in: Capsule())
                                .foregroundStyle(history.preset == p ? Color(uiColor: .systemBackground) : .primary)
                        }
                    }
                }
            }

            HStack {
                Text(rangeText).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                Text(countText).font(.footnote).foregroundStyle(.secondary)
            }

            TimelineSlider()
                .frame(height: 64)

            Picker("Metric", selection: $history.metric) {
                ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(history.isRawTrace)

            LatencyLegend()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26))
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private static let rangeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd HH:mm")
        return f
    }()

    private var rangeText: String {
        return "\(Self.rangeFormatter.string(from: history.range.lowerBound)) → \(Self.rangeFormatter.string(from: history.range.upperBound))"
    }

    private var countText: String {
        let n = history.visibleCount.formatted()
        let mode = history.isRawTrace ? "trace" : "grid"
        return history.truncated ? "\(n)+ pts · \(mode)" : "\(n) pts · \(mode)"
    }
}

/// Histogram of stored samples over time with two drag handles selecting the visible range.
struct TimelineSlider: View {
    @EnvironmentObject private var history: HistoryModel
    @State private var dragLower: Date?
    @State private var dragUpper: Date?

    var body: some View {
        let now = Date()
        let start = min(history.dataBounds?.lowerBound ?? history.range.lowerBound, history.range.lowerBound)
        let domain = start...max(now, start.addingTimeInterval(3600))
        let lower = dragLower ?? history.range.lowerBound
        let upper = dragUpper ?? history.range.upperBound

        GeometryReader { geo in
            let w = geo.size.width
            let barsH = geo.size.height - 16
            let x: (Date) -> CGFloat = { d in
                CGFloat(d.timeIntervalSince(domain.lowerBound) / domain.upperBound.timeIntervalSince(domain.lowerBound)) * w
            }
            let date: (CGFloat) -> Date = { px in
                let f = Double(min(max(px / w, 0), 1))
                return domain.lowerBound.addingTimeInterval(f * domain.upperBound.timeIntervalSince(domain.lowerBound))
            }

            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    let maxCount = max(1, history.histogram.values.max() ?? 1)
                    let bw = max(1.5, x(domain.lowerBound.addingTimeInterval(history.histogramBucket)) - x(domain.lowerBound))
                    for (t, n) in history.histogram {
                        let bx = x(t)
                        let h = max(2, barsH * CGFloat(sqrt(Double(n) / Double(maxCount))))
                        let inSel = t.addingTimeInterval(history.histogramBucket) > lower && t < upper
                        ctx.fill(Path(CGRect(x: bx, y: barsH - h, width: max(1, bw - 0.8), height: h)),
                                 with: .color(inSel ? .accentColor : .secondary.opacity(0.35)))
                    }
                }
                .frame(height: barsH)

                // Selection box
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor, lineWidth: 1.5))
                    .frame(width: max(4, x(upper) - x(lower)), height: barsH)
                    .offset(x: x(lower))
                    .allowsHitTesting(false)

                handle.offset(x: x(lower) - 11, y: barsH / 2 - 15)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                        dragLower = min(date(g.location.x), upper.addingTimeInterval(-600))
                    }.onEnded { _ in commit() })
                handle.offset(x: x(upper) - 11, y: barsH / 2 - 15)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                        dragUpper = max(date(g.location.x), lower.addingTimeInterval(600))
                    }.onEnded { _ in commit() })

                // Axis labels
                HStack {
                    Text(domain.lowerBound, format: .dateTime.month(.abbreviated).day())
                    Spacer()
                    Text("now")
                }
                .font(.caption2).foregroundStyle(.secondary)
                .offset(y: barsH + 2)
            }
        }
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(uiColor: .systemBackground))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor, lineWidth: 1.5))
            .frame(width: 10, height: 30)
            .padding(.horizontal, 6) // bigger hit area
            .contentShape(Rectangle())
    }

    private func commit() {
        let r = (dragLower ?? history.range.lowerBound)...(dragUpper ?? history.range.upperBound)
        dragLower = nil
        dragUpper = nil
        history.setCustom(r)
    }
}

struct CustomRangeSheet: View {
    @EnvironmentObject private var history: HistoryModel
    @Environment(\.dismiss) private var dismiss
    @State private var from = Date()
    @State private var to = Date()

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $from, in: ...to)
                DatePicker("To", selection: $to, in: from...)
            }
            .navigationTitle("Custom range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Show") { history.setCustom(from...to); dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            from = history.range.lowerBound
            to = history.range.upperBound
        }
    }
}
