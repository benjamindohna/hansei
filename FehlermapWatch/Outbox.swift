import Foundation

/// File-Ablage auf der Watch. Aufnahmen leben in "Outbox", bis der Transfer
/// ans iPhone bestätigt ist, danach wandern sie nach "Sent" (Sicherheitskopie,
/// wird nach 7 Tagen aufgeräumt). Nichts wird gelöscht, bevor es drüben ist.
enum Outbox {
    static var directory: URL {
        ensure(named: "Outbox")
    }

    static var sentDirectory: URL {
        ensure(named: "Sent")
    }

    static var pendingFiles: [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter {
            $0.lastPathComponent.hasPrefix("rec_") || $0.lastPathComponent.hasPrefix("meta_")
        }
    }

    static func markSent(_ url: URL) {
        let dest = sentDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.moveItem(at: url, to: dest)
    }

    static func cleanup() {
        // Inflight-Files von abgestürzten Aufnahmen: retten statt löschen.
        // Zeitstempel aus dem Erstellungsdatum; leere Prepared-Files (nur
        // Header, nie aufgenommen) fliegen raus.
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey])) ?? []
        for file in files where file.lastPathComponent.hasPrefix("inflight_") {
            let attrs = try? file.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            if let created = attrs?.creationDate, (attrs?.fileSize ?? 0) > 1_000 {
                let name = RecordingFile.fileName(sessionStart: created, recordingStart: created)
                try? FileManager.default.moveItem(at: file, to: directory.appendingPathComponent(name))
            } else {
                try? FileManager.default.removeItem(at: file)
            }
        }
        // Sent copies older than 7 days.
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        let sent = (try? FileManager.default.contentsOfDirectory(
            at: sentDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in sent {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private static func ensure(named name: String) -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
