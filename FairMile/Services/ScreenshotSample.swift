#if DEBUG
import Foundation
import SwiftData

/// Sample trips for App Store screenshots. The Release archive does not include this.
enum ScreenshotSample {
    static let argument = "-FairMileScreenshotSample"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    static var step: String {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-FairMileScreenshotStep"),
              index + 1 < arguments.count
        else { return "log" }
        return arguments[index + 1]
    }

    @MainActor
    static func prepare(app: AppModel, context: ModelContext) {
        guard isRequested else { return }
        app.finishOnboarding()
        do {
            try seed(context: context)
        } catch {
            assertionFailure("Screenshot sample failed: \(error.localizedDescription)")
        }
        switch step {
        case "trips":
            app.tab = .trips
        case "export":
            app.tab = .export
        case "paywall":
            app.showPaywall = true
        case "editor":
            app.tab = .log
            app.screenshotTripID = newestTripID(context: context)
        default:
            app.tab = .log
        }
    }

    @MainActor
    private static func seed(context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<Trip>()).filter { $0.deletedAt == nil }
        guard existing.isEmpty else { return }
        let vehicles = try context.fetch(FetchDescriptor<Vehicle>())
        guard let vehicle = vehicles.first(where: \.isDefault) ?? vehicles.first else { return }
        vehicle.name = "Civic"

        let trips: [(waypoints: [(Double, Double)], start: Date, purpose: String, from: String, to: String)] = [
            (
                [
                    (37.7955, -122.3937),
                    (37.7890, -122.4010),
                    (37.7760, -122.4170),
                    (37.7600, -122.4350),
                    (37.7350, -122.4300),
                    (37.7000, -122.4050),
                    (37.6550, -122.3950),
                    (37.6213, -122.3790)
                ],
                day(2026, 11, 9, 9, 14),
                "Client meeting",
                "Ferry Building, San Francisco",
                "San Francisco International Airport"
            ),
            (
                [
                    (37.7848, -122.4090),
                    (37.7795, -122.4145),
                    (37.7710, -122.4210),
                    (37.7690, -122.4460),
                    (37.7595, -122.4580),
                    (37.7485, -122.4520)
                ],
                day(2026, 11, 6, 13, 40),
                "Supply pickup",
                "450 Golden Gate Ave, San Francisco",
                "1600 Irving St, San Francisco"
            ),
            (
                [
                    (37.7793, -122.4192),
                    (37.7870, -122.4070),
                    (37.7980, -122.4000),
                    (37.8085, -122.4100),
                    (37.8088, -122.4098)
                ],
                day(2026, 11, 3, 8, 5),
                "Site visit",
                "1 Dr Carlton B Goodlett Pl, San Francisco",
                "Pier 39, San Francisco"
            )
        ]

        for item in trips {
            let points = samples(waypoints: item.waypoints, start: item.start)
            var draft = TripDraft.session(
                vehicleId: vehicle.id,
                startedAt: item.start,
                endedAt: points.last?.timestamp ?? item.start,
                acceptance: TrackAcceptance(points: points, meters: TrackMath.pathMeters(points: points), gapCount: 0)
            )
            draft.startAddress = item.from
            draft.endAddress = item.to
            draft.purpose = item.purpose
            draft.milesThousandths = draft.pathMilesThousandths
            draft.trackedMilesThousandths = draft.milesThousandths
            try TripLibrary.save(baseline: draft, edited: draft, context: context, isPlus: true)
        }
    }

    private static func newestTripID(context: ModelContext) -> UUID? {
        let trips = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
        return trips.filter { $0.deletedAt == nil }.max { $0.startedAt < $1.startedAt }?.id
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        Format.calendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .now
    }

    private static func samples(waypoints: [(Double, Double)], start: Date) -> [TrackSample] {
        let stepMeters = 40.0
        var coordinates: [Coordinate] = []
        guard waypoints.count >= 2 else { return [] }
        for index in 0..<(waypoints.count - 1) {
            let startPoint = Coordinate(latitude: waypoints[index].0, longitude: waypoints[index].1)
            let endPoint = Coordinate(latitude: waypoints[index + 1].0, longitude: waypoints[index + 1].1)
            let distance = TrackMath.meters(startPoint, endPoint)
            let steps = max(1, Int((distance / stepMeters).rounded(.up)))
            let count = index == waypoints.count - 2 ? steps : steps
            for step in 0..<count {
                let progress = Double(step) / Double(steps)
                coordinates.append(
                    Coordinate(
                        latitude: startPoint.latitude + (endPoint.latitude - startPoint.latitude) * progress,
                        longitude: startPoint.longitude + (endPoint.longitude - startPoint.longitude) * progress
                    )
                )
            }
        }
        if let last = waypoints.last {
            coordinates.append(Coordinate(latitude: last.0, longitude: last.1))
        }
        return coordinates.enumerated().map { index, coordinate in
            TrackSample(
                id: UUID(),
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                timestamp: start.addingTimeInterval(Double(index) * 3),
                horizontalAccuracy: 8,
                segment: 0
            )
        }
    }
}
#endif
