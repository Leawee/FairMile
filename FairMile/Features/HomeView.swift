import SwiftData
import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query(sort: \RatePeriod.startDay) private var rateRows: [RatePeriod]
    @State private var editingID: UUID?
    @State private var manualDraft: TripDraft?
    @State private var showDenied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SummaryCard(summary: summary)
                    quotaLine
                    if app.recorder.phase != .idle && !app.showRecorder {
                        recoveryBanner
                    }
                    if recent.isEmpty {
                        ContentUnavailableView(
                            "No trips yet",
                            systemImage: "car",
                            description: Text("Start one when you leave, or add a trip you already drove.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    } else {
                        Text("Recent")
                            .font(.title3.weight(.semibold))
                        ForEach(recent) { draft in
                            Button {
                                editingID = draft.id
                            } label: {
                                TripRow(
                                    draft: draft,
                                    vehicleName: vehicleName(draft.vehicleId),
                                    priced: LedgerMath.price(draft, records: records)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    DisclaimerText()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("FairMile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add trip", systemImage: "plus") { openManual() }
                        .accessibilityLabel("Add a past trip")
                }
            }
            .safeAreaInset(edge: .bottom) {
                startBar
            }
            .navigationDestination(item: $editingID) { id in
                TripEditorScreen(tripID: id)
            }
            .navigationDestination(item: $manualDraft) { draft in
                TripEditorView(draft: draft, isReview: false)
            }
            .alert("Location is off", isPresented: $showDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Not now", role: .cancel) {}
            } message: {
                Text(Copy.locationUsage)
            }
            .onChange(of: app.recorder.phase) { _, phase in
                if phase == .recording, app.recorder.locationRunning {
                    app.showRecorder = true
                }
            }
        }
    }

    private var startBar: some View {
        VStack(spacing: 8) {
            Button {
                if app.recorder.phase == .idle {
                    guard let vehicle = defaultVehicle else { return }
                    app.recorder.start(vehicleId: vehicle.id)
                    if app.recorder.denied { showDenied = true }
                } else {
                    app.showRecorder = true
                }
            } label: {
                Text(app.recorder.phase == .idle ? "Start trip" : "Open trip")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(defaultVehicle == nil && app.recorder.phase == .idle)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .background(.bar)
    }

    private var quotaLine: some View {
        HStack {
            if app.purchases.isPlus {
                Text("Unlimited trips")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(monthCount) of \(Quota.monthlyFreeTrips) free trips in \(Format.monthYear(.now))")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Unlimited") { app.showPaywall = true }
            }
        }
        .font(.subheadline)
    }

    private var recoveryBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(bannerTitle)
                .font(.headline)
            if let started = app.recorder.startedAt {
                Text("Started \(Format.time(started)) · \(Format.miles(app.recorder.acceptance.milesThousandths, decimals: 1)) mi")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if app.recorder.phase == .review {
                    Button("Review") { app.showRecorder = true }
                        .buttonStyle(.borderedProminent)
                    Button("Discard", role: .destructive) { app.recorder.clear() }
                } else if app.recorder.locationRunning {
                    Button("Open map") { app.showRecorder = true }
                        .buttonStyle(.borderedProminent)
                    Button("End trip") {
                        app.recorder.end()
                        app.showRecorder = true
                    }
                } else {
                    Button("Continue") {
                        app.recorder.continueRecording()
                        if app.recorder.denied { showDenied = true }
                        if app.recorder.locationRunning { app.showRecorder = true }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("End trip") {
                        app.recorder.end()
                        app.showRecorder = true
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var bannerTitle: String {
        if app.recorder.phase == .review { return "A trip is waiting to be saved" }
        if app.recorder.locationRunning { return "Recording" }
        return "A trip is still open"
    }

    private var records: [RateRecord] {
        rateRows.compactMap(TripLibrary.record(from:))
    }

    private var liveDrafts: [TripDraft] {
        trips.filter { $0.deletedAt == nil }.map(TripLibrary.draft(from:))
    }

    private var recent: [TripDraft] {
        Array(liveDrafts.prefix(8))
    }

    private var summary: LedgerSummary {
        let scoped: [TripDraft]
        let title: String
        if app.purchases.isPlus {
            let year = Format.year(of: .now)
            scoped = liveDrafts.filter { Format.year(of: $0.startedAt) == year }
            title = String(year)
        } else {
            scoped = liveDrafts.filter { Format.isInLast30Days($0.startedAt, now: .now) }
            title = "Last 30 days"
        }
        return LedgerMath.summary(drafts: scoped, records: records, title: title)
    }

    private var monthCount: Int {
        Quota.count(startDates: liveDrafts.map(\.startedAt), now: .now)
    }

    private var defaultVehicle: Vehicle? {
        vehicles.first(where: \.isDefault) ?? vehicles.first
    }

    private func vehicleName(_ id: UUID) -> String {
        vehicles.first { $0.id == id }?.displayName ?? ""
    }

    private func openManual() {
        guard let vehicle = defaultVehicle else { return }
        if !app.purchases.isPlus, monthCount >= Quota.monthlyFreeTrips {
            app.showPaywall = true
            return
        }
        manualDraft = TripDraft.manual(vehicleId: vehicle.id, now: .now)
    }
}
