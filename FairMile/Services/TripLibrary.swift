import Foundation
import SwiftData

@MainActor
enum TripLibrary {
    static func records(context: ModelContext) -> [RateRecord] {
        let rows = (try? context.fetch(FetchDescriptor<RatePeriod>())) ?? []
        return rows.compactMap(record(from:))
    }

    static func record(from row: RatePeriod) -> RateRecord? {
        guard let category = TripCategory(rawValue: row.categoryRaw) else { return nil }
        return RateRecord(
            id: row.id,
            category: category,
            startDay: row.startDay,
            endDay: row.endDay,
            centsTenths: row.centsTenths,
            source: row.source,
            notice: row.notice,
            createdAt: row.createdAt
        )
    }

    static func draft(from trip: Trip) -> TripDraft {
        let track = (try? JSONCodec.decode([TrackSample].self, from: trip.trackData)) ?? []
        let origin = trip.originData.isEmpty ? nil : try? JSONCodec.decode(TripOrigin.self, from: trip.originData)
        var draft = TripDraft(
            id: trip.id,
            vehicleId: trip.vehicle?.id ?? trip.vehicleId,
            startedAt: trip.startedAt,
            endedAt: trip.endedAt,
            startAddress: trip.startAddress,
            endAddress: trip.endAddress,
            startCoordinate: coordinate(trip.startLatitude, trip.startLongitude),
            endCoordinate: coordinate(trip.endLatitude, trip.endLongitude),
            track: track,
            trimStart: trip.trimStart,
            trimEnd: trip.trimEnd,
            milesThousandths: trip.milesThousandths,
            trackedMilesThousandths: trip.trackedMilesThousandths,
            mileageOverridden: trip.mileageOverridden,
            placesEdited: trip.placesEdited,
            origin: origin,
            category: TripCategory(rawValue: trip.categoryRaw) ?? .business,
            purpose: trip.purpose,
            notes: trip.notes,
            source: TripSource(rawValue: trip.sourceRaw) ?? .manual,
            expenses: (trip.expenses ?? []).map { expense in
                ExpenseDraft(
                    id: expense.id,
                    date: expense.date,
                    type: ExpenseType(rawValue: expense.typeRaw) ?? .other,
                    amountCents: expense.amountCents,
                    notes: expense.notes,
                    photoData: expense.photoData
                )
            }.sorted { $0.date < $1.date },
            revisions: (trip.revisions ?? []).map { revision in
                RevisionDraft(id: revision.id, at: revision.at, summary: revision.summary)
            }.sorted { $0.at < $1.at },
            isEdited: trip.isEdited
        )
        draft.clampTrim()
        draft.refreshEditedFlag()
        return draft
    }

    static func liveDrafts(context: ModelContext) -> [TripDraft] {
        let trips = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
        return trips.filter { $0.deletedAt == nil }.map(draft(from:)).sorted { $0.startedAt > $1.startedAt }
    }

    static func save(
        baseline: TripDraft,
        edited: TripDraft,
        context: ModelContext,
        isPlus: Bool,
        now: Date = .now
    ) throws {
        guard edited.endedAt >= edited.startedAt else { throw LedgerError.invalidTimes }
        let trips = try context.fetch(FetchDescriptor<Trip>())
        let existing = trips.first { $0.id == edited.id }
        if existing == nil, !isPlus {
            let dates = trips.filter { $0.deletedAt == nil }.map(\.startedAt)
            if Quota.count(startDates: dates, now: edited.startedAt) >= Quota.monthlyFreeTrips {
                throw LedgerError.quota
            }
        }
        let prepared = TripEdits.preparedForSave(
            baseline: baseline,
            edited: edited,
            isNew: existing == nil,
            now: now
        )
        let trip = existing ?? Trip(id: prepared.id, vehicleId: prepared.vehicleId)
        if existing == nil {
            context.insert(trip)
        }
        try write(prepared, onto: trip, context: context)
        try context.save()
    }

    static func split(originalID: UUID, left: TripDraft, right: TripDraft, context: ModelContext, now: Date = .now) throws {
        let trips = try context.fetch(FetchDescriptor<Trip>())
        if let original = trips.first(where: { $0.id == originalID }) {
            original.deletedAt = now
            original.updatedAt = now
            addRevision("Split into two trips.", to: original, at: now, context: context)
        }
        for portion in [left, right] {
            let trip = Trip(id: portion.id, vehicleId: portion.vehicleId)
            context.insert(trip)
            try write(portion, onto: trip, context: context)
        }
        try context.save()
    }

    static func merge(result: TripDraft, originalIDs: [UUID], context: ModelContext, now: Date = .now) throws {
        let trips = try context.fetch(FetchDescriptor<Trip>())
        for id in originalIDs {
            guard let original = trips.first(where: { $0.id == id }) else { continue }
            original.deletedAt = now
            original.updatedAt = now
            addRevision("Merged into another trip.", to: original, at: now, context: context)
        }
        let trip = Trip(id: result.id, vehicleId: result.vehicleId)
        context.insert(trip)
        try write(result, onto: trip, context: context)
        try context.save()
    }

