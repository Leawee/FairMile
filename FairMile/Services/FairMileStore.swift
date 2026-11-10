import Foundation
import SwiftData

@MainActor
enum Seed {
    static func bootstrap(context: ModelContext) throws {
        let vehicles = try context.fetch(FetchDescriptor<Vehicle>())
        if vehicles.isEmpty {
            context.insert(Vehicle(name: "My car", isDefault: true))
        } else if !vehicles.contains(where: \.isDefault) {
            vehicles.min { $0.createdAt < $1.createdAt }?.isDefault = true
        }
        try syncRates(context: context)
        try context.save()
    }

    static func syncRates(context: ModelContext) throws {
        let bundled = try RateBook.loadBundled()
        let existing = try context.fetch(FetchDescriptor<RatePeriod>())
        let keys = Set(bundled.map { key(category: $0.category.rawValue, start: $0.startDay, end: $0.endDay) })
        for row in existing where row.source == "IRS" {
            let rowKey = key(category: row.categoryRaw, start: row.startDay, end: row.endDay)
            if !keys.contains(rowKey) {
                context.delete(row)
            }
        }
        for record in bundled {
            let recordKey = key(category: record.category.rawValue, start: record.startDay, end: record.endDay)
            if let row = existing.first(where: {
                $0.source == "IRS" && key(category: $0.categoryRaw, start: $0.startDay, end: $0.endDay) == recordKey
            }) {
                row.centsTenths = record.centsTenths
                row.notice = record.notice
            } else {
                context.insert(
                    RatePeriod(
                        category: record.category,
                        startDay: record.startDay,
                        endDay: record.endDay,
                        centsTenths: record.centsTenths,
                        source: "IRS",
                        notice: record.notice,
                        createdAt: .distantPast
                    )
                )
            }
        }
    }

    private static func key(category: String, start: String, end: String) -> String {
        "\(category)|\(start)|\(end)"
    }
}

enum FairMileStore {
    static func supportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("FairMile", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func make(inMemory: Bool, iCloud: Bool) -> ModelContainer {
        if inMemory {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return makeContainer(configuration)
        }
        if iCloud {
            let cloud = ModelConfiguration("FairMile", cloudKitDatabase: .automatic)
            if let container = try? ModelContainer(
                for: Vehicle.self, Trip.self, Expense.self, TripRevision.self, RatePeriod.self,
                configurations: cloud
            ) {
                return container
            }
        }
        let local = ModelConfiguration("FairMile", cloudKitDatabase: .none)
        return makeContainer(local)
    }

    private static func makeContainer(_ configuration: ModelConfiguration) -> ModelContainer {
        do {
            return try ModelContainer(
                for: Vehicle.self, Trip.self, Expense.self, TripRevision.self, RatePeriod.self,
                configurations: configuration
            )
        } catch {
            fatalError("FairMile could not open its log. \(error.localizedDescription)")
        }
    }
}
