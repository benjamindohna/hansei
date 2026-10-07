import SwiftUI

@main
struct FehlermapApp: App {
    @StateObject private var store = RecordingStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        PhoneSync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            SessionListView()
                .environmentObject(store)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.refresh()
                Task { await Uploader.uploadPending() }
            }
        }
    }
}
