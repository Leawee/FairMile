import SwiftUI

@main
struct FairMileApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .modelContainer(appModel.container)
        }
    }
}
