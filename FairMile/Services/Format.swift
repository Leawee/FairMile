import Foundation

enum Format {
    static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = .current
        return calendar
    }

    static func dayString(_ date: Date) -> String {
        let parts = calendar().dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func prettyDay(_ day: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: day) else { return day }
        parser.dateFormat = "MMM d, yyyy"
        return parser.string(from: date)
    }

    static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = .current
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = .current
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    static func monthYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = .current
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    static func year(of date: Date) -> Int {
        calendar().component(.year, from: date)
    }

    static func isSameMonth(_ date: Date, _ other: Date) -> Bool {
        calendar().isDate(date, equalTo: other, toGranularity: .month)
    }

    static func isInLast30Days(_ date: Date, now: Date) -> Bool {
        guard let start = calendar().date(byAdding: .day, value: -30, to: now) else { return false }
        return date >= start && date <= now
    }

    static func clock(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }

    static func miles(_ thousandths: Int, decimals: Int) -> String {
        let number = NSDecimalNumber(decimal: Decimal(thousandths) / 1000)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        return formatter.string(from: number) ?? "0"
    }

    static func thousandths(fromMiles text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US")) else {
            return nil
        }
        if value < 0 { return 0 }
        let scaled = NSDecimalNumber(decimal: value * 1000).rounding(accordingToBehavior: halfUp)
        return scaled.intValue
    }

    static func cents(fromDollars text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "$", with: "")
        guard !trimmed.isEmpty, let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US")) else {
            return nil
        }
        if value < 0 { return 0 }
        let scaled = NSDecimalNumber(decimal: value * 100).rounding(accordingToBehavior: halfUp)
        return scaled.intValue
    }

    static func rateTenths(fromCents text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "¢", with: "")
        guard !trimmed.isEmpty, let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US")) else {
            return nil
        }
        if value <= 0 { return nil }
        let scaled = NSDecimalNumber(decimal: value * 10).rounding(accordingToBehavior: halfUp)
        return scaled.intValue
    }

    static func currency(cents: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        return formatter.string(from: NSDecimalNumber(decimal: Decimal(cents) / 100)) ?? "$0.00"
    }

    static func plainDollars(cents: Int) -> String {
        let sign = cents < 0 ? "-" : ""
        let absolute = abs(cents)
        return "\(sign)\(absolute / 100).\(String(format: "%02d", absolute % 100))"
    }

    static func rate(_ tenths: Int) -> String {
        rateDecimal(tenths) + "¢"
    }

    static func rateDecimal(_ tenths: Int) -> String {
        let cents = Decimal(tenths) / 10
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.minimumFractionDigits = tenths % 10 == 0 ? 0 : 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: cents as NSDecimalNumber) ?? "0"
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
