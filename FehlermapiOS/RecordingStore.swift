import Foundation
import AVFoundation

struct GameSession: Identifiable {
    let id: Date // session start
    let recordings: [Recording]
}

struct Recording: Identifiable {
    let id: URL // file URL
    let recordedAt: Date
    let duration: TimeInterval
}

/// Liest die Fehlermap-Ablage: Documents/Recordings/<sessionEpoch>/rec_*.m4a.
/// Kein Datenbank-Layer — die Files selbst sind die Wahrheit.
@MainActor
final class RecordingStore: ObservableObject {
    @Published var sessions: [GameSession] = []

    private var observer: NSObjectProtocol?

    init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: PhoneSync.didReceiveRecording, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    nonisolated static var baseDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static func directory(forSessionStart start: Date) -> URL {
        let dir = baseDirectory.appendingPathComponent("\(Int(start.timeIntervalSince1970))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func refresh() {
        let fm = FileManager.default
        let sessionDirs = (try? fm.contentsOfDirectory(at: Self.baseDirectory, includingPropertiesForKeys: nil)) ?? []

        sessions = sessionDirs.compactMap { dir -> GameSession? in
            guard let epoch = TimeInterval(dir.lastPathComponent) else { return nil }
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            let recordings = files.compactMap { url -> Recording? in
                guard let parsed = RecordingFile.parse(fileName: url.lastPathComponent) else { return nil }
                let duration = (try? AVAudioPlayer(contentsOf: url).duration) ?? 0
                return Recording(id: url, recordedAt: parsed.recordingStart, duration: duration)
            }
            .sorted { $0.recordedAt < $1.recordedAt }
            guard !recordings.isEmpty else { return nil }
            return GameSession(id: Date(timeIntervalSince1970: epoch), recordings: recordings)
        }
        .sorted { $0.id > $1.id }
    }
}
