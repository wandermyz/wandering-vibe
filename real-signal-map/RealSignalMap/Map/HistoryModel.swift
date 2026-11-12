import CoreLocation
import MapKit
import SwiftUI

/// Preset time slices for the History map.
enum RangePreset: String, CaseIterable, Identifiable {
    case today = "Today", day = "24h", week = "7 days", month = "30 days", all = "All", custom = "Custom"
    var id: String { rawValue }
}

/// Drives the History tab: time range, metric, viewport-scoped query and tap details.
@MainActor
final class HistoryModel: ObservableObject {
    @Published var preset: RangePreset = .week
    @Published var range: ClosedRange<Date>
    @Published var metric: Metric = .median { didSet { rebuildOverlay() } }
    @Published private(set) var overlay: SampleOverlay?
    @Published private(set) var visibleCount = 0
    @Published private(set) var truncated = false
    @Published private(set) var isRawTrace = false
    @Published private(set) var dataBounds: ClosedRange<Date>?
    @Published private(set) var histogram: [Date: Int] = [:]
    @Published private(set) var histogramBucket: TimeInterval = 3600
    @Published var detail: SpotDetail?
    /// Where the map opens (latest sample), set once.
    @Published private(set) var initialCenter: CLLocationCoordinate2D?

    struct SpotDetail: Identifiable {
        let id = UUID()
        var coordinate: CLLocationCoordinate2D
        var stats: SpotStats
        var radiusMeters: Double
        var placeName: String?
    }

    private let store: SampleStore
    private var region: MKCoordinateRegion?
    private var mapWidth: Double = 10_000
    private var samples: [Sample] = []
    private var grid: Aggregation.Grid?
    private var reloadTask: Task<Void, Never>?
    private let geocoder = CLGeocoder()
    nonisolated static let queryLimit = 600_000

    init(store: SampleStore) {
        self.store = store
        let now = Date()
        range = now.addingTimeInterval(-7 * 86_400)...now
    }

    // MARK: Inputs

    func apply(_ p: RangePreset) {
        preset = p
        let now = Date()
        switch p {
        case .today: range = Calendar.current.startOfDay(for: now)...now
        case .day: range = now.addingTimeInterval(-86_400)...now
        case .week: range = now.addingTimeInterval(-7 * 86_400)...now
        case .month: range = now.addingTimeInterval(-30 * 86_400)...now
        case .all: range = (dataBounds?.lowerBound ?? now.addingTimeInterval(-86_400))...now
        case .custom: return
        }
        reload()
    }

    func setCustom(_ r: ClosedRange<Date>) {
        preset = .custom
        range = r
        reload()
    }

    func regionChanged(_ r: MKCoordinateRegion, widthMeters: Double) {
        region = r
        mapWidth = widthMeters
        reload(debounce: true)
    }

    /// Refreshes timeline + map (call on appear, after new data was recorded).
    func refreshAll() {
        let store = store
        Task.detached(priority: .userInitiated) {
            let bounds = store.timeBounds()
            let latest = store.latestCoordinate()
            await MainActor.run {
                self.dataBounds = bounds
                if self.initialCenter == nil, let latest {
                    self.initialCenter = CLLocationCoordinate2D(latitude: latest.lat, longitude: latest.lon)
                }
                if self.preset != .custom { self.apply(self.preset) }
                self.reloadHistogram()
            }
        }
    }

    private func reloadHistogram() {
        guard let b = dataBounds else { histogram = [:]; return }
        let span = max(Date().timeIntervalSince(b.lowerBound), 3600)
        // ~120 bars, snapped to friendly sizes.
        let sizes: [TimeInterval] = [600, 1800, 3600, 3 * 3600, 6 * 3600, 12 * 3600, 86_400, 2 * 86_400, 7 * 86_400]
        let bucket = sizes.first(where: { span / $0 <= 120 }) ?? sizes.last!
        let store = store
        Task.detached(priority: .utility) {
            let h = store.histogram(bucket: bucket)
            await MainActor.run {
                self.histogramBucket = bucket
                self.histogram = h
            }
        }
    }

    // MARK: Query

    func reload(debounce: Bool = false) {
        guard let region else { return }
        reloadTask?.cancel()
        let range = range
        let width = mapWidth
        let store = store
        reloadTask = Task { [weak self] in
            if debounce { try? await Task.sleep(nanoseconds: 250_000_000) }
            guard !Task.isCancelled else { return }
            // Pad the viewport so small pans don't need a requery to look right.
            let latPad = region.span.latitudeDelta * 0.25
            let lonPad = region.span.longitudeDelta * 0.25
            let rows = await Task.detached(priority: .userInitiated) {
                store.samples(from: range.lowerBound, to: range.upperBound,
                              minLat: region.center.latitude - region.span.latitudeDelta / 2 - latPad,
                              maxLat: region.center.latitude + region.span.latitudeDelta / 2 + latPad,
                              minLon: region.center.longitude - region.span.longitudeDelta / 2 - lonPad,
                              maxLon: region.center.longitude + region.span.longitudeDelta / 2 + lonPad,
                              limit: HistoryModel.queryLimit)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.samples = rows
            self.truncated = rows.count >= HistoryModel.queryLimit
            self.isRawTrace = width <= Aggregation.rawTraceMaxWidth
            self.grid = self.isRawTrace ? nil : Aggregation.grid(rows, cellMeters: Aggregation.cellSize(forMapWidth: width),
                                                                  refLat: region.center.latitude)
            self.visibleCount = rows.count
            self.rebuildOverlay()
        }
    }

    private func rebuildOverlay() {
        if let grid {
            let metric = metric
            let shapes = grid.cells.map { key, cellSamples -> GridCellShape in
                let b = grid.bounds(of: key)
                let p1 = MKMapPoint(CLLocationCoordinate2D(latitude: b.maxLat, longitude: b.minLon))
                let p2 = MKMapPoint(CLLocationCoordinate2D(latitude: b.minLat, longitude: b.maxLon))
                let rect = MKMapRect(x: p1.x, y: p1.y, width: p2.x - p1.x, height: p2.y - p1.y)
                return GridCellShape(rect: rect, color: SpotStats(samples: cellSamples).color(for: metric))
            }
            overlay = SampleOverlay(.cells(shapes))
        } else {
            overlay = SampleOverlay(.trace(Aggregation.segments(samples)))
        }
    }

    // MARK: Tap

    func tap(_ c: CLLocationCoordinate2D) {
        if detail != nil { detail = nil; return }
        var picked: [Sample]
        var center = c
        var radius: Double
        if let grid {
            let key = grid.key(for: c)
            picked = grid.cells[key] ?? []
            let b = grid.bounds(of: key)
            center = CLLocationCoordinate2D(latitude: (b.minLat + b.maxLat) / 2, longitude: (b.minLon + b.maxLon) / 2)
            radius = grid.cellMeters / 2
        } else {
            radius = max(25, mapWidth / 25)
            let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
            picked = samples.filter { CLLocation(latitude: $0.lat, longitude: $0.lon).distance(from: here) <= radius }
        }
        guard !picked.isEmpty else { return }
        detail = SpotDetail(coordinate: center, stats: SpotStats(samples: picked), radiusMeters: radius)
        let id = detail?.id
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(CLLocation(latitude: center.latitude, longitude: center.longitude)) { [weak self] marks, _ in
            guard let m = marks?.first else { return }
            let name = [m.thoroughfare, m.locality].compactMap { $0 }.joined(separator: ", ")
            Task { @MainActor in
                guard let self, self.detail?.id == id, !name.isEmpty else { return }
                self.detail?.placeName = name
            }
        }
    }
}
