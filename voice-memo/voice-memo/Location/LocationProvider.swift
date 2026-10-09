import CoreLocation
import Foundation

@MainActor
final class LocationProvider: NSObject {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Request a place name. Returns nil if unavailable / permission denied / lookup fails.
    /// Never throws — recordings should not fail because of location.
    func placeName(timeout: TimeInterval = 4) async -> String? {
        guard CLLocationManager.locationServicesEnabled() else { return nil }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            // Don't block start of recording on a permission prompt.
            return nil
        case .restricted, .denied:
            return nil
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            return nil
        }

        let loc = await withCheckedContinuation { (c: CheckedContinuation<CLLocation?, Never>) in
            self.continuation = c
            manager.requestLocation()
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await MainActor.run {
                    if let c = self.continuation {
                        self.continuation = nil
                        c.resume(returning: nil)
                    }
                }
            }
        }
        guard let loc else { return nil }

        let geocoder = CLGeocoder()
        let placemarks = (try? await geocoder.reverseGeocodeLocation(loc)) ?? []
        guard let p = placemarks.first else { return nil }
        return p.locality ?? p.subLocality ?? p.name
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in
            if let c = continuation {
                continuation = nil
                c.resume(returning: last)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if let c = continuation {
                continuation = nil
                c.resume(returning: nil)
            }
        }
    }
}
