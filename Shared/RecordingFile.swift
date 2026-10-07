import Foundation

/// Naming convention for recording files, shared between Watch und iPhone.
/// Pattern: rec_<sessionStartEpoch>_<recordingStartEpoch>.m4a
/// All metadata lives in the filename, so a retry after a failed transfer
/// never depends on sidecar state.
enum RecordingFile {
    static let fileExtension = "m4a"

    static func fileName(sessionStart: Date, recordingStart: Date) -> String {
        "rec_\(Int(sessionStart.timeIntervalSince1970))_\(Int(recordingStart.timeIntervalSince1970)).\(fileExtension)"
    }

    static func parse(fileName: String) -> (sessionStart: Date, recordingStart: Date)? {
        let base = (fileName as NSString).deletingPathExtension
        let parts = base.split(separator: "_")
        guard parts.count == 3, parts[0] == "rec",
              let sessionEpoch = TimeInterval(parts[1]),
              let recEpoch = TimeInterval(parts[2]) else { return nil }
        return (Date(timeIntervalSince1970: sessionEpoch), Date(timeIntervalSince1970: recEpoch))
    }
}
