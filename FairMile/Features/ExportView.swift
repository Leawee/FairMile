import PDFKit
import SwiftData
import SwiftUI
import UIKit

struct ExportView: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query(sort: \RatePeriod.startDay) private var rateRows: [RatePeriod]
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var vehicleID: UUID?
    @State private var preview: Data?
    @State private var share: ShareFile?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Report") {
                    Picker("Year", selection: $year) {
                        ForEach(yearChoices, id: \.self) { value in
                            Text(String(value)).tag(value)
                        }
                    }
                    Picker("Vehicle", selection: $vehicleID) {
                        Text("All vehicles").tag(UUID?.none)
                        ForEach(vehicles) { vehicle in
                            Text(vehicle.displayName).tag(Optional(vehicle.id))
                        }
                    }
                }
                Section("Last 30 days") {
                    SummaryCard(summary: LedgerMath.summary(drafts: recentDrafts, records: records, title: "Last 30 days"))
                        .listRowInsets(EdgeInsets())
                    exportButtons(range: .last30Days, title: "Export last 30 days")
                }
                Section("Full year") {
                    if app.purchases.isPlus {
                        SummaryCard(summary: LedgerMath.summary(drafts: yearDrafts, records: records, title: String(year)))
                            .listRowInsets(EdgeInsets())
                        exportButtons(range: .year(year), title: "Export \(year)")
                    } else {
                        Text("The full-year PDF and CSV include every trip in the calendar year, with the rate for each start date.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("See FairMile Plus") { app.showPaywall = true }
                    }
                }
                Section {
                    DisclaimerText()
                    Text(Copy.notTheIRS)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Export")
            .sheet(item: $share) { item in
                ActivityView(url: item.url)
            }
            .sheet(isPresented: previewPresented) {
                NavigationStack {
                    if let preview {
                        PDFKitView(data: preview)
                            .ignoresSafeArea(edges: .bottom)
                            .navigationTitle("Preview")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { self.preview = nil } } }
                    }
                }
            }
            .alert("Export needs a fix", isPresented: messagePresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    @ViewBuilder
    private func exportButtons(range: ExportRange, title: String) -> some View {
        Button("\(title) PDF") { export(range: range, kind: .pdf) }
        Button("\(title) CSV") { export(range: range, kind: .csv) }
        Button("Preview PDF") { export(range: range, kind: .preview) }
    }

    private var records: [RateRecord] {
        rateRows.compactMap(TripLibrary.record(from:))
    }

    private var live: [TripDraft] {
        trips.filter { $0.deletedAt == nil }.map(TripLibrary.draft(from:))
    }

    private var recentDrafts: [TripDraft] {
        LedgerMath.filter(drafts: live, vehicleId: vehicleID, range: .last30Days, now: .now)
    }

    private var yearDrafts: [TripDraft] {
        LedgerMath.filter(drafts: live, vehicleId: vehicleID, range: .year(year), now: .now)
    }

    private var yearChoices: [Int] {
        let current = Format.year(of: .now)
        return Array((current - 2)...(current + 1))
    }

    private var names: [UUID: String] {
        Dictionary(uniqueKeysWithValues: vehicles.map { ($0.id, $0.displayName) })
    }

    private var previewPresented: Binding<Bool> {
        Binding(get: { preview != nil }, set: { if !$0 { preview = nil } })
    }

    private var messagePresented: Binding<Bool> {
        Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    }

    private func export(range: ExportRange, kind: ExportKind) {
        let drafts = LedgerMath.filter(drafts: live, vehicleId: vehicleID, range: range, now: .now)
        let check = LedgerMath.check(drafts: drafts, records: records, range: range, isPlus: app.purchases.isPlus)
        if check.needsPlus {
            app.showPaywall = true
            return
        }
        if !check.missingPurpose.isEmpty || !check.missingRate.isEmpty {
            var parts: [String] = []
            if !check.missingPurpose.isEmpty {
                parts.append("\(check.missingPurpose.count) business trip(s) still need a purpose.")
            }
            if !check.missingRate.isEmpty {
                parts.append("\(check.missingRate.count) trip(s) have no mileage rate on file.")
            }
            message = parts.joined(separator: " ")
            return
        }
        let heading = rangeLabel(range)
        let prepared = "\(vehicleID.flatMap { names[$0] } ?? "All vehicles") · Prepared \(Format.date(.now))"
        switch kind {
        case .preview, .pdf:
            let data = PDFExporter.make(drafts: drafts, records: records, vehicles: names, heading: heading, subtitle: prepared)
            if kind == .preview {
                preview = data
            } else if let url = try? write(data, name: "FairMile-\(fileToken(range)).pdf") {
                share = ShareFile(url: url)
            }
        case .csv:
            let csv = CSVExporter.make(drafts: drafts, records: records, vehicles: names)
            if let url = try? write(Data(csv.utf8), name: "FairMile-\(fileToken(range)).csv") {
                share = ShareFile(url: url)
            }
        }
    }

    private func rangeLabel(_ range: ExportRange) -> String {
        switch range {
        case .last30Days: "Last 30 days"
        case .year(let year): "Mileage log \(year)"
        }
    }

    private func fileToken(_ range: ExportRange) -> String {
        switch range {
        case .last30Days: "last-30-days"
        case .year(let year): String(year)
        }
    }

    private func write(_ data: Data, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}

private enum ExportKind { case pdf, csv, preview }

struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct PDFKitView: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }
    func updateUIView(_ uiView: PDFView, context: Context) {}
}
