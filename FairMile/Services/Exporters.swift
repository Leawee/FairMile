import Foundation
import PDFKit
import UIKit

enum CSVExporter {
    static let headers = [
        "Date", "Start time", "End time", "Vehicle", "From", "To", "Miles",
        "Category", "Purpose", "Notes", "Rate cents per mile", "Rate period",
        "Estimated deduction USD", "Edited", "Source", "Expense USD", "Expense detail"
    ]

    static func make(drafts: [TripDraft], records: [RateRecord], vehicles: [UUID: String]) -> String {
        var lines = [headers.map(cell).joined(separator: ",")]
        for draft in drafts {
            let priced = LedgerMath.price(draft, records: records)
            let expenseCents = draft.expenses.reduce(0) { $0 + $1.amountCents }
            let detail = draft.expenses
                .map { "\($0.type.title) \(Format.currency(cents: $0.amountCents))" }
                .joined(separator: "; ")
            let row = [
                Format.dayString(draft.startedAt),
                Format.time(draft.startedAt),
                Format.time(draft.endedAt),
                vehicles[draft.vehicleId] ?? "",
                draft.startAddress,
                draft.endAddress,
                Format.miles(draft.milesThousandths, decimals: 2),
                draft.category.title,
                draft.purpose,
                draft.notes,
                priced.match.map { Format.rateDecimal($0.centsTenths) } ?? "",
                priced.match.map { "\(Format.prettyDay($0.startDay)) – \(Format.prettyDay($0.endDay))" } ?? "",
                priced.amountCents.map { Format.plainDollars(cents: $0) } ?? "",
                draft.isEdited ? "yes" : "no",
                draft.source.title,
                Format.plainDollars(cents: expenseCents),
                detail
            ]
            lines.append(row.map(cell).joined(separator: ","))
        }
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }

    static func cell(_ value: String) -> String {
        var text = value.replacingOccurrences(of: "\"", with: "\"\"")
        if let first = text.first, "=+-@".contains(first) {
            text = "'" + text
        }
        if text.contains(",") || text.contains("\"") || text.contains("\n") || text.contains("\r") || text.hasPrefix("'") {
            return "\"\(text)\""
        }
        return text
    }
}

