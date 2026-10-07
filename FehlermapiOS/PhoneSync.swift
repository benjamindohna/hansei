import Foundation
import WatchConnectivity

/// Empfängt Files von der Watch. Wichtig: iOS startet die App bei eingehenden
/// Transfers im Hintergrund — WCSession muss deshalb sofort beim App-Launch
/// aktiviert werden, und das File muss synchron aus dem temporären Pfad
/// wegkopiert werden, bevor der Delegate-Callback zurückkehrt.
final class PhoneSync: NSObject, ObservableObject {
    static let shared = PhoneSync()
    static let didReceiveRecording = Notification.Name("PhoneSync.didReceiveRecording")

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
}

extension PhoneSync: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let name = file.fileURL.lastPathComponent

        // Session-Metadaten (Dauer, Distanz …) von der Watch.
        if name.hasPrefix("meta_"), name.hasSuffix(".json"),
           let epoch = TimeInterval(name.dropFirst(5).dropLast(5)) {
            let dir = RecordingStore.directory(forSessionStart: Date(timeIntervalSince1970: epoch))
            let dest = dir.appendingPathComponent("meta.json")
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.moveItem(at: file.fileURL, to: dest)) != nil {
                Task { await Uploader.uploadMeta(dest, sessionEpoch: Int(epoch)) }
            }
            return
        }

        guard let parsed = RecordingFile.parse(fileName: name) else { return }

        let dir = RecordingStore.directory(forSessionStart: parsed.sessionStart)
        let dest = dir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: file.fileURL, to: dest)
            NotificationCenter.default.post(name: Self.didReceiveRecording, object: nil)
            Task { await Uploader.upload(dest) }
        } catch {
            // Move failed — the temp file is gone after return, but die Watch
            // behält 7 Tage eine Sent-Kopie, aus der man notfalls retten kann.
        }
    }
}
