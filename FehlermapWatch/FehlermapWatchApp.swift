import SwiftUI

@main
struct FehlermapWatchApp: App {
    @StateObject private var workout = WorkoutManager()
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var sync = WatchSync.shared

    init() {
        Outbox.cleanup()
        WatchSync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(workout)
                .environmentObject(recorder)
                .environmentObject(sync)
        }
    }
}