    static func softDelete(_ trip: Trip, context: ModelContext, now: Date = .now) throws {
        trip.deletedAt = now
        trip.updatedAt = now
        addRevision("Moved this trip to Recently Deleted.", to: trip, at: now, context: context)
        try context.save()
    }

    static func restore(_ trip: Trip, context: ModelContext, isPlus: Bool, now: Date = .now) throws {
        if !isPlus {
            let dates = try context.fetch(FetchDescriptor<Trip>())
                .filter { $0.deletedAt == nil }
                .map(\.startedAt)
            if Quota.count(startDates: dates, now: trip.startedAt) >= Quota.monthlyFreeTrips {
                throw LedgerError.quota
            }
        }
        trip.deletedAt = nil
        trip.updatedAt = now
        addRevision("Restored this trip.", to: trip, at: now, context: context)
        try context.save()
    }

    static func purge(_ trip: Trip, context: ModelContext) throws {
        context.delete(trip)
        try context.save()
    }

    static func monthCount(context: ModelContext, now: Date) -> Int {
        let dates = ((try? context.fetch(FetchDescriptor<Trip>())) ?? [])
            .filter { $0.deletedAt == nil }
            .map(\.startedAt)
        return Quota.count(startDates: dates, now: now)
    }

    private static func write(_ draft: TripDraft, onto trip: Trip, context: ModelContext) throws {
        let records = records(context: context)
        let priced = LedgerMath.price(draft, records: records)
        trip.vehicleId = draft.vehicleId
        trip.startedAt = draft.startedAt
        trip.endedAt = draft.endedAt
        trip.startAddress = draft.startAddress
        trip.endAddress = draft.endAddress
        trip.startLatitude = draft.startCoordinate?.latitude
        trip.startLongitude = draft.startCoordinate?.longitude
        trip.endLatitude = draft.endCoordinate?.latitude
        trip.endLongitude = draft.endCoordinate?.longitude
        trip.trackData = try JSONCodec.encode(draft.track)
        trip.originData = try draft.origin.map { try JSONCodec.encode($0) } ?? Data()
        trip.trimStart = draft.trimStart
        trip.trimEnd = draft.trimEnd
        trip.milesThousandths = draft.milesThousandths
        trip.trackedMilesThousandths = draft.trackedMilesThousandths
        trip.mileageOverridden = draft.mileageOverridden
        trip.placesEdited = draft.placesEdited
        trip.isEdited = draft.isEdited
        trip.categoryRaw = draft.category.rawValue
        trip.purpose = draft.purpose
        trip.notes = draft.notes
        trip.sourceRaw = draft.source.rawValue
        trip.hasRate = priced.match != nil
        trip.rateTenths = priced.match?.centsTenths ?? 0
        trip.rateLabel = priced.match?.label ?? ""
        trip.amountCents = priced.amountCents ?? 0
        trip.updatedAt = Date()
        let vehicles = try context.fetch(FetchDescriptor<Vehicle>())
        trip.vehicle = vehicles.first { $0.id == draft.vehicleId }
        try syncExpenses(draft.expenses, trip: trip, context: context)
        syncRevisions(draft.revisions, trip: trip, context: context)
    }

    private static func syncExpenses(_ drafts: [ExpenseDraft], trip: Trip, context: ModelContext) throws {
        let existing = trip.expenses ?? []
        let ids = Set(drafts.map(\.id))
        for expense in existing where !ids.contains(expense.id) {
            context.delete(expense)
        }
        for item in drafts {
            if let expense = existing.first(where: { $0.id == item.id }) {
                expense.date = item.date
                expense.typeRaw = item.type.rawValue
                expense.amountCents = item.amountCents
                expense.notes = item.notes
                expense.photoData = item.photoData
            } else {
                let expense = Expense(
                    id: item.id,
                    date: item.date,
                    type: item.type,
                    amountCents: item.amountCents,
                    notes: item.notes,
                    photoData: item.photoData
                )
                expense.trip = trip
                context.insert(expense)
            }
        }
    }

    private static func syncRevisions(_ drafts: [RevisionDraft], trip: Trip, context: ModelContext) {
        let existing = Set((trip.revisions ?? []).map(\.id))
        for item in drafts where !existing.contains(item.id) {
            let revision = TripRevision(id: item.id, at: item.at, summary: item.summary)
            revision.trip = trip
            context.insert(revision)
        }
    }

    private static func addRevision(_ summary: String, to trip: Trip, at date: Date, context: ModelContext) {
        let revision = TripRevision(at: date, summary: summary)
        revision.trip = trip
        context.insert(revision)
    }

    private static func coordinate(_ latitude: Double?, _ longitude: Double?) -> Coordinate? {
        guard let latitude, let longitude else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }
}