enum PDFExporter {
    static func make(drafts: [TripDraft], records: [RateRecord], vehicles: [UUID: String], heading: String, subtitle: String) -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 40
        let width = page.width - margin * 2
        let bottom = page.height - 52
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { context in
            var y = margin

            func beginPage() {
                context.beginPage()
                y = margin
                let footer = "\(Copy.notTaxAdvice) \(Copy.notTheIRS)"
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 8),
                    .foregroundColor: UIColor.secondaryLabel
                ]
                (footer as NSString).draw(
                    in: CGRect(x: margin, y: page.height - 32, width: width, height: 20),
                    withAttributes: attributes
                )
            }

            func paint(_ text: String, font: UIFont, color: UIColor, gap: CGFloat) {
                let height = measured(text, font: font, width: width)
                if y + height > bottom {
                    beginPage()
                }
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]
                (text as NSString).draw(
                    with: CGRect(x: margin, y: y, width: width, height: height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                )
                y += height + gap
            }

            beginPage()
            paint("FairMile", font: .systemFont(ofSize: 22, weight: .semibold), color: .label, gap: 4)
            paint(heading, font: .systemFont(ofSize: 14, weight: .medium), color: .label, gap: 2)
            paint(subtitle, font: .systemFont(ofSize: 11), color: .secondaryLabel, gap: 8)
            paint(Copy.notTaxAdvice, font: .systemFont(ofSize: 10), color: .secondaryLabel, gap: 2)
            paint(Copy.notTheIRS, font: .systemFont(ofSize: 10), color: .secondaryLabel, gap: 12)

            let summary = LedgerMath.summary(drafts: drafts, records: records, title: heading)
            paint(
                "Business \(Format.miles(summary.businessMilesThousandths, decimals: 2)) mi · \(Format.currency(cents: summary.businessAmountCents))",
                font: .systemFont(ofSize: 13, weight: .semibold),
                color: .label,
                gap: 4
            )
            for slice in summary.slices {
                paint(
                    "\(Format.rate(slice.rateTenths)) · \(slice.label) · \(Format.miles(slice.milesThousandths, decimals: 2)) mi · \(Format.currency(cents: slice.amountCents))",
                    font: .systemFont(ofSize: 10),
                    color: .secondaryLabel,
                    gap: 2
                )
            }
            if summary.charityMilesThousandths > 0 {
                paint(categoryLine("Charity", miles: summary.charityMilesThousandths, cents: summary.charityAmountCents), font: .systemFont(ofSize: 10), color: .secondaryLabel, gap: 2)
            }
            if summary.medicalMilesThousandths > 0 {
                paint(categoryLine("Medical", miles: summary.medicalMilesThousandths, cents: summary.medicalAmountCents), font: .systemFont(ofSize: 10), color: .secondaryLabel, gap: 2)
            }
            if summary.personalMilesThousandths > 0 {
                paint("Personal \(Format.miles(summary.personalMilesThousandths, decimals: 2)) mi · not deducted", font: .systemFont(ofSize: 10), color: .secondaryLabel, gap: 2)
            }
            if summary.expenseCents > 0 {
                paint("Receipts \(Format.currency(cents: summary.expenseCents)). \(Copy.standardMileageReminder)", font: .systemFont(ofSize: 10), color: .secondaryLabel, gap: 2)
            }
            paint(Copy.editedMeaning, font: .systemFont(ofSize: 9), color: .tertiaryLabel, gap: 14)

            for draft in drafts {
                paint(tripBlock(draft, records: records, vehicles: vehicles), font: .systemFont(ofSize: 10), color: .label, gap: 10)
            }
        }
    }

    static func document(drafts: [TripDraft], records: [RateRecord], vehicles: [UUID: String], heading: String, subtitle: String) -> PDFDocument {
        PDFDocument(data: make(drafts: drafts, records: records, vehicles: vehicles, heading: heading, subtitle: subtitle)) ?? PDFDocument()
    }

    private static func tripBlock(_ draft: TripDraft, records: [RateRecord], vehicles: [UUID: String]) -> String {
        let priced = LedgerMath.price(draft, records: records)
        let amount = priced.amountCents.map { Format.currency(cents: $0) } ?? "No rate"
        let rate = priced.match.map { Format.rate($0.centsTenths) } ?? "No rate"
        let from = draft.startAddress.isEmpty ? "Start not named" : draft.startAddress
        let to = draft.endAddress.isEmpty ? "End not named" : draft.endAddress
        let purpose = draft.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : draft.purpose
        let edited = draft.isEdited ? " · Edited" : ""
        let expenses = draft.expenses.map { "\($0.type.title) \(Format.currency(cents: $0.amountCents))" }.joined(separator: ", ")
        var lines = [
            "\(Format.date(draft.startedAt)) · \(Format.time(draft.startedAt))–\(Format.time(draft.endedAt)) · \(vehicles[draft.vehicleId] ?? "Vehicle") · \(draft.category.title)\(edited)",
            "\(from) → \(to)",
            "\(Format.miles(draft.milesThousandths, decimals: 2)) mi · \(rate) · \(amount)",
            "Purpose: \(purpose)"
        ]
        if !draft.notes.isEmpty { lines.append("Notes: \(draft.notes)") }
        if !expenses.isEmpty { lines.append("Receipts: \(expenses)") }
        return lines.joined(separator: "\n")
    }

    private static func categoryLine(_ name: String, miles: Int, cents: Int) -> String {
        "\(name) \(Format.miles(miles, decimals: 2)) mi · \(Format.currency(cents: cents))"
    }

    private static func measured(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        return ceil(bounds.height)
    }
}
