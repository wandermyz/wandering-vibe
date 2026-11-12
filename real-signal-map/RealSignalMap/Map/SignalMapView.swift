import MapKit
import SwiftUI

struct TraceSegment {
    var a: MKMapPoint
    var b: MKMapPoint
    var color: UIColor
}

struct GridCellShape {
    var rect: MKMapRect
    var color: UIColor
}

/// One immutable overlay holding either a raw trace or aggregated cells.
/// Drawn by a single renderer so tens of thousands of segments stay cheap.
final class SampleOverlay: NSObject, MKOverlay {
    enum Content {
        case trace([TraceSegment])
        case cells([GridCellShape])
    }

    let content: Content
    let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    let boundingMapRect = MKMapRect.world

    init(_ content: Content) { self.content = content }
}

final class SampleOverlayRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? SampleOverlay else { return }
        switch overlay.content {
        case .trace(let segments):
            let width = 6 / zoomScale
            context.setLineCap(.round)
            context.setLineWidth(width)
            for s in segments {
                let box = MKMapRect(x: min(s.a.x, s.b.x), y: min(s.a.y, s.b.y),
                                    width: abs(s.a.x - s.b.x), height: abs(s.a.y - s.b.y)).insetBy(dx: -width, dy: -width)
                guard box.intersects(mapRect) else { continue }
                context.setStrokeColor(s.color.cgColor)
                context.move(to: point(for: s.a))
                context.addLine(to: point(for: s.b))
                context.strokePath()
            }
        case .cells(let cells):
            for c in cells where c.rect.intersects(mapRect) {
                var r = rect(for: c.rect)
                let inset = min(r.width, r.height) * 0.06
                r = r.insetBy(dx: inset, dy: inset)
                context.setFillColor(c.color.withAlphaComponent(0.78).cgColor)
                let path = CGPath(roundedRect: r, cornerWidth: r.width * 0.18, cornerHeight: r.height * 0.18, transform: nil)
                context.addPath(path)
                context.fillPath()
            }
        }
    }
}

/// Camera behaviour for `SignalMapView`.
enum MapMode { case follow, explore }

/// MKMapView wrapper that shows one `SampleOverlay`, reports region changes and taps.
struct SignalMapView: UIViewRepresentable {
    var overlay: SampleOverlay?
    var mode: MapMode
    var highlight: CLLocationCoordinate2D?
    /// Explore mode: centre here (once) with a ~40 km wide view.
    var initialCenter: CLLocationCoordinate2D? = nil
    var onRegionChange: ((MKCoordinateRegion, Double) -> Void)?
    var onTap: ((CLLocationCoordinate2D) -> Void)?

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = true
        if mode == .follow { map.setUserTrackingMode(.follow, animated: false) }

        let tracking = MKUserTrackingButton(mapView: map)
        tracking.translatesAutoresizingMaskIntoConstraints = false
        tracking.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9)
        tracking.layer.cornerRadius = 10
        tracking.clipsToBounds = true
        map.addSubview(tracking)
        NSLayoutConstraint.activate([
            tracking.trailingAnchor.constraint(equalTo: map.trailingAnchor, constant: -14),
            tracking.topAnchor.constraint(equalTo: map.safeAreaLayoutGuide.topAnchor, constant: mode == .follow ? 64 : 10),
            tracking.widthAnchor.constraint(equalToConstant: 44),
            tracking.heightAnchor.constraint(equalToConstant: 44),
        ])

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        map.addGestureRecognizer(tap)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        if mode == .explore, !context.coordinator.didSetInitialRegion {
            if let c = initialCenter {
                context.coordinator.didSetInitialRegion = true
                // Shift south so the point sits above the bottom sheet.
                let shifted = CLLocationCoordinate2D(latitude: c.latitude - 0.1, longitude: c.longitude)
                map.setRegion(MKCoordinateRegion(center: shifted, latitudinalMeters: 40_000, longitudinalMeters: 40_000), animated: false)
            } else if let user = map.userLocation.location {
                context.coordinator.didSetInitialRegion = true
                map.setRegion(MKCoordinateRegion(center: user.coordinate, latitudinalMeters: 40_000, longitudinalMeters: 40_000), animated: false)
            }
        }
        let current = map.overlays.compactMap { $0 as? SampleOverlay }
        if let overlay, !current.contains(where: { $0 === overlay }) {
            map.addOverlay(overlay, level: .aboveRoads)
            map.removeOverlays(current)
        } else if overlay == nil, !current.isEmpty {
            map.removeOverlays(current)
        }

        let pins = map.annotations.compactMap { $0 as? MKPointAnnotation }
        if let highlight {
            if pins.first.map({ $0.coordinate.latitude != highlight.latitude || $0.coordinate.longitude != highlight.longitude }) ?? true {
                map.removeAnnotations(pins)
                let pin = MKPointAnnotation()
                pin.coordinate = highlight
                map.addAnnotation(pin)
            }
        } else if !pins.isEmpty {
            map.removeAnnotations(pins)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: SignalMapView
        var didSetInitialRegion = false
        init(parent: SignalMapView) { self.parent = parent }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is SampleOverlay { return SampleOverlayRenderer(overlay: overlay) }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let r = mapView.region
            let west = CLLocation(latitude: r.center.latitude, longitude: r.center.longitude - r.span.longitudeDelta / 2)
            let east = CLLocation(latitude: r.center.latitude, longitude: r.center.longitude + r.span.longitudeDelta / 2)
            parent.onRegionChange?(r, west.distance(from: east))
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is MKPointAnnotation else { return nil }
            let v = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "spot")
            v.markerTintColor = .label
            v.glyphImage = UIImage(systemName: "antenna.radiowaves.left.and.right")
            return v
        }

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let map = g.view as? MKMapView else { return }
            parent.onTap?(map.convert(g.location(in: map), toCoordinateFrom: map))
        }
    }
}
