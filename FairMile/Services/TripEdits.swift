import Foundation

enum TripEdits {
    static func divide(total: Int, fraction: Double) -> (Int, Int) {
        let clamped = min(max(fraction, 0.05), 0.95)
        let left = Int((Double(total) * clamped).rounded())
        return (max(0, left), max(0, total - left))
    }

    static func changes(from old: TripDraft, to new: TripDraft) -> [String] {
        var lines: [String] = []
        if old.milesThousandths != new.milesThousandths {
            lines.append("Changed miles from \(Format.miles(old.milesThousandths, decimals: 2)) to \(Format.miles(new.milesThousandths, decimals: 2)).")
        }
        if old.category != new.category {
            lines.append("Changed the category from \(old.category.title) to \(new.category.title).")
        }
        if old.purpose != new.purpose {
            lines.append("Changed the purpose.")
        }
        if old.notes != new.notes {
            lines.append("Changed the notes.")
        }
        if old.vehicleId != new.vehicleId {
            lines.append("Changed the vehicle.")
        }
        if old.startedAt != new.startedAt {
            lines.append("Changed the start time.")
        }
        if old.endedAt != new.endedAt {
            lines.append("Changed the end time.")
        }
        if old.startAddress != new.startAddress || old.endAddress != new.endAddress {
            lines.append("Updated a place name.")
        }
        if old.startCoordinate != new.startCoordinate
            || old.endCoordinate != new.endCoordinate
            || old.trimStart != new.trimStart
            || old.trimEnd != new.trimEnd {
            lines.append("Moved the start or end.")
        }
        if old.expenses != new.expenses {
            lines.append("Updated receipts.")
        }
        return lines
    }

    static func preparedForSave(baseline: TripDraft, edited: TripDraft, isNew: Bool, now: Date) -> TripDraft {
        var result = edited
        if result.origin == nil {
            result.origin = TripOrigin(draft: isNew ? result : baseline)
        }
        result.refreshEditedFlag()
        let lines: [String]
        if isNew, result.source == .manual {
            lines = ["Entered this trip by hand."]
        } else if isNew {
            lines = ["Recorded this trip."] + changes(from: baseline, to: result)
        } else {
            lines = changes(from: baseline, to: result)
        }
        for line in lines where !result.revisions.contains(where: { $0.summary == line && $0.at == now }) {
            result.revisions.append(RevisionDraft(id: UUID(), at: now, summary: line))
        }
        return result
    }

    static func split(
        _ draft: TripDraft,
        fraction: Double,
        rightPurpose: String,
        rightCategory: TripCategory,
        expenseIDsOnRight: Set<UUID>,
        now: Date
    ) -> (TripDraft, TripDraft) {
        let clamped = min(max(fraction, 0.05), 0.95)
        let (leftMiles, rightMiles) = divide(total: draft.milesThousandths, fraction: clamped)
        let included = draft.includedPoints
        let cut = TrackMath.split(points: included, fraction: clamped)
        let leftPoints = included.isEmpty ? [] : Array(included[0...min(cut.leftEnd, included.count - 1)])
        let rightPoints = included.isEmpty ? [] : Array(included[min(cut.rightStart, included.count - 1)...])
        let splitTime = splitDate(draft: draft, points: included, index: cut.leftEnd, fraction: clamped)

        var left = portion(
            from: draft,
            points: leftPoints,
            startedAt: draft.startedAt,
            endedAt: splitTime,
            miles: leftMiles,
            purpose: draft.purpose,
            category: draft.category,
            keepStartAddress: true,
            now: now
        )
        left.expenses = draft.expenses.filter { !expenseIDsOnRight.contains($0.id) }

        var right = portion(
            from: draft,
            points: rightPoints,
            startedAt: splitTime,
            endedAt: draft.endedAt,
            miles: rightMiles,
            purpose: rightPurpose,
            category: rightCategory,
            keepStartAddress: false,
            now: now
        )
        right.startAddress = ""
        right.endAddress = draft.endAddress
        right.expenses = draft.expenses.filter { expenseIDsOnRight.contains($0.id) }.map { expense in
            var copy = expense
            copy.id = UUID()
            return copy
        }
        return (left, right)
    }

