import SwiftUI
import SwiftData

struct TripListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query(sort: \RatePeriod.startDay) private var rateRows: [RatePeriod]
    @State private var category: TripCategory?
    @State private var vehicleID: UUID?
    @State private var query = ""
    @State private var editingID: UUID?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            filterChip("All", selected: category == nil) { category = nil }
                            ForEach(TripCategory.allCases) { item in
                                filterChip(item.title, selected: category == item) { category = item }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                if filtered.isEmpty {
                    ContentUnavailableView("No matching trips", systemImage: "line.3.horizontal.decrease.circle", description: Text("Try another category or vehicle."))
                } else {
                    ForEach(filtered) { draft in
                        Button {
                            editingID = draft.id
                        } label: {
                            TripRow(
                                draft: draft,
                                vehicleName: vehicles.first { $0.id == draft.vehicleId }?.displayName ?? "",
                                priced: LedgerMath.price(draft, records: records)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Trips")
            .searchable(text: $query, prompt: "Purpose or place")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Vehicle", systemImage: "car") {
                        Button("All vehicles") { vehicleID = nil }
                        ForEach(vehicles) { vehicle in
                            Button(vehicle.displayName) { vehicleID = vehicle.id }
                        }
                    }
                }
            }
            .navigationDestination(item: $editingID) { id in
                TripEditorScreen(tripID: id)
            }
        }
    }

    private var records: [RateRecord] {
        rateRows.compactMap(TripLibrary.record(from:))
    }

    private var filtered: [TripDraft] {
        trips.filter { $0.deletedAt == nil }.map(TripLibrary.draft(from:)).filter { draft in
            if let category, draft.category != category { return false }
            if let vehicleID, draft.vehicleId != vehicleID { return false }
            let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if needle.isEmpty { return true }
            let haystack = [draft.purpose, draft.notes, draft.startAddress, draft.endAddress].joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(needle)
        }
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .tint(selected ? Color.accentColor : Color.secondary)
            .controlSize(.small)
    }
}

struct TripEditorScreen: View {
    let tripID: UUID
    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]

    var body: some View {
        if let trip = trips.first(where: { $0.id == tripID && $0.deletedAt == nil }) {
            TripEditorView(draft: TripLibrary.draft(from: trip), isReview: false)
        } else {
            ContentUnavailableView("This trip is not in the log", systemImage: "car")
        }
    }
}
