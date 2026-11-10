import SwiftUI

struct SplitSheet: View {
    @Environment(\.dismiss) private var dismiss
    let draft: TripDraft
    var onSplit: (TripDraft, TripDraft) -> Void
    @State private var fraction = 0.5
    @State private var rightPurpose = ""
    @State private var rightCategory: TripCategory
    @State private var rightExpenses: Set<UUID> = []

    init(draft: TripDraft, onSplit: @escaping (TripDraft, TripDraft) -> Void) {
        self.draft = draft
        self.onSplit = onSplit
        _rightCategory = State(initialValue: draft.category)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Where to split") {
                    Slider(value: $fraction, in: 0.05...0.95, step: 0.01)
                    LabeledContent("First trip", value: "\(Format.miles(miles.0, decimals: 2)) mi")
                    LabeledContent("Second trip", value: "\(Format.miles(miles.1, decimals: 2)) mi")
                    Text("Miles are split by this share of the current total. They are not replaced with a straight line.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Second trip") {
                    TextField("Purpose", text: $rightPurpose, axis: .vertical)
                    Picker("Category", selection: $rightCategory) {
                        ForEach(TripCategory.allCases) { category in
                            Text(category.title).tag(category)
                        }
                    }
                }
                if !draft.expenses.isEmpty {
                    Section("Receipts") {
                        Text("Receipts you mark go to the second trip. The rest stay on the first.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        ForEach(draft.expenses) { expense in
                            Toggle(isOn: Binding(
                                get: { rightExpenses.contains(expense.id) },
                                set: { isOn in
                                    if isOn { rightExpenses.insert(expense.id) } else { rightExpenses.remove(expense.id) }
                                }
                            )) {
                                Text("\(expense.type.title) · \(Format.currency(cents: expense.amountCents))")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Split trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Split") {
                        let parts = TripEdits.split(
                            draft,
                            fraction: fraction,
                            rightPurpose: rightPurpose,
                            rightCategory: rightCategory,
                            expenseIDsOnRight: rightExpenses,
                            now: .now
                        )
                        onSplit(parts.0, parts.1)
                        dismiss()
                    }
                }
            }
        }
    }

    private var miles: (Int, Int) {
        TripEdits.divide(total: draft.milesThousandths, fraction: fraction)
    }
}

struct MergeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let draft: TripDraft
    let neighbors: (previous: TripDraft?, next: TripDraft?)
    var onMerge: (TripDraft, [UUID]) -> Void
    @State private var choice: UUID?
    @State private var purpose: String
    @State private var category: TripCategory

    init(draft: TripDraft, neighbors: (previous: TripDraft?, next: TripDraft?), onMerge: @escaping (TripDraft, [UUID]) -> Void) {
        self.draft = draft
        self.neighbors = neighbors
        self.onMerge = onMerge
        _purpose = State(initialValue: draft.purpose)
        _category = State(initialValue: draft.category)
        _choice = State(initialValue: neighbors.previous?.id ?? neighbors.next?.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                if options.isEmpty {
                    Section {
                        Text("Merge is available when this vehicle has a trip immediately before or after this one.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Adjacent trip") {
                        Picker("Trip", selection: $choice) {
                            ForEach(options) { option in
                                Text(label(option)).tag(Optional(option.id))
                            }
                        }
                        if let other = selected {
                            Text(gapText(other))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Section("Merged trip") {
                        TextField("Purpose", text: $purpose, axis: .vertical)
                        Picker("Category", selection: $category) {
                            ForEach(TripCategory.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        if let other = selected {
                            LabeledContent("Miles", value: "\(Format.miles(draft.milesThousandths + other.milesThousandths, decimals: 2)) mi")
                        }
                        Text("Miles are added together. The map does not invent the road between the trips.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Merge trips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Merge") {
                        guard let other = selected else { return }
                        let result = TripEdits.merge(draft, other, purpose: purpose, category: category, now: .now)
                        onMerge(result, [draft.id, other.id])
                        dismiss()
                    }
                    .disabled(selected == nil)
                }
            }
        }
    }

    private var options: [TripDraft] {
        [neighbors.previous, neighbors.next].compactMap { $0 }
    }

    private var selected: TripDraft? {
        options.first { $0.id == choice }
    }

    private func label(_ trip: TripDraft) -> String {
        let purpose = trip.purpose.isEmpty ? trip.category.title : trip.purpose
        return "\(Format.date(trip.startedAt)) · \(purpose)"
    }

    private func gapText(_ other: TripDraft) -> String {
        let earlier = draft.startedAt <= other.startedAt ? draft : other
        let later = earlier.id == draft.id ? other : draft
        let gap = later.startedAt.timeIntervalSince(earlier.endedAt)
        if gap < 0 { return "These trips overlap in time." }
        let minutes = Int(gap / 60)
        return "\(minutes) minutes between these trips. The merged trip uses the rate for its start date."
    }
}