    static func merge(
        _ first: TripDraft,
        _ second: TripDraft,
        purpose: String,
        category: TripCategory,
        now: Date
    ) -> TripDraft {
        let earlier = first.startedAt <= second.startedAt ? first : second
        let later = earlier.id == first.id ? second : first
        let points = joined(earlier.includedPoints, later.includedPoints)
        var result = earlier
        result.id = UUID()
        result.startedAt = min(earlier.startedAt, later.startedAt)
        result.endedAt = max(earlier.endedAt, later.endedAt)
        result.endAddress = later.endAddress
        result.endCoordinate = later.endCoordinate ?? later.includedPoints.last?.coordinate
        result.track = points
        result.trimStart = 0
        result.trimEnd = max(0, points.count - 1)
        result.milesThousandths = earlier.milesThousandths + later.milesThousandths
        result.trackedMilesThousandths = nil
        result.mileageOverridden = true
        result.placesEdited = false
        result.source = .merge
        result.category = category
        result.purpose = purpose
        result.notes = [earlier.notes, later.notes]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        result.expenses = earlier.expenses + later.expenses.map { expense in
            var copy = expense
            copy.id = UUID()
            return copy
        }
        result.revisions = [
            RevisionDraft(
                id: UUID(),
                at: now,
                summary: "Merged two adjacent trips. Miles were added together and were not remeasured from the map."
            )
        ]
        result.origin = TripOrigin(draft: result)
        result.refreshEditedFlag()
        return result
    }

    static func neighbors(of draft: TripDraft, in drafts: [TripDraft]) -> (previous: TripDraft?, next: TripDraft?) {
        let sameVehicle = drafts
            .filter { $0.vehicleId == draft.vehicleId && $0.id != draft.id }
            .sorted { $0.startedAt < $1.startedAt }
        let previous = sameVehicle.last { $0.startedAt < draft.startedAt }
        let next = sameVehicle.first { $0.startedAt > draft.startedAt }
        return (previous, next)
    }

    private static func splitDate(draft: TripDraft, points: [TrackSample], index: Int, fraction: Double) -> Date {
        let candidate: Date
        if points.indices.contains(index) {
            candidate = points[index].timestamp
        } else {
            let duration = draft.endedAt.timeIntervalSince(draft.startedAt)
            candidate = draft.startedAt.addingTimeInterval(duration * fraction)
        }
        return min(max(candidate, draft.startedAt), draft.endedAt)
    }

    private static func portion(
        from draft: TripDraft,
        points: [TrackSample],
        startedAt: Date,
        endedAt: Date,
        miles: Int,
        purpose: String,
        category: TripCategory,
        keepStartAddress: Bool,
        now: Date
    ) -> TripDraft {
        var portion = draft
        portion.id = UUID()
        portion.startedAt = startedAt
        portion.endedAt = endedAt
        portion.track = points
        portion.trimStart = 0
        portion.trimEnd = max(0, points.count - 1)
        portion.milesThousandths = miles
        portion.trackedMilesThousandths = draft.source == .session ? miles : draft.trackedMilesThousandths
        portion.startCoordinate = points.first?.coordinate ?? (keepStartAddress ? draft.startCoordinate : nil)
        portion.endCoordinate = points.last?.coordinate ?? (keepStartAddress ? nil : draft.endCoordinate)
        portion.startAddress = keepStartAddress ? draft.startAddress : ""
        portion.endAddress = keepStartAddress ? "" : draft.endAddress
        portion.purpose = purpose
        portion.category = category
        portion.notes = keepStartAddress ? draft.notes : ""
        portion.placesEdited = false
        portion.source = .split
        portion.expenses = []
        portion.revisions = [
            RevisionDraft(
                id: UUID(),
                at: now,
                summary: "Split from a trip that started \(Format.date(draft.startedAt))."
            )
        ]
        portion.origin = TripOrigin(draft: portion)
        portion.refreshEditedFlag()
        return portion
    }

    private static func joined(_ earlier: [TrackSample], _ later: [TrackSample]) -> [TrackSample] {
        guard let last = earlier.last, let first = later.first else { return earlier + later }
        let shift = last.segment + 1 - first.segment
        let moved = later.map { sample -> TrackSample in
            var copy = sample
            copy.segment += shift
            return copy
        }
        return earlier + moved
    }
}
