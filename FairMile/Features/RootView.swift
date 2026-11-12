import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = app
        Group {
            if app.hasOnboarded {
                TabView(selection: $app.tab) {
                    HomeView()
                        .tabItem { Label("Log", systemImage: "book.closed") }
                        .tag(AppTab.log)
                    TripListView()
                        .tabItem { Label("Trips", systemImage: "list.bullet") }
                        .tag(AppTab.trips)
                    ExportView()
                        .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
                        .tag(AppTab.export)
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(AppTab.settings)
                }
            } else {
                OnboardingView()
            }
        }
        .tint(Color.accentColor)
        .sheet(isPresented: $app.showPaywall) {
            PaywallView()
        }
        .fullScreenCover(isPresented: $app.showRecorder) {
            RecordView()
        }
        .task {
            guard !app.isPreview else { return }
            do {
                try Seed.bootstrap(context: context)
            } catch {
                assertionFailure("Rate table failed to load: \(error.localizedDescription)")
            }
            #if DEBUG
            ScreenshotSample.prepare(app: app, context: context)
            #endif
            await app.purchases.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                app.recorder.sceneBecameActive()
            }
        }
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @State private var page = 0

    private let pages: [(symbol: String, title: String, body: String)] = [
        ("book.closed", "A mileage log you can check", "Record the drive, fix anything that looks wrong, and keep a record you can hand to your accountant."),
        ("location", "Start when you leave", "FairMile measures the path while the app is open. It does not track in the background. You can also add a past trip by hand."),
        ("calendar", "Rates that follow the date", "Each trip uses the IRS standard mileage rate for the day it started. Export the year as a PDF or CSV when you need it.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            Image(systemName: pages[page].symbol)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Color.accentColor)
            Text(pages[page].title)
                .font(.largeTitle.weight(.semibold))
            Text(pages[page].body)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if page == pages.count - 1 {
                DisclaimerText()
            }
            Spacer()
            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { index in
                    Circle()
                        .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .accessibilityLabel("Page \(page + 1) of \(pages.count)")
            Button(page == pages.count - 1 ? "Start using FairMile" : "Continue") {
                if page == pages.count - 1 {
                    app.finishOnboarding()
                } else {
                    page += 1
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .center)
            if page < pages.count - 1 {
                Button("Skip") { app.finishOnboarding() }
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(.systemGroupedBackground))
    }
}
