import SwiftUI
import AVFoundation

struct SessionListView: View {
    @EnvironmentObject private var store: RecordingStore
    @State private var showProfileSheet = false
    @State private var profileName = Profile.id

    var body: some View {
        NavigationStack {
            Group {
                if store.sessions.isEmpty {
                    ContentUnavailableView(
                        "Noch keine Aufnahmen",
                        systemImage: "applewatch",
                        description: Text("Starte eine Session auf der Watch. Aufnahmen erscheinen hier automatisch nach dem Sync.")
                    )
                } else {
                    List(store.sessions) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.id, format: .dateTime.weekday(.wide).day().month().year())
                                    .font(.headline)
                                Text("\(session.id, format: .dateTime.hour().minute()) Uhr · \(session.recordings.count) Aufnahmen")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { store.refresh() }
            .onAppear { store.refresh() }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("HANSEI")
                        .font(.system(size: 17, weight: .thin))
                        .tracking(1.8)
                        .foregroundStyle(Color(.systemGray))
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        profileName = Profile.id
                        showProfileSheet = true
                    } label: {
                        Image(systemName: "person.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: URL(string: "https://gethansei.vercel.app/?p=\(Profile.id)")!) {
                        Image(systemName: "safari")
                    }
                }
            }
            .sheet(isPresented: $showProfileSheet) {
                NavigationStack {
                    Form {
                        Section {
                            TextField("Name", text: $profileName)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } footer: {
                            Text("Trennt deine Aufnahmen online von anderen Profilen. Nur Kleinbuchstaben und Zahlen.")
                        }
                    }
                    .navigationTitle("Profil")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Sichern") {
                                Profile.id = profileName
                                profileName = Profile.id
                                showProfileSheet = false
                            }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }
}

struct SessionDetailView: View {
    let session: GameSession
    @StateObject private var player = AudioPlayerModel()

    var body: some View {
        List(session.recordings) { recording in
            Button {
                player.toggle(url: recording.id)
            } label: {
                HStack {
                    Image(systemName: player.playingURL == recording.id ? "pause.circle.fill" : "play.circle")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recording.recordedAt, format: .dateTime.hour().minute().second())
                            .font(.body.monospacedDigit())
                        Text(durationString(recording.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle(session.id.formatted(.dateTime.day().month().hour().minute()))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func durationString(_ duration: TimeInterval) -> String {
        let s = Int(duration.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

@MainActor
final class AudioPlayerModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playingURL: URL?
    private var player: AVAudioPlayer?

    func toggle(url: URL) {
        if playingURL == url {
            player?.stop()
            playingURL = nil
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.play()
            player = p
            playingURL = url
        } catch {
            playingURL = nil
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playingURL = nil }
    }
}
