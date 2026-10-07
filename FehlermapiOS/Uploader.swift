import Foundation

/// Lädt gesyncte Aufnahmen zur Web-App hoch (Vercel Blob + Transkription).
/// Erfolg wird per Marker-File (<name>.m4a.uploaded) festgehalten — kein
/// erneuter Upload, aber Retries bleiben idempotent, weil der Server unter
/// deterministischem Pfad überschreibt. uploadPending() läuft bei jedem
/// App-Start/Foreground und nach jedem Empfang von der Watch.
enum Uploader {
    static let endpoint = URL(string: "https://gethansei.vercel.app/api/upload")!
    static let token = Secrets.uploadToken

    static func uploadPending() async {
        let fm = FileManager.default
        let sessionDirs = (try? fm.contentsOfDirectory(
            at: RecordingStore.baseDirectory, includingPropertiesForKeys: nil)) ?? []
        for dir in sessionDirs {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == RecordingFile.fileExtension {
                let marker = file.appendingPathExtension("uploaded")
                guard !fm.fileExists(atPath: marker.path) else { continue }
                await upload(file)
            }
            let meta = dir.appendingPathComponent("meta.json")
            if fm.fileExists(atPath: meta.path),
               !fm.fileExists(atPath: meta.path + ".uploaded"),
               let epoch = Int(dir.lastPathComponent) {
                await uploadMeta(meta, sessionEpoch: epoch)
            }
        }
    }

    static func uploadMeta(_ fileURL: URL, sessionEpoch: Int) async {
        guard sessionEpoch > 0, let data = try? Data(contentsOf: fileURL) else { return }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "kind", value: "meta"),
            URLQueryItem(name: "session", value: String(sessionEpoch)),
            URLQueryItem(name: "profile", value: Profile.id),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (_, response) = try await URLSession.shared.upload(for: request, from: data)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                FileManager.default.createFile(atPath: fileURL.path + ".uploaded", contents: nil)
            }
        } catch {}
    }

    static func upload(_ fileURL: URL) async {
        guard let parsed = RecordingFile.parse(fileName: fileURL.lastPathComponent),
              let data = try? Data(contentsOf: fileURL) else { return }

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "session", value: String(Int(parsed.sessionStart.timeIntervalSince1970))),
            URLQueryItem(name: "rec", value: String(Int(parsed.recordingStart.timeIntervalSince1970))),
            URLQueryItem(name: "profile", value: Profile.id),
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")

        do {
            let (_, response) = try await URLSession.shared.upload(for: request, from: data)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                let marker = fileURL.appendingPathExtension("uploaded")
                FileManager.default.createFile(atPath: marker.path, contents: nil)
            }
            // Non-2xx oder Netzfehler: kein Marker, nächster uploadPending()-Lauf
            // versucht es erneut.
        } catch {}
    }
}
