import Foundation
import WatchConnectivity

/// Transfer-Queue Watch → iPhone via WCSession.transferFile.
/// transferFile läuft vom System gepuffert im Hintergrund weiter, auch wenn
/// das iPhone gerade nicht erreichbar ist. Zusätzlich: Beim App-Start und
/// nach jedem Fehlschlag wird die Outbox erneut eingereiht, damit kein File
/// verloren geht.
final class WatchSync: NSObject, ObservableObject {
    static let shared = WatchSync()

    @Published var pendingCount = 0

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func enqueue(_ url: URL) {
        WCSession.default.transferFile(url, metadata: nil)
        updatePendingCount()
    }

    /// Reiht alle Outbox-Files ein, für die kein Transfer mehr aussteht.
    func retryOutbox() {
        let inFlight = Set(WCSession.default.outstandingFileTransfers.map { $0.file.fileURL.lastPathComponent })
        for file in Outbox.pendingFiles where !inFlight.contains(file.lastPathComponent) {
            WCSession.default.transferFile(file, metadata: nil)
        }
        updatePendingCount()
    }

    private func updatePendingCount() {
        let count = Outbox.pendingFiles.count
        DispatchQueue.main.async { self.pendingCount = count }
    }
}

extension WatchSync: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            retryOutbox()
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let url = fileTransfer.file.fileURL
        if error == nil {
            Outbox.markSent(url)
        }
        // Bei Fehler bleibt das File in der Outbox; retryOutbox reiht es beim
        // nächsten Anlass wieder ein.
        updatePendingCount()
    }
}
