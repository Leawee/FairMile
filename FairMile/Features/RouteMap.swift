import CoreLocation
import MapKit
import SwiftUI

enum PlaceMode: String, CaseIterable, Identifiable {
    case view
    case start
    case end

    var id: String { rawValue }

    var title: String {
        switch self {
        case .view: "View"
        case .start: "Place start"
        case .end: "Place end"
        }
    }
}

struct RouteMap: View {
    var points: [TrackSample]
    var start: Coordinate?
    var end: Coordinate?
    var showsUser: Bool
    var placeMode: PlaceMode
    var onPlace: (Coordinate) -> Void
    @Binding var position: MapCameraPosition

    var body: some View {
        MapReader { proxy in
            Map(position: $position, interactionModes: placeMode == .view ? .all : []) {
                ForEach(Array(TrackMath.segments(of: points).enumerated()), id: \.offset) { _, segment in
                    let coordinates = segment.map {
                        CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                    }
                    if coordinates.count >= 2 {
                        MapPolyline(coordinates: coordinates)
                            .stroke(Color.accentColor, lineWidth: 5)
                    }
                }
                if let start {
                    Marker("Start", systemImage: "location.circle", coordinate: start.location)
                        .tint(.green)
                }
                if let end {
                    Marker("End", systemImage: "mappin.circle.fill", coordinate: end.location)
                        .tint(Color.accentColor)
                }
                if showsUser {
                    UserAnnotation()
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .simultaneousGesture(
                SpatialTapGesture().onEnded { event in
                    guard placeMode != .view, let coordinate = proxy.convert(event.location, from: .local) else { return }
                    onPlace(Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))
                }
            )
        }
    }
}

extension Coordinate {
    var location: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum MapFrame {
    static func fit(_ points: [TrackSample]) -> MapCameraPosition {
        let coordinates = points.map(\.coordinate.location)
        guard let first = coordinates.first else { return .automatic }
        if coordinates.count == 1 {
            return .region(MKCoordinateRegion(center: first, latitudinalMeters: 1_200, longitudinalMeters: 1_200))
        }
        var rect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }
        let padded = rect.insetBy(dx: -max(rect.size.width * 0.35, 400), dy: -max(rect.size.height * 0.35, 400))
        return .rect(padded)
    }
}

enum PlaceLookup {
    static func address(for coordinate: Coordinate) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        let street = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let parts = [street.isEmpty ? placemark.name : street, placemark.locality, placemark.administrativeArea]
            .compactMap { $0 }
        var unique: [String] = []
        for part in parts where !part.isEmpty && !unique.contains(part) {
            unique.append(part)
        }
        return unique.isEmpty ? nil : unique.joined(separator: ", ")
    }
}
