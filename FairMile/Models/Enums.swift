import Foundation

enum TripCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case business
    case personal
    case charity
    case medical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .business: "Business"
        case .personal: "Personal"
        case .charity: "Charity"
        case .medical: "Medical"
        }
    }

    var hint: String {
        switch self {
        case .business: "Counted in the deduction estimate"
        case .personal: "Kept in the log, not deducted"
        case .charity: "Uses the charitable rate"
        case .medical: "Uses the medical rate"
        }
    }
}

enum ExpenseType: String, Codable, CaseIterable, Identifiable, Sendable {
    case parking
    case toll
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .parking: "Parking"
        case .toll: "Toll"
        case .other: "Other"
        }
    }
}

enum TripSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case session
    case manual
    case split
    case merge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .session: "Recorded"
        case .manual: "Entered"
        case .split: "Split"
        case .merge: "Merged"
        }
    }
}

enum LedgerError: LocalizedError {
    case quota
    case invalidTimes
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .quota:
            "This month already has 15 trips. FairMile Plus removes the limit."
        case .invalidTimes:
            "The end time needs to be after the start time."
        case .saveFailed:
            "The trip could not be saved."
        }
    }
}
