import MapKit
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct TripEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @Query(sort: \RatePeriod.startDay) private var rateRows: [RatePeriod]

    @State private var draft: TripDraft
    @State private var baseline: TripDraft
    @State private var milesField: String
    @State private var placeMode: PlaceMode = .view
    @State private var position: MapCameraPosition = .automatic
    @State private var didFit = false
    @State private var showSplit = false
    @State private var showMerge = false
    @State private var showDiscardConfirm = false
    @State private var showResumeConfirm = false
    @State private var expenseEdit: ExpenseDraft?
    @State private var errorMessage: String?
    private let isReview: Bool
    private let onSaved: () -> Void
    private let onClose: (TripDraft) -> Void
    private let onDiscard: () -> Void
    private let onResume: () -> Void

    init(
        draft: TripDraft,
        isReview: Bool,
        onSaved: @escaping () -> Void = {},
        onClose: @escaping (TripDraft) -> Void = { _ in },
        onDiscard: @escaping () -> Void = {},
        onResume: @escaping () -> Void = {}
    ) {
        self.isReview = isReview
        self.onSaved = onSaved
        self.onClose = onClose
        self.onDiscard = onDiscard
        self.onResume = onResume
        _draft = State(initialValue: draft)
        _baseline = State(initialValue: draft)
        _milesField = State(initialValue: Format.miles(draft.milesThousandths, decimals: 2))
    }

    var body: some View {
        VStack(spacing: 0) {
            mapHeader
            Form {
                heroSection
                purposeSection
                categorySection
                whenSection
                milesSection
                notesSection
                receiptSection
                historySection
                actionSection
            }
        }
        .navigationTitle(isReview ? "Review trip" : Format.date(draft.startedAt))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(isReview ? "Close" : "Cancel", action: close)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!canSave)
            }
        }
        .task { await fillAddresses() }
        .onAppear { fitIfNeeded() }
        .onChange(of: draft) { _, updated in
            if isReview { app.recorder.updateDraft(updated) }
        }
        .sheet(isPresented: $showSplit) {
            SplitSheet(draft: draft) { left, right in
                commitSplit(left: left, right: right)
            }
        }
        .sheet(isPresented: $showMerge) {
            MergeSheet(draft: draft, neighbors: TripEdits.neighbors(of: draft, in: savedDrafts)) { result, ids in
                commitMerge(result, originals: ids)
            }
        }
        .sheet(item: $expenseEdit) { expense in
            ExpenseSheet(draft: expense) { saved in
                if let index = draft.expenses.firstIndex(where: { $0.id == saved.id }) {
                    draft.expenses[index] = saved
                } else {
                    draft.expenses.append(saved)
                }
            }
        }
        .alert("This trip was not saved", isPresented: errorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? LedgerError.saveFailed.localizedDescription)
        }
        .confirmationDialog("Discard this trip?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("Discard trip", role: .destructive, action: onDiscard)
        }
        .confirmationDialog("Keep recording? Edits on this screen are not saved yet.", isPresented: $showResumeConfirm, titleVisibility: .visible) {
            Button("Keep recording", action: onResume)
        }
        .interactiveDismissDisabled(isDirty)
    }

    private var mapHeader: some View {
        VStack(spacing: 8) {
            RouteMap(
                points: draft.includedPoints,
                start: draft.startCoordinate,
                end: draft.endCoordinate,
                showsUser: false,
                placeMode: placeMode,
                onPlace: { coordinate in
                    if placeMode == .start { draft.placeStart(coordinate) }
                    if placeMode == .end { draft.placeEnd(coordinate) }
                },
                position: $position
            )
            .frame(height: 220)
            Picker("Map", selection: $placeMode) {
                ForEach(PlaceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            if placeMode != .view {
                Text(Copy.pinDoesNotChangeMiles)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 8)
        .background(Color(.systemGroupedBackground))
    }

    private var heroSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Format.miles(draft.milesThousandths, decimals: 2)) mi")
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                Spacer()
                if draft.isEdited {
                    Text("Edited")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
            }
            Text(amountLine)
                .font(.headline)
                .foregroundStyle(draft.category == .personal ? .secondary : Color.accentColor)
            Text(priced.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var purposeSection: some View {
        Section("Purpose") {
            TextField("Why was this drive business?", text: $draft.purpose, axis: .vertical)
                .lineLimit(2...4)
            if draft.category == .business, draft.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Add a purpose before you export this business trip.")
                    .font(.footnote)
                    .foregroundStyle(Theme.charity)
            }
            if !recentPurposes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(recentPurposes, id: \.self) { purpose in
                            Button(purpose) { draft.purpose = purpose }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    private var categorySection: some View {
        Section("Category") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(TripCategory.allCases) { category in
                    Button {
                        draft.category = category
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.title)
                                .font(.body.weight(.semibold))
                            Text(category.hint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            draft.category == category ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(draft.category == category ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
            if vehicles.count > 1 {
                Picker("Vehicle", selection: $draft.vehicleId) {
                    ForEach(vehicles) { vehicle in
                        Text(vehicle.displayName).tag(vehicle.id)
                    }
                }
            } else if let vehicle = vehicles.first {
                LabeledContent("Vehicle", value: vehicle.displayName)
            }
        }
    }

    private var whenSection: some View {
        Section("When and where") {
            DatePicker("Start", selection: $draft.startedAt)
            DatePicker("End", selection: $draft.endedAt)
            TextField("Start place", text: $draft.startAddress)
            TextField("End place", text: $draft.endAddress)
            if draft.track.isEmpty {
                Text(Copy.manualMiles)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var milesSection: some View {
        Section("Miles") {
            TextField("Miles", text: $milesField)
                .keyboardType(.decimalPad)
                .onChange(of: milesField) { _, value in
                    guard let thousandths = Format.thousandths(fromMiles: value) else { return }
                    draft.setMiles(thousandths)
                }
            if draft.source == .session, !draft.track.isEmpty {
                if draft.track.count > 1 {
                    VStack(alignment: .leading) {
                        Text("Trim start")
                        Slider(
                            value: trimStartBinding,
                            in: 0...Double(max(draft.track.count - 1, 0)),
                            step: 1
                        )
                        Text("Trim end")
                        Slider(
                            value: trimEndBinding,
                            in: 0...Double(max(draft.track.count - 1, 0)),
                            step: 1
                        )
                    }
                    .accessibilityElement(children: .contain)
                }
                Text(draft.mileageOverridden ? "Manual miles stay in place while you trim the path." : Copy.pathMiles)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let tracked = draft.trackedMilesThousandths {
                    LabeledContent("Tracked path", value: "\(Format.miles(tracked, decimals: 2)) mi")
                }
                Button("Use path mileage") {
                    draft.usePathMileage()
                    milesField = Format.miles(draft.milesThousandths, decimals: 2)
                }
                .disabled(draft.track.isEmpty)
            }
            if draft.gapCount > 0 {
                Text(Copy.gapWarning)
                    .font(.footnote)
                    .foregroundStyle(Theme.charity)
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Optional", text: $draft.notes, axis: .vertical)
                .lineLimit(2...5)
        }
    }

    private var receiptSection: some View {
        Section("Receipts") {
            Text(Copy.standardMileageReminder)
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(draft.expenses) { expense in
                Button {
                    expenseEdit = expense
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(expense.type.title)
                            if !expense.notes.isEmpty {
                                Text(expense.notes).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(Format.currency(cents: expense.amountCents))
                            .monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                draft.expenses.remove(atOffsets: offsets)
            }
            Button("Add parking, toll, or other") {
                expenseEdit = ExpenseDraft(id: UUID(), date: draft.endedAt, type: .parking, amountCents: 0, notes: "", photoData: nil)
            }
        }
    }

    private var historySection: some View {
        Section("History") {
            if draft.revisions.isEmpty {
                Text("No changes yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(draft.revisions.sorted { $0.at > $1.at }) { revision in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(revision.summary)
                        Text(Format.date(revision.at) + " " + Format.time(revision.at))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text(Copy.editedMeaning)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var actionSection: some View {
        Section {
            Button("Split trip") { showSplit = true }
                .disabled(draft.milesThousandths == 0 && draft.track.count < 2)
            if savedDrafts.contains(where: { $0.id == draft.id }) {
                Button("Merge with adjacent") { showMerge = true }
            }
            if isReview {
                Button("Keep recording") { showResumeConfirm = true }
                Button("Discard trip", role: .destructive) { showDiscardConfirm = true }
            } else if trips.contains(where: { $0.id == draft.id }) {
                Button("Delete trip", role: .destructive, action: deleteTrip)
            }
        }
    }

    private var priced: PricedTrip {
        LedgerMath.price(draft, records: records)
    }

    private var records: [RateRecord] {
        rateRows.compactMap(TripLibrary.record(from:))
    }

    private var savedDrafts: [TripDraft] {
        trips.filter { $0.deletedAt == nil }.map(TripLibrary.draft(from:))
    }

    private var recentPurposes: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for trip in trips where trip.deletedAt == nil && trip.id != draft.id {
            let purpose = trip.purpose.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !purpose.isEmpty, seen.insert(purpose).inserted else { continue }
            result.append(purpose)
            if result.count == 6 { break }
        }
        return result
    }

    private var amountLine: String {
        if draft.category == .personal { return "Not deducted" }
        if let cents = priced.amountCents { return "\(Format.currency(cents: cents)) estimated" }
        return "Estimate unavailable"
    }

    private var canSave: Bool {
        guard draft.endedAt >= draft.startedAt else { return false }
        let hasContent = draft.milesThousandths > 0
            || draft.track.count >= 2
            || !draft.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let needsWrite = isDirty || isReview || !trips.contains(where: { $0.id == draft.id })
        return hasContent && needsWrite
    }

    private var isDirty: Bool {
        draft != baseline
    }

    private var trimStartBinding: Binding<Double> {
        Binding(
            get: { Double(draft.trimStart) },
            set: { newValue in
                draft.setTrim(start: Int(newValue), end: draft.trimEnd)
                if !draft.mileageOverridden {
                    milesField = Format.miles(draft.milesThousandths, decimals: 2)
                }
                fitIfNeeded(force: true)
            }
        )
    }

    private var trimEndBinding: Binding<Double> {
        Binding(
            get: { Double(draft.trimEnd) },
            set: { newValue in
                draft.setTrim(start: draft.trimStart, end: Int(newValue))
                if !draft.mileageOverridden {
                    milesField = Format.miles(draft.milesThousandths, decimals: 2)
                }
                fitIfNeeded(force: true)
            }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func fitIfNeeded(force: Bool = false) {
        guard force || !didFit else { return }
        position = MapFrame.fit(draft.includedPoints.isEmpty ? draft.track : draft.includedPoints)
        didFit = true
    }

    private func fillAddresses() async {
        if draft.startAddress.isEmpty, let start = draft.startCoordinate, let text = await PlaceLookup.address(for: start), draft.startAddress.isEmpty {
            draft.startAddress = text
        }
        if draft.endAddress.isEmpty, let end = draft.endCoordinate, let text = await PlaceLookup.address(for: end), draft.endAddress.isEmpty {
            draft.endAddress = text
        }
    }

    private func save() {
        do {
            try TripLibrary.save(
                baseline: baseline,
                edited: draft,
                context: context,
                isPlus: app.purchases.isPlus
            )
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func close() {
        if isReview {
            onClose(draft)
            dismiss()
            return
        }
        dismiss()
    }

    private func deleteTrip() {
        guard let trip = trips.first(where: { $0.id == draft.id }) else { return }
        do {
            try TripLibrary.softDelete(trip, context: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commitSplit(left: TripDraft, right: TripDraft) {
        do {
            try TripLibrary.split(originalID: draft.id, left: left, right: right, context: context)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commitMerge(_ result: TripDraft, originals: [UUID]) {
        do {
            try TripLibrary.merge(result: result, originalIDs: originals, context: context)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
