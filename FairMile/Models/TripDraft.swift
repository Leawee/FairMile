import Foundation

struct TripOrigin: Codable, Equatable, Hashable, Sendable {
    var milesThousandths: Int
    var trimStart: Int
    var trimEnd: Int
    var start: Coordinate?
    var end: Coordinate?

    init(draft: TripDraft) {
        milesThousandths = draft.milesThousandths
        trimStart = draft.trimStart
        trimEnd = draft.trimEnd
        start = draft.startCoordinate
        end = draft.endCoordinate
    }
}

struct ExpenseDraft: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id: UUID
    var date: Date
    var type: ExpenseType
    var amountCents: Int
    var notes: String
    var photoData: Data?
}

struct RevisionDraft: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id: UUID
    var at: Date
    var summary: String
}

struct TripDraft: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id: UUID
    var vehicleId: UUID
    var startedAt: Date
    var endedAt: Date
    var startAddress: String
    var endAddress: String
    var startCoordinate: Coordinate?
    var endCoordinate: Coordinate?
    var track: [TrackSample]
    var trimStart: Int
    var trimEnd: Int
    var milesThousandths: Int
    var trackedMilesThousandths: Int?
    var mileageOverridden: Bool
    var placesEdited: Bool
    var origin: TripOrigin?
    var category: TripCategory
    var purpose: String
    var notes: String
    var source: TripSource
    var expenses: [ExpenseDraft]
    var revisions: [RevisionDraft]
    var isEdited: Bool

    var includedPoints: [TrackSample] {
        guard !track.isEmpty else { return [] }
        let start = min(max(0, trimStart), track.count - 1)
        let end = min(max(start, trimEnd), track.count - 1)
        return Array(track[start...end])
    }

    var trimIsFull: Bool {
        track.isEmpty || (trimStart == 0 && trimEnd == track.count - 1)
    }

    var gapCount: Int {
        max(0, Set(includedPoints.map(\.segment)).count - 1)
    }

    var pathMilesThousandths: Int {
        TrackMath.milesThousandths(fromMeters: TrackMath.pathMeters(points: includedPoints))
    }

    mutating func clampTrim() {
        guard !track.isEmpty else {
            trimStart = 0
            trimEnd = 0
            return
        }
        trimStart = min(max(0, trimStart), track.count - 1)
        trimEnd = min(max(trimStart, trimEnd), track.count - 1)
    }

    mutating func setTrim(start: Int, end: Int) {
        placesEdited = false
        trimStart = start
        trimEnd = end
        clampTrim()
        if let first = includedPoints.first, let last = includedPoints.last {
            startCoordinate = first.coordinate
            endCoordinate = last.coordinate
        }
        if !mileageOverridden {
            milesThousandths = pathMilesThousandths
        }
        refreshEditedFlag()
    }

    mutating func placeStart(_ coordinate: Coordinate) {
        startCoordinate = coordinate
        placesEdited = true
        refreshEditedFlag()
    }

    mutating func placeEnd(_ coordinate: Coordinate) {
        endCoordinate = coordinate
        placesEdited = true
        refreshEditedFlag()
    }

    mutating func setMiles(_ thousandths: Int) {
        milesThousandths = max(0, thousandths)
        if source == .session {
            mileageOverridden = milesThousandths != pathMilesThousandths
        }
        refreshEditedFlag()
    }

    mutating func usePathMileage() {
        guard source == .session, !track.isEmpty else { return }
        mileageOverridden = false
        milesThousandths = pathMilesThousandths
        refreshEditedFlag()
    }

    mutating func refreshEditedFlag() {
        if source == .split || source == .merge {
            isEdited = true
            return
        }
        guard let origin else {
            isEdited = false
            return
        }
        isEdited = milesThousandths != origin.milesThousandths
            || trimStart != origin.trimStart
            || trimEnd != origin.trimEnd
            || startCoordinate != origin.start
            || endCoordinate != origin.end
    }

    static func session(vehicleId: UUID, startedAt: Date, endedAt: Date, acceptance: TrackAcceptance) -> TripDraft {
        let points = acceptance.points
        let miles = TrackMath.milesThousandths(fromMeters: TrackMath.pathMeters(points: points))
        var draft = TripDraft(
            id: UUID(),
            vehicleId: vehicleId,
            startedAt: startedAt,
            endedAt: endedAt,
            startAddress: "",
            endAddress: "",
            startCoordinate: points.first?.coordinate,
            endCoordinate: points.last?.coordinate,
            track: points,
            trimStart: 0,
            trimEnd: max(0, points.count - 1),
            milesThousandths: miles,
            trackedMilesThousandths: miles,
            mileageOverridden: false,
            placesEdited: false,
            origin: nil,
            category: .business,
            purpose: "",
            notes: "",
            source: .session,
            expenses: [],
            revisions: [],
            isEdited: false
        )
        draft.origin = TripOrigin(draft: draft)
        draft.refreshEditedFlag()
        return draft
    }

    static func manual(vehicleId: UUID, now: Date) -> TripDraft {
        let start = Format.calendar().date(byAdding: .hour, value: -1, to: now) ?? now
        return TripDraft(
            id: UUID(),
            vehicleId: vehicleId,
            startedAt: start,
            endedAt: now,
            startAddress: "",
            endAddress: "",
            startCoordinate: nil,
            endCoordinate: nil,
            track: [],
            trimStart: 0,
            trimEnd: 0,
            milesThousandths: 0,
            trackedMilesThousandths: nil,
            mileageOverridden: false,
            placesEdited: false,
            origin: nil,
            category: .business,
            purpose: "",
            notes: "",
            source: .manual,
            expenses: [],
            revisions: [],
            isEdited: false
        )
    }
}

enum JSONCodec {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}
