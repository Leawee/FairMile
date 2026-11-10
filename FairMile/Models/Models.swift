import Foundation
import SwiftData

@Model
final class Vehicle {
    var id: UUID = UUID()
    var name: String = ""
    var year: Int?
    var make: String = ""
    var modelName: String = ""
    var isDefault: Bool = false
    var createdAt: Date = Date()
    @Relationship(deleteRule: .nullify, inverse: \Trip.vehicle)
    var trips: [Trip]? = []

    init(name: String, year: Int? = nil, make: String = "", modelName: String = "", isDefault: Bool = false) {
        self.id = UUID()
        self.name = name
        self.year = year
        self.make = make
        self.modelName = modelName
        self.isDefault = isDefault
        self.createdAt = Date()
        self.trips = []
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Vehicle" : trimmed
    }

    var detailLine: String {
        [year.map(String.init), make, modelName]
            .compactMap { value in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " ")
    }
}

@Model
final class Trip {
    var id: UUID = UUID()
    var vehicleId: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date = Date()
    var startLatitude: Double?
    var startLongitude: Double?
    var endLatitude: Double?
    var endLongitude: Double?
    var startAddress: String = ""
    var endAddress: String = ""
    @Attribute(.externalStorage) var trackData: Data = Data()
    var originData: Data = Data()
    var trimStart: Int = 0
    var trimEnd: Int = 0
    var milesThousandths: Int = 0
    var trackedMilesThousandths: Int?
    var mileageOverridden: Bool = false
    var placesEdited: Bool = false
    var isEdited: Bool = false
    var categoryRaw: String = TripCategory.business.rawValue
    var purpose: String = ""
    var notes: String = ""
    var sourceRaw: String = TripSource.session.rawValue
    var rateTenths: Int = 0
    var hasRate: Bool = false
    var rateLabel: String = ""
    var amountCents: Int = 0
    var deletedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var vehicle: Vehicle?
    @Relationship(deleteRule: .cascade, inverse: \Expense.trip)
    var expenses: [Expense]? = []
    @Relationship(deleteRule: .cascade, inverse: \TripRevision.trip)
    var revisions: [TripRevision]? = []

    init(id: UUID = UUID(), vehicleId: UUID) {
        self.id = id
        self.vehicleId = vehicleId
        self.startedAt = Date()
        self.endedAt = Date()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.expenses = []
        self.revisions = []
    }
}

@Model
final class Expense {
    var id: UUID = UUID()
    var date: Date = Date()
    var typeRaw: String = ExpenseType.parking.rawValue
    var amountCents: Int = 0
    var notes: String = ""
    @Attribute(.externalStorage) var photoData: Data?
    var trip: Trip?

    init(id: UUID = UUID(), date: Date, type: ExpenseType, amountCents: Int, notes: String, photoData: Data?) {
        self.id = id
        self.date = date
        self.typeRaw = type.rawValue
        self.amountCents = amountCents
        self.notes = notes
        self.photoData = photoData
    }
}

@Model
final class TripRevision {
    var id: UUID = UUID()
    var at: Date = Date()
    var summary: String = ""
    var trip: Trip?

    init(id: UUID = UUID(), at: Date, summary: String) {
        self.id = id
        self.at = at
        self.summary = summary
    }
}

@Model
final class RatePeriod {
    var id: UUID = UUID()
    var categoryRaw: String = TripCategory.business.rawValue
    var startDay: String = ""
    var endDay: String = ""
    var centsTenths: Int = 0
    var source: String = "IRS"
    var notice: String = ""
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        category: TripCategory,
        startDay: String,
        endDay: String,
        centsTenths: Int,
        source: String,
        notice: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.categoryRaw = category.rawValue
        self.startDay = startDay
        self.endDay = endDay
        self.centsTenths = centsTenths
        self.source = source
        self.notice = notice
        self.createdAt = createdAt
    }
}
