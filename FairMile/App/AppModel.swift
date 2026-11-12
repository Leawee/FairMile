import Foundation
import Observation
import SwiftData

enum AppTab: Hashable {
    case log
    case trips
    case export
    case settings
}

@MainActor
@Observable
final class AppModel {
    let container: ModelContainer
    let recorder: TripRecorder
    let purchases: PurchaseManager
    let defaults: UserDefaults
    let isPreview: Bool
    var hasOnboarded: Bool
    var iCloudEnabled: Bool
    var showPaywall = false
    var showRecorder = false
    var tab: AppTab = .log
    #if DEBUG
    var screenshotTripID: UUID?
    #endif

    init(inMemory: Bool = false) {
        isPreview = inMemory
        if inMemory {
            defaults = UserDefaults(suiteName: "fairmile.preview.\(UUID().uuidString)") ?? .standard
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("fairmile-\(UUID().uuidString)", isDirectory: true)
            recorder = TripRecorder(directory: directory)
            container = FairMileStore.make(inMemory: true, iCloud: false)
        } else {
            defaults = .standard
            recorder = TripRecorder(directory: FairMileStore.supportDirectory())
            container = FairMileStore.make(inMemory: false, iCloud: defaults.bool(forKey: Prefs.iCloud))
        }
        hasOnboarded = defaults.bool(forKey: Prefs.onboarded)
        iCloudEnabled = defaults.bool(forKey: Prefs.iCloud)
        purchases = PurchaseManager()
    }

    func finishOnboarding() {
        hasOnboarded = true
        defaults.set(true, forKey: Prefs.onboarded)
    }

    func setICloud(_ enabled: Bool) {
        iCloudEnabled = enabled
        defaults.set(enabled, forKey: Prefs.iCloud)
    }
}
