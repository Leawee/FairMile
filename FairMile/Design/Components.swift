import SwiftUI
import UIKit

enum Theme {
    static let recording = Color(red: 0.70, green: 0.16, blue: 0.14)
    static let charity = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.93, green: 0.69, blue: 0.42, alpha: 1)
            : UIColor(red: 0.62, green: 0.40, blue: 0.12, alpha: 1)
    })
    static let medical = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.62, green: 0.76, blue: 0.90, alpha: 1)
            : UIColor(red: 0.22, green: 0.40, blue: 0.62, alpha: 1)
    })

    static func tint(_ category: TripCategory) -> Color {
        switch category {
        case .business: .accentColor
        case .personal: .secondary
        case .charity: charity
        case .medical: medical
        }
    }
}

struct DisclaimerText: View {
    var body: some View {
        Text(Copy.notTaxAdvice)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SummaryCard: View {
    var summary: LedgerSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(summary.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(Format.miles(summary.businessMilesThousandths, decimals: 1))
                    .font(.system(size: 44, weight: .semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("business mi")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(Format.miles(summary.businessMilesThousandths, decimals: 1)) business miles")
            Text(Format.currency(cents: summary.businessAmountCents))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Estimated deduction \(Format.currency(cents: summary.businessAmountCents))")
            if summary.slices.isEmpty {
                Text("No business deduction in this range yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(summary.slices) { slice in
                        HStack {
                            Text(Format.rate(slice.rateTenths))
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 64, alignment: .leading)
                            Text(slice.label)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text(Format.miles(slice.milesThousandths, decimals: 1))
                                .font(.subheadline.monospacedDigit())
                            Text(Format.currency(cents: slice.amountCents))
                                .font(.subheadline.monospacedDigit())
                                .frame(width: 84, alignment: .trailing)
                        }
                    }
                }
            }
            if summary.charityMilesThousandths > 0 || summary.medicalMilesThousandths > 0 || summary.personalMilesThousandths > 0 || summary.expenseCents > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    extra("Charity", miles: summary.charityMilesThousandths, cents: summary.charityAmountCents, deducted: true)
                    extra("Medical", miles: summary.medicalMilesThousandths, cents: summary.medicalAmountCents, deducted: true)
                    if summary.personalMilesThousandths > 0 {
                        Text("Personal \(Format.miles(summary.personalMilesThousandths, decimals: 1)) mi · not deducted")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if summary.expenseCents > 0 {
                        Text("Receipts \(Format.currency(cents: summary.expenseCents))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private func extra(_ title: String, miles: Int, cents: Int, deducted: Bool) -> some View {
        if miles > 0 {
            Text("\(title) \(Format.miles(miles, decimals: 1)) mi · \(deducted ? Format.currency(cents: cents) : "not deducted")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct TripRow: View {
    var draft: TripDraft
    var vehicleName: String
    var priced: PricedTrip

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(draft.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.category == .business ? Theme.charity : .primary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(Format.miles(draft.milesThousandths, decimals: 1))
                    .font(.body.monospacedDigit().weight(.semibold))
                Text(amount)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        let purpose = draft.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        if purpose.isEmpty, draft.category == .business { return "Add a business purpose" }
        if purpose.isEmpty { return draft.category.title }
        return purpose
    }

    private var subtitle: String {
        var parts = [Format.date(draft.startedAt), draft.category.title]
        if !vehicleName.isEmpty { parts.append(vehicleName) }
        if draft.isEdited { parts.append("Edited") }
        return parts.joined(separator: " · ")
    }

    private var amount: String {
        if draft.category == .personal { return "Not deducted" }
        if let cents = priced.amountCents { return Format.currency(cents: cents) }
        return "No rate"
    }
}
