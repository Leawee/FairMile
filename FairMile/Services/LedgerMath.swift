import Foundation

struct PricedTrip: Equatable, Sendable {
    var match: RateMatch?
    var amountCents: Int?
    var explanation: String
}

struct LedgerSummary: Equatable, Sendable {
    struct Slice: Equatable, Identifiable, Sendable {
        var id: String
        var label: String
        var rateTenths: Int
        var milesThousandths: Int
        var amountCents: Int
    }

    var title: String
    var businessMilesThousandths: Int
    var businessAmountCents: Int
    var slices: [Slice]
    var charityMilesThousandths: Int
    var charityAmountCents: Int
    var medicalMilesThousandths: Int
    var medicalAmountCents: Int
    var personalMilesThousandths: Int
    var expenseCents: Int
    var tripCount: Int
    var missingPurposeCount: Int
}

enum ExportRange: Equatable, Sendable {
    case last30Days
    case year(Int)

    var requiresPlus: Bool {
        if case .year = self { return true }
        return false
    }
}

struct ExportCheck: Equatable, Sendable {
    var needsPlus: Bool
    var missingPurpose: [UUID]
    var missingRate: [UUID]

    var ready: Bool {
        !needsPlus && missingPurpose.isEmpty && missingRate.isEmpty
    }
}

enum Quota {
    static let monthlyFreeTrips = 15

    static func count(startDates: [Date], now: Date) -> Int {
        startDates.filter { Format.isSameMonth($0, now) }.count
    }
}

enum LedgerMath {
    static func price(_ draft: TripDraft, records: [RateRecord]) -> PricedTrip {
        let startDay = Format.dayString(draft.startedAt)
        let endDay = Format.dayString(draft.endedAt)
        if draft.category == .personal {
            return PricedTrip(
                match: nil,
                amountCents: 0,
                explanation: "Personal trips stay in the log and are left out of the deduction estimate."
            )
        }
        guard let match = RateBook.match(category: draft.category, day: startDay, records: records) else {
            return PricedTrip(
                match: nil,
                amountCents: nil,
                explanation: "No mileage rate is on file for \(Format.prettyDay(startDay)). The estimate stays blank until you add that rate."
            )
        }
        var parts = [match.label]
        if !match.notice.isEmpty {
            parts.append(match.notice)
        }
        if startDay != endDay {
            parts.append("This trip crosses midnight. The rate follows the start date.")
        }
        if endDay < match.startDay || endDay > match.endDay {
            parts.append("The \(Format.rate(match.centsTenths)) rate applies because the trip started on \(Format.date(draft.startedAt)). A different rate is on file for \(Format.date(draft.endedAt)).")
        }
        return PricedTrip(
            match: match,
            amountCents: RateBook.amountCents(milesThousandths: draft.milesThousandths, centsTenths: match.centsTenths),
            explanation: parts.joined(separator: " ")
        )
    }

    static func summary(drafts: [TripDraft], records: [RateRecord], title: String) -> LedgerSummary {
        var businessMiles = 0
        var businessAmount = 0
        var charityMiles = 0
        var charityAmount = 0
        var medicalMiles = 0
        var medicalAmount = 0
        var personalMiles = 0
        var expenses = 0
        var missingPurpose = 0
        var slices: [String: LedgerSummary.Slice] = [:]

        for draft in drafts {
            let priced = price(draft, records: records)
            expenses += draft.expenses.reduce(0) { $0 + $1.amountCents }
            switch draft.category {
            case .business:
                businessMiles += draft.milesThousandths
                if draft.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    missingPurpose += 1
                }
                if let amount = priced.amountCents, let match = priced.match {
                    businessAmount += amount
                    let key = "\(match.startDay)|\(match.endDay)|\(match.centsTenths)"
                    var slice = slices[key] ?? LedgerSummary.Slice(
                        id: key,
                        label: "\(Format.prettyDay(match.startDay))–\(Format.prettyDay(match.endDay))",
                        rateTenths: match.centsTenths,
                        milesThousandths: 0,
                        amountCents: 0
                    )
                    slice.milesThousandths += draft.milesThousandths
                    slice.amountCents += amount
                    slices[key] = slice
                }
            case .charity:
                charityMiles += draft.milesThousandths
                charityAmount += priced.amountCents ?? 0
            case .medical:
                medicalMiles += draft.milesThousandths
                medicalAmount += priced.amountCents ?? 0
            case .personal:
                personalMiles += draft.milesThousandths
            }
        }

        return LedgerSummary(
            title: title,
            businessMilesThousandths: businessMiles,
            businessAmountCents: businessAmount,
            slices: slices.values.sorted { $0.label < $1.label },
            charityMilesThousandths: charityMiles,
            charityAmountCents: charityAmount,
            medicalMilesThousandths: medicalMiles,
            medicalAmountCents: medicalAmount,
            personalMilesThousandths: personalMiles,
            expenseCents: expenses,
            tripCount: drafts.count,
            missingPurposeCount: missingPurpose
        )
    }

    static func filter(drafts: [TripDraft], vehicleId: UUID?, range: ExportRange, now: Date) -> [TripDraft] {
        drafts.filter { draft in
            if let vehicleId, draft.vehicleId != vehicleId { return false }
            switch range {
            case .last30Days:
                return Format.isInLast30Days(draft.startedAt, now: now)
            case .year(let year):
                return Format.year(of: draft.startedAt) == year
            }
        }
        .sorted { $0.startedAt < $1.startedAt }
    }

    static func check(drafts: [TripDraft], records: [RateRecord], range: ExportRange, isPlus: Bool) -> ExportCheck {
        var missingPurpose: [UUID] = []
        var missingRate: [UUID] = []
        for draft in drafts {
            if draft.category == .business,
               draft.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                missingPurpose.append(draft.id)
            }
            if draft.category != .personal, price(draft, records: records).match == nil {
                missingRate.append(draft.id)
            }
        }
        return ExportCheck(
            needsPlus: range.requiresPlus && !isPlus,
            missingPurpose: missingPurpose,
            missingRate: missingRate
        )
    }
}
