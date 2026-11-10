import SwiftData
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var iCloudNote = false

    var body: some View {
        NavigationStack {
            Form {
                Section("FairMile Plus") {
                    if app.purchases.isPlus {
                        Text("Plus is active on this Apple ID.")
                    } else {
                        Text("Free includes 15 trips a month and a 30-day summary.")
                            .foregroundStyle(.secondary)
                    }
                    Button("Plans and trial") { app.showPaywall = true }
                    Button("Restore purchases") {
                        Task { await app.purchases.restore() }
                    }
                }
                Section {
                    NavigationLink("Vehicles") { VehiclesView() }
                    NavigationLink("Mileage rates") { RatesView() }
                    NavigationLink("Recently deleted") { TrashView() }
                }
                Section("iCloud") {
                    Toggle("Private iCloud copy", isOn: iCloudBinding)
                    Text("Off by default. FairMile has no server of its own. Close the app and open it again after changing this. If iCloud cannot start, the log stays on this iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Location") {
                    Text(Copy.locationUsage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("About") {
                    Link("Privacy Policy", destination: Copy.privacyPolicyURL)
                    DisclaimerText()
                    Text(Copy.notTheIRS)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let error = app.purchases.loadError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Reopen FairMile", isPresented: $iCloudNote) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Close FairMile from the app switcher and open it again. The log stays on this iPhone if iCloud is not available.")
            }
        }
    }

    private var iCloudBinding: Binding<Bool> {
        Binding(
            get: { app.iCloudEnabled },
            set: { newValue in
                app.setICloud(newValue)
                iCloudNote = true
            }
        )
    }
}

struct VehiclesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @State private var editor: VehicleEditorRoute?
    @State private var message: String?

    var body: some View {
        List {
            ForEach(vehicles) { vehicle in
                Button {
                    editor = VehicleEditorRoute(vehicle: vehicle)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(vehicle.displayName)
                            if vehicle.isDefault {
                                Text("Default")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                        if !vehicle.detailLine.isEmpty {
                            Text(vehicle.detailLine)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Vehicles")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") {
                    editor = VehicleEditorRoute(vehicle: nil)
                }
            }
        }
        .sheet(item: $editor) { route in
            VehicleForm(vehicle: route.vehicle, vehicles: vehicles, trips: trips)
        }
        .alert("Vehicle", isPresented: messagePresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private var messagePresented: Binding<Bool> {
        Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    }
}

struct VehicleEditorRoute: Identifiable {
    let id = UUID()
    let vehicle: Vehicle?
}

struct VehicleForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var vehicle: Vehicle?
    var vehicles: [Vehicle]
    var trips: [Trip]
    @State private var name = ""
    @State private var year = ""
    @State private var make = ""
    @State private var modelName = ""
    @State private var isDefault = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Year", text: $year)
                    .keyboardType(.numberPad)
                TextField("Make", text: $make)
                TextField("Model", text: $modelName)
                Toggle("Default vehicle", isOn: $isDefault)
                if vehicle != nil {
                    Button("Delete vehicle", role: .destructive, action: deleteVehicle)
                }
            }
            .navigationTitle(vehicle == nil ? "New vehicle" : "Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .onAppear {
                name = vehicle?.name ?? ""
                year = vehicle?.year.map(String.init) ?? ""
                make = vehicle?.make ?? ""
                modelName = vehicle?.modelName ?? ""
                isDefault = vehicle?.isDefault ?? vehicles.isEmpty
            }
            .alert("Vehicle", isPresented: messagePresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var messagePresented: Binding<Bool> {
        Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            message = "Give the vehicle a name."
            return
        }
        let target = vehicle ?? Vehicle(name: trimmed)
        if vehicle == nil { context.insert(target) }
        target.name = trimmed
        target.year = Int(year)
        target.make = make.trimmingCharacters(in: .whitespacesAndNewlines)
        target.modelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if isDefault {
            for item in vehicles where item.id != target.id { item.isDefault = false }
            target.isDefault = true
        } else if vehicles.allSatisfy({ $0.id == target.id || !$0.isDefault }) {
            target.isDefault = true
        } else {
            target.isDefault = false
        }
        try? context.save()
        dismiss()
    }

    private func deleteVehicle() {
        guard let vehicle else { return }
        if vehicles.count <= 1 {
            message = "Keep at least one vehicle."
            return
        }
        if trips.contains(where: { $0.deletedAt == nil && ($0.vehicleId == vehicle.id || $0.vehicle?.id == vehicle.id) }) {
            message = "This vehicle still has trips. Move those trips first."
            return
        }
        context.delete(vehicle)
        try? context.save()
        dismiss()
    }
}

struct RatesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RatePeriod.startDay) private var rows: [RatePeriod]
    @State private var showAdd = false

    var body: some View {
        List {
            ForEach(grouped, id: \.year) { group in
                Section(group.year) {
                    ForEach(group.rows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(categoryTitle(row.categoryRaw)) · \(Format.rate(row.centsTenths))")
                                .font(.body.weight(.semibold))
                            Text("\(Format.prettyDay(row.startDay)) – \(Format.prettyDay(row.endDay))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(row.source == "IRS" ? row.notice : "Custom rate")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        delete(offsets, in: group.rows)
                    }
                }
            }
            Section {
                Text("If two custom rates overlap, FairMile uses the one that starts later. IRS rows stay in the list and a custom row wins for the same dates.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(Copy.notTheIRS)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Mileage rates")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") { showAdd = true }
            }
        }
        .sheet(isPresented: $showAdd) {
            RateForm()
        }
    }

    private var grouped: [(year: String, rows: [RatePeriod])] {
        let years = Set(rows.map { String($0.startDay.prefix(4)) }).sorted(by: >)
        return years.map { year in
            (year, rows.filter { $0.startDay.hasPrefix(year) }.sorted { $0.startDay > $1.startDay })
        }
    }

    private func categoryTitle(_ raw: String) -> String {
        TripCategory(rawValue: raw)?.title ?? raw
    }

    private func delete(_ offsets: IndexSet, in group: [RatePeriod]) {
        for index in offsets {
            let row = group[index]
            guard row.source == "custom" else { continue }
            context.delete(row)
        }
        try? context.save()
    }
}

struct RateForm: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var category: TripCategory = .business
    @State private var start = Date()
    @State private var end = Date()
    @State private var cents = ""
    @State private var notice = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Category", selection: $category) {
                    ForEach(TripCategory.allCases.filter { $0 != .personal }) { item in
                        Text(item.title).tag(item)
                    }
                }
                DatePicker("Starts", selection: $start, displayedComponents: .date)
                DatePicker("Ends", selection: $end, displayedComponents: .date)
                TextField("Cents per mile", text: $cents)
                    .keyboardType(.decimalPad)
                TextField("Source note", text: $notice)
            }
            .navigationTitle("Add rate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .alert("Rate", isPresented: messagePresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var messagePresented: Binding<Bool> {
        Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    }

    private func save() {
        guard let tenths = Format.rateTenths(fromCents: cents) else {
            message = "Enter the cents per mile, such as 72.5."
            return
        }
        let startDay = Format.dayString(start)
        let endDay = Format.dayString(end)
        guard endDay >= startDay else {
            message = "The end date needs to be on or after the start date."
            return
        }
        context.insert(
            RatePeriod(
                category: category,
                startDay: startDay,
                endDay: endDay,
                centsTenths: tenths,
                source: "custom",
                notice: notice.trimmingCharacters(in: .whitespacesAndNewlines),
                createdAt: .now
            )
        )
        try? context.save()
        dismiss()
    }
}

struct TrashView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @State private var message: String?

    var body: some View {
        List {
            if deleted.isEmpty {
                ContentUnavailableView("Nothing deleted", systemImage: "trash", description: Text("Deleted trips stay here until you remove them."))
            } else {
                ForEach(deleted) { trip in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(trip.purpose.isEmpty ? (TripCategory(rawValue: trip.categoryRaw)?.title ?? "Trip") : trip.purpose)
                        Text("\(Format.date(trip.startedAt)) · \(Format.miles(trip.milesThousandths, decimals: 1)) mi")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Restore") { restore(trip) }
                            Button("Delete forever", role: .destructive) { purge(trip) }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Recently deleted")
        .alert("Trip", isPresented: messagePresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private var deleted: [Trip] {
        trips.filter { $0.deletedAt != nil }
    }

    private var messagePresented: Binding<Bool> {
        Binding(get: { message != nil }, set: { if !$0 { message = nil } })
    }

    private func restore(_ trip: Trip) {
        do {
            try TripLibrary.restore(trip, context: context, isPlus: app.purchases.isPlus)
        } catch {
            message = error.localizedDescription
        }
    }

    private func purge(_ trip: Trip) {
        try? TripLibrary.purge(trip, context: context)
    }
}
