import CoreLocation
import Foundation
import Observation

struct ActiveTripSnapshot: Codable, Equatable, Sendable {
    var phase: String
    var vehicleId: UUID
    var startedAt: Date
    var acceptance: TrackAcceptance
    var draft: TripDraft?
}

final class LocationBridge: NSObject, CLLocationManagerDelegate {
    var onSamples: (@Sendable ([TrackSample]) -> Void)?
    var onAuthorization: (@Sendable (CLAuthorizationStatus) -> Void)?

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorization?(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let samples = locations.map { location in
            TrackSample(
                id: UUID(),
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timestamp: location.timestamp,
                horizontalAccuracy: location.horizontalAccuracy,
                segment: 0
            )
        }
        onSamples?(samples)
    }
}

@MainActor
@Observable
final class TripRecorder {
    enum Phase: Equatable {
        case idle
        case recording
        case review
    }

    private(set) var phase: Phase = .idle
    private(set) var acceptance = TrackAcceptance()
    private(set) var startedAt: Date?
    private(set) var vehicleId: UUID?
    private(set) var locationRunning = false
    private(set) var denied = false
    var draft: TripDraft?

    private let directory: URL
    private let bridge = LocationBridge()
    private var manager: CLLocationManager?
    private var pendingVehicle: UUID?
    private var fileURL: URL { directory.appendingPathComponent("active-trip.json") }

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        bridge.onSamples = { [weak self] samples in
            Task { @MainActor in
                self?.ingest(samples)
            }
        }
        bridge.onAuthorization = { [weak self] status in
            Task { @MainActor in
                self?.applyAuthorization(status)
            }
        }
        restore()
    }

    func start(vehicleId: UUID) {
        denied = false
        pendingVehicle = vehicleId
        let manager = activate()
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            beginNew(vehicleId: vehicleId)
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            denied = true
        }
    }

    func continueRecording() {
        guard let vehicleId else { return }
        guard phase == .recording || phase == .review else { return }
        denied = false
        pendingVehicle = vehicleId
        let manager = activate()
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            phase = .recording
            draft = nil
            locationRunning = true
            manager.startUpdatingLocation()
            persist()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            denied = true
        }
    }

    func end() {
        stopLocation()
        guard let startedAt, let vehicleId else { return }
        let ended = max(Date(), startedAt.addingTimeInterval(1))
        draft = TripDraft.session(
            vehicleId: vehicleId,
            startedAt: startedAt,
            endedAt: ended,
            acceptance: acceptance
        )
        phase = .review
        persist()
    }

    func updateDraft(_ draft: TripDraft) {
        guard phase == .review else { return }
        self.draft = draft
        persist()
    }

    func clear() {
        stopLocation()
        phase = .idle
        acceptance = TrackAcceptance()
        startedAt = nil
        vehicleId = nil
        draft = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    func sceneBecameActive() {
        guard phase == .recording, locationRunning else { return }
        activate().startUpdatingLocation()
    }

    private func beginNew(vehicleId: UUID) {
        acceptance = TrackAcceptance()
        startedAt = Date()
        self.vehicleId = vehicleId
        draft = nil
        phase = .recording
        locationRunning = true
        pendingVehicle = nil
        activate().startUpdatingLocation()
        persist()
    }

    private func applyAuthorization(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            denied = false
            guard let pendingVehicle else { return }
            if phase == .idle {
                beginNew(vehicleId: pendingVehicle)
            } else {
                self.vehicleId = pendingVehicle
                phase = .recording
                locationRunning = true
                activate().startUpdatingLocation()
                persist()
            }
        case .denied, .restricted:
            denied = true
        default:
            break
        }
    }

    private func ingest(_ samples: [TrackSample]) {
        guard phase == .recording else { return }
        for sample in samples {
            acceptance = TrackMath.adding(sample, to: acceptance)
        }
        persist()
    }

    private func stopLocation() {
        manager?.stopUpdatingLocation()
        locationRunning = false
    }

    private func activate() -> CLLocationManager {
        if let manager { return manager }
        let manager = CLLocationManager()
        manager.delegate = bridge
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        self.manager = manager
        return manager
    }

    private func persist() {
        guard phase != .idle, let vehicleId, let startedAt else { return }
        let snapshot = ActiveTripSnapshot(
            phase: phase == .review ? "review" : "recording",
            vehicleId: vehicleId,
            startedAt: startedAt,
            acceptance: acceptance,
            draft: draft
        )
        guard let data = try? JSONCodec.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func restore() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONCodec.decode(ActiveTripSnapshot.self, from: data) else { return }
        vehicleId = snapshot.vehicleId
        startedAt = snapshot.startedAt
        acceptance = snapshot.acceptance
        draft = snapshot.draft
        phase = snapshot.phase == "review" ? .review : .recording
        locationRunning = false
    }
}
