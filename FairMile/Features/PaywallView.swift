import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var buyingID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("FairMile Plus")
                        .font(.largeTitle.weight(.semibold))
                    Text("Edit every trip. Use the IRS rate for the day it started. Full-year PDF and CSV are included.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        label("Editable trips, including split and merge")
                        label("Rates by date, including a year that changes midstream")
                        label("Unlimited trips and receipt photos")
                        label("Full-year export, with nothing held back")
                    }
                    if let yearly = app.purchases.yearlyProduct() {
                        Button {
                            Task { await buy(yearly) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(app.purchases.trialText(for: yearly) ?? "Yearly")
                                    .font(.headline)
                                Text("\(yearly.displayPrice) per year")
                                    .font(.subheadline)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(buyingID != nil)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Yearly · 7-day free trial")
                                .font(.headline)
                            Text("$39.99 per year")
                                .font(.subheadline)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    ForEach(app.purchases.orderedProducts.filter { $0.id != PlusProduct.yearly.rawValue }) { product in
                        Button {
                            Task { await buy(product) }
                        } label: {
                            HStack {
                                Text(product.displayName)
                                Spacer()
                                Text(priceLine(product))
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(buyingID != nil)
                    }
                    if app.purchases.products.isEmpty {
                        Text("Monthly $4.99 · Lifetime $79.99")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        #if DEBUG
                        if !ScreenshotSample.isRequested {
                            Text(app.purchases.loadError ?? "Prices load from the App Store.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        #else
                        Text(app.purchases.loadError ?? "Prices load from the App Store.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        #endif
                    }
                    Button("Restore purchases") {
                        Task { await app.purchases.restore() }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    DisclaimerText()
                    Text("The trial is on the yearly plan. You can cancel in Apple subscriptions before it ends.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func label(_ text: String) -> some View {
        Label(text, systemImage: "checkmark")
            .font(.body)
    }

    private func priceLine(_ product: Product) -> String {
        if product.type == .nonConsumable { return product.displayPrice }
        if product.subscription?.subscriptionPeriod.unit == .month { return "\(product.displayPrice) / month" }
        return product.displayPrice
    }

    private func buy(_ product: Product) async {
        buyingID = product.id
        let unlocked = await app.purchases.purchase(product)
        buyingID = nil
        if unlocked { dismiss() }
    }
}
