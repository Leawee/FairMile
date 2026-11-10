import MapKit
import SwiftUI
import UIKit

struct RecordView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if app.recorder.phase == .review, let draft = app.recorder.draft {
                TripEditorView(
                    draft: draft,
                    isReview: true,
                    onSaved: {
                        app.recorder.clear()
                        dismiss()
                    },
                    onClose: { updated in
                        app.recorder.updateDraft(updated)
                        dismiss()
                    },
                    onDiscard: {
                        app.recorder.clear()
                        dismiss()
                    },
                    onResume: {
                        app.recorder.continueRecording()
                    }
                )
                .id(draft.id)
            } else {
                RecordingScreen()
            }
        }
    }
}

private struct RecordingScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        ZStack(alignment: .bottom) {
            RouteMap(
                points: app.recorder.acceptance.points,
                start: app.recorder.acceptance.points.first?.coordinate,
                end: nil,
                showsUser: true,
                placeMode: .view,
                onPlace: { _ in },
                position: $position
            )
            .ignoresSafeArea()
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if let started = app.recorder.startedAt {
                        TimelineView(.periodic(from: started, by: 1)) { context in
                            Text(Format.clock(from: started, to: context.date))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(Format.miles(app.recorder.acceptance.milesThousandths, decimals: 1))
                        .font(.system(size: 48, weight: .semibold))
                        .monospacedDigit()
                    Text(app.recorder.acceptance.points.count < 2 ? "Waiting for a GPS fix" : "miles along the driven path")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if app.recorder.acceptance.gapCount > 0 {
                        Text(Copy.gapWarning)
                            .font(.footnote)
                            .foregroundStyle(Theme.charity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                Text(Copy.keepOpen)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("End trip") {
                    app.recorder.end()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.recording)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Recenter", systemImage: "location") {
                    position = .automatic
                    position = .userLocation(fallback: .automatic)
                }
                .accessibilityLabel("Recenter map")
            }
        }
    }
}
