import AVFoundation
import WatchKit

/// Reliability-first recorder:
/// - Die Audio-Session wird einmal beim Session-Start aktiviert und bleibt
///   für die gesamte Spieldauer aktiv, der nächste AVAudioRecorder wird
///   vorbereitet (prepareToRecord) — dadurch startet die Aufnahme beim Tap
///   ohne Aktivierungs-Latenz.
/// - Kein Auto-Stop bei Stille (zu fehleranfällig bei Platzlärm), stattdessen
///   Tap-to-Stop plus Segment-Logik gegen vergessene Aufnahmen: Nach 60 s
///   endet die Aufnahme automatisch; in den letzten 10 s eines Segments warnt
///   die Watch (Puls alle 2 s + "Weiter aufnehmen"-Button, der um 60 s
///   verlängert). Hartes Maximum pro Aufnahme: 5 Minuten.
/// - Haptik bestätigt Start und Stop, Fehler werden sichtbar gemacht.
@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    static let segment: TimeInterval = 60
    static let warningWindow: TimeInterval = 10
    static let maxDuration: TimeInterval = 300

    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0
    @Published var secondsUntilAutoStop: Int?
    @Published var lastError: String?

    private var deadline: TimeInterval = AudioRecorder.segment

    var canExtend: Bool { deadline < Self.maxDuration }

    private var recorder: AVAudioRecorder?
    private var preparedRecorder: AVAudioRecorder?
    private var preparedURL: URL?
    private var timer: Timer?
    private var recordingStart: Date?
    private var sessionStart: Date?
    private var lastPulse = 0
    private var lastWarnPulse = 0

    /// Called with the finished file URL after every successful recording.
    var onFinished: ((URL) -> Void)?

    private static let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 32_000,
    ]

    // MARK: Session lifecycle

    func beginSession(startedAt: Date) async -> Bool {
        sessionStart = startedAt
        let granted = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
        guard granted else {
            lastError = "Mikrofon-Zugriff verweigert. Bitte in den Einstellungen erlauben."
            return false
        }
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .default)
            try audioSession.setActive(true)
            prepareNextRecorder()
            return true
        } catch {
            lastError = "Audio-Setup fehlgeschlagen: \(error.localizedDescription)"
            return false
        }
    }

    func endSession() {
        if isRecording { stop() }
        preparedRecorder = nil
        preparedURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sessionStart = nil
    }

    // MARK: Recording

    func start() {
        guard !isRecording, sessionStart != nil else { return }
        lastError = nil

        if preparedRecorder == nil { prepareNextRecorder() }
        guard let prepared = preparedRecorder, let url = preparedURL else {
            fail("Recorder konnte nicht vorbereitet werden.")
            return
        }

        let now = Date()
        guard prepared.record() else {
            fail("Aufnahme konnte nicht gestartet werden.")
            preparedRecorder = nil
            preparedURL = nil
            return
        }

        // Rename target happens at stop; recorder writes to the prepared URL.
        recorder = prepared
        preparedRecorder = nil
        recordingStart = now
        isRecording = true
        elapsed = 0
        lastPulse = 0
        lastWarnPulse = 0
        deadline = Self.segment
        secondsUntilAutoStop = nil
        WKInterfaceDevice.current().play(.start)

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.recordingStart else { return }
                self.elapsed = Date().timeIntervalSince(start)

                let remaining = self.deadline - self.elapsed
                if remaining <= 0 {
                    // Segment abgelaufen, keine Verlängerung getippt → Auto-Stop.
                    self.stop()
                    return
                }
                if remaining <= Self.warningWindow {
                    // Warnfenster: dringlicher Puls alle 2 s + Countdown fürs UI.
                    self.secondsUntilAutoStop = max(1, Int(remaining.rounded()))
                    let warnPulse = Int(self.elapsed / 2)
                    if warnPulse > self.lastWarnPulse {
                        self.lastWarnPulse = warnPulse
                        WKInterfaceDevice.current().play(.directionUp)
                    }
                } else {
                    // Leiser Puls alle 10 s: bestätigt auch bei dunklem Display,
                    // dass die Aufnahme noch läuft.
                    self.secondsUntilAutoStop = nil
                    let pulse = Int(self.elapsed / 10)
                    if pulse > self.lastPulse {
                        self.lastPulse = pulse
                        WKInterfaceDevice.current().play(.click)
                    }
                }
                // Safety net: falls der Recorder von außen gestoppt wurde
                // (Audio-Interruption o.ä.), Aufnahme sichern statt hängen.
                if let rec = self.recorder, !rec.isRecording {
                    self.finalize(recordedURL: url)
                }
            }
        }
        _ = url // captured for the timer closure above
    }

    func stop() {
        guard isRecording, let rec = recorder else { return }
        let url = rec.url
        rec.stop()
        finalize(recordedURL: url)
    }

    /// Verlängert das aktuelle Segment um 60 s (bis zum harten Maximum).
    func extend() {
        guard isRecording, canExtend else { return }
        deadline = min(deadline + Self.segment, Self.maxDuration)
        secondsUntilAutoStop = nil
        WKInterfaceDevice.current().play(.click)
    }

    private func finalize(recordedURL: URL) {
        timer?.invalidate()
        timer = nil
        recorder = nil
        isRecording = false
        secondsUntilAutoStop = nil

        guard let sessionStart, let recordingStart else { return }
        self.recordingStart = nil

        // Move to its final, metadata-carrying name in the outbox.
        let finalName = RecordingFile.fileName(sessionStart: sessionStart, recordingStart: recordingStart)
        let finalURL = Outbox.directory.appendingPathComponent(finalName)
        do {
            try FileManager.default.moveItem(at: recordedURL, to: finalURL)
        } catch {
            fail("Aufnahme konnte nicht gespeichert werden: \(error.localizedDescription)")
            return
        }

        // Verify we actually captured audio data.
        let size = ((try? FileManager.default.attributesOfItem(atPath: finalURL.path))?[.size] as? Int) ?? 0
        guard size > 1_000 else {
            fail("Aufnahme ist leer — bitte erneut versuchen.")
            return
        }

        WKInterfaceDevice.current().play(.stop)
        onFinished?(finalURL)
        prepareNextRecorder()
    }

    private func prepareNextRecorder() {
        let url = Outbox.directory.appendingPathComponent("inflight_\(UUID().uuidString).m4a")
        do {
            let rec = try AVAudioRecorder(url: url, settings: Self.settings)
            guard rec.prepareToRecord() else {
                fail("Recorder-Vorbereitung fehlgeschlagen.")
                return
            }
            preparedRecorder = rec
            preparedURL = url
        } catch {
            fail("Recorder-Fehler: \(error.localizedDescription)")
        }
    }

    private func fail(_ message: String) {
        lastError = message
        isRecording = false
        timer?.invalidate()
        timer = nil
        recorder = nil
        WKInterfaceDevice.current().play(.failure)
    }
}
