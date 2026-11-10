import Foundation

struct Coordinate: Codable, Equatable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
}

struct TrackSample: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id: UUID
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    var horizontalAccuracy: Double
    var segment: Int

    var coordinate: Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }
}

enum TrackPolicy {
    static let maxAccuracyMeters = 65.0
    static let minimumStepMeters = 8.0
    static let maxSpeedMetersPerSecond = 55.0
    static let gapSeconds = 45.0
    static let gapMeters = 100.0
    static let minimumInterval = 0.5
    static let earthRadiusMeters = 6_371_000.0
    static let metersPerMile = 1_609.344
}

struct TrackAcceptance: Codable, Equatable, Hashable, Sendable {
    var points: [TrackSample] = []
    var meters: Double = 0
    var gapCount: Int = 0

    var milesThousandths: Int {
        TrackMath.milesThousandths(fromMeters: meters)
    }
}

enum TrackMath {
    static func meters(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return TrackPolicy.earthRadiusMeters * 2 * atan2(sqrt(h), sqrt(max(0, 1 - h)))
    }

    static func milesThousandths(fromMeters meters: Double) -> Int {
        guard meters > 0 else { return 0 }
        return Int(((meters / TrackPolicy.metersPerMile) * 1000).rounded())
    }

    static func pathMeters(points: [TrackSample]) -> Double {
        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            guard previous.segment == current.segment else { continue }
            total += meters(previous.coordinate, current.coordinate)
        }
        return total
    }

    static func segments(of points: [TrackSample]) -> [[TrackSample]] {
        guard let first = points.first else { return [] }
        var grouped: [[TrackSample]] = [[first]]
        for point in points.dropFirst() {
            if point.segment == grouped[grouped.count - 1][0].segment {
                grouped[grouped.count - 1].append(point)
            } else {
                grouped.append([point])
            }
        }
        return grouped
    }

    static func adding(_ sample: TrackSample, to acceptance: TrackAcceptance) -> TrackAcceptance {
        var next = acceptance
        guard sample.horizontalAccuracy >= 0,
              sample.horizontalAccuracy <= TrackPolicy.maxAccuracyMeters,
              abs(sample.latitude) <= 90,
              abs(sample.longitude) <= 180 else {
            return next
        }
        guard let last = next.points.last else {
            var first = sample
            first.segment = 0
            next.points = [first]
            return next
        }
        let interval = sample.timestamp.timeIntervalSince(last.timestamp)
        guard interval >= TrackPolicy.minimumInterval else { return next }
        let distance = meters(last.coordinate, sample.coordinate)
        guard distance >= TrackPolicy.minimumStepMeters else { return next }
        guard distance / interval <= TrackPolicy.maxSpeedMetersPerSecond else { return next }

        var stored = sample
        if interval > TrackPolicy.gapSeconds, distance > TrackPolicy.gapMeters {
            stored.segment = last.segment + 1
            next.gapCount += 1
            next.points.append(stored)
            return next
        }
        stored.segment = last.segment
        next.points.append(stored)
        next.meters += distance
        return next
    }

    static func accept(_ samples: [TrackSample]) -> TrackAcceptance {
        samples.reduce(into: TrackAcceptance()) { partial, sample in
            partial = adding(sample, to: partial)
        }
    }

    static func split(points: [TrackSample], fraction: Double) -> (leftEnd: Int, rightStart: Int) {
        let clamped = min(max(fraction, 0.05), 0.95)
        guard points.count >= 2 else { return (0, 0) }
        let total = pathMeters(points: points)
        guard total > 0 else {
            let mid = max(1, min(points.count - 1, Int((Double(points.count - 1) * clamped).rounded())))
            return (mid, mid)
        }
        let target = total * clamped
        var walked = 0.0
        var splitIndex = 1
        for index in 1..<points.count {
            let step: Double
            if points[index - 1].segment == points[index].segment {
                step = meters(points[index - 1].coordinate, points[index].coordinate)
            } else {
                step = 0
            }
            if walked + step >= target {
                splitIndex = index
                break
            }
            walked += step
            splitIndex = index
        }
        splitIndex = min(max(1, splitIndex), points.count - 1)
        return (splitIndex, splitIndex)
    }
}
