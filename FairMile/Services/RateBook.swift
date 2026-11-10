import Foundation

struct RateRecord: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id: UUID
    var category: TripCategory
    var startDay: String
    var endDay: String
    var centsTenths: Int
    var source: String
    var notice: String
    var createdAt: Date
}

struct RateMatch: Equatable, Sendable {
    var centsTenths: Int
    var startDay: String
    var endDay: String
    var notice: String
    var source: String
    var label: String
}

enum RateBookError: Error {
    case missingTable
}

struct BundledRateFile: Decodable {
    var version: Int
    var reviewed: String
    var source: String
    var periods: [Period]

    struct Period: Decodable {
        var category: String
        var start: String
        var end: String
        var cents: String
        var notice: String
    }
}

final class BundleToken: NSObject {}

enum RateBook {
    static func match(category: TripCategory, day: String, records: [RateRecord]) -> RateMatch? {
        guard category != .personal else { return nil }
        let matches = records.filter { $0.category == category && $0.startDay <= day && day <= $0.endDay }
        let custom = matches.filter { $0.source == "custom" }
        let pool = custom.isEmpty ? matches.filter { $0.source != "custom" } : custom
        guard let best = pool.max(by: { lhs, rhs in
            if lhs.startDay != rhs.startDay { return lhs.startDay < rhs.startDay }
            return lhs.createdAt < rhs.createdAt
        }) else { return nil }
        let label = "\(Format.rate(best.centsTenths)) per mile · \(Format.prettyDay(best.startDay))–\(Format.prettyDay(best.endDay))"
        return RateMatch(
            centsTenths: best.centsTenths,
            startDay: best.startDay,
            endDay: best.endDay,
            notice: best.notice,
            source: best.source,
            label: label
        )
    }

    static func amountCents(milesThousandths: Int, centsTenths: Int) -> Int {
        let product = Int64(milesThousandths) * Int64(centsTenths)
        let denominator: Int64 = 10_000
        if product >= 0 {
            return Int((product + denominator / 2) / denominator)
        }
        return Int((product - denominator / 2) / denominator)
    }

    static func loadBundled(bundle: Bundle = .main) throws -> [RateRecord] {
        for candidate in [bundle, Bundle(for: BundleToken.self)] {
            if let url = candidate.url(forResource: "Rates", withExtension: "json") {
                return try records(from: Data(contentsOf: url))
            }
        }
        throw RateBookError.missingTable
    }

    static func records(from data: Data) throws -> [RateRecord] {
        let file = try JSONDecoder().decode(BundledRateFile.self, from: data)
        return try file.periods.map { period in
            guard let category = TripCategory(rawValue: period.category) else {
                throw RateBookError.missingTable
            }
            guard let decimal = Decimal(string: period.cents, locale: Locale(identifier: "en_US")) else {
                throw RateBookError.missingTable
            }
            let tenths = NSDecimalNumber(decimal: decimal * 10).rounding(accordingToBehavior: halfUp).intValue
            return RateRecord(
                id: UUID(),
                category: category,
                startDay: period.start,
                endDay: period.end,
                centsTenths: tenths,
                source: "IRS",
                notice: period.notice,
                createdAt: .distantPast
            )
        }
    }

    private static let halfUp = NSDecimalNumberHandler(
        roundingMode: .plain,
        scale: 0,
        raiseOnExactness: false,
        raiseOnOverflow: false,
        raiseOnUnderflow: false,
        raiseOnDivideByZero: false
    )
}
