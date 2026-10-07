import SwiftUI
import WatchKit

extension Color {
    /// Markenfarbe: Zinnoberrot (traditionelles Shu-Iro).
    static let vermillion = Color(red: 0.84, green: 0.28, blue: 0.20)
    /// Warmes Papierweiß für Flächen auf Schwarz.
    static let paper = Color(red: 0.96, green: 0.94, blue: 0.91)
}

enum SessionPhase: Equatable {
    case idle
    case countdown(Int)
    case active
    case ending
    case summary(recordings: Int, duration: TimeInterval, calories: Double?, avgHeartRate: Double?, distanceMeters: Double?, saveError: String?)
}

struct ContentView: View {
    @EnvironmentObject private var workout: WorkoutManager
    @EnvironmentObject private var recorder: AudioRecorder
    @EnvironmentObject private var sync: WatchSync

    @State private var phase: SessionPhase = .idle
    @State private var recordingCount = 0
    @State private var isStarting = false

    var body: some View {
        switch phase {
        case .idle:
            startPage
        case .countdown(let n):
            countdownPage(n)
        case .active:
            TabView {
                recordPage
                endPage
            }
            .tabViewStyle(.verticalPage)
        case .ending:
            endingPage
        case .summary(let recordings, let duration, let calories, let avgHR, let distance, let saveError):
            summaryPage(recordings: recordings, duration: duration, calories: calories, avgHeartRate: avgHR, distanceMeters: distance, saveError: saveError)
        }
    }

    // MARK: Start

    private var startPage: some View {
        VStack(spacing: 14) {
            VStack(spacing: 3) {
                Text("HANSEI")
                    .font(.system(size: 20, weight: .thin))
                    .tracking(1.8)
                    .foregroundStyle(Color(red: 0.72, green: 0.73, blue: 0.75))
                Text("Reflexion im Spiel")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button {
                startSession()
            } label: {
                Label(isStarting ? String(localized: "Startet…") : String(localized: "Session starten"), systemImage: "play.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(.vermillion)
            .disabled(isStarting)

            if let error = workout.lastError ?? recorder.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 4)
    }

    private func startSession() {
        isStarting = true
        Task {
            let workoutOK = await workout.start()
            guard workoutOK, let start = workout.sessionStart else {
                isStarting = false
                return
            }
            let audioOK = await recorder.beginSession(startedAt: start)
            guard audioOK else {
                _ = await workout.finish()
                isStarting = false
                return
            }
            recordingCount = 0
            recorder.onFinished = { url in
                recordingCount += 1
                sync.enqueue(url)
            }
            isStarting = false
            await runCountdown()
        }
    }

    // MARK: Countdown

    private func runCountdown() async {
        for n in stride(from: 3, through: 1, by: -1) {
            phase = .countdown(n)
            WKInterfaceDevice.current().play(.directionUp)
            try? await Task.sleep(for: .seconds(1))
        }
        WKInterfaceDevice.current().play(.start)
        phase = .active
    }

    private func countdownPage(_ n: Int) -> some View {
        ZStack {
            Color.black
            Text("\(n)")
                .font(.system(size: 90, weight: .bold, design: .rounded))
                .foregroundStyle(Color.vermillion)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: n)
        }
        .ignoresSafeArea()
    }

    // MARK: Record

    private var recordPage: some View {
        recordButton
            .ignoresSafeArea()
    }

    @ViewBuilder
    private var recordButton: some View {
        let button = Button {
            if recorder.isRecording {
                recorder.stop()
            } else {
                recorder.start()
            }
        } label: {
            ZStack {
                (recorder.isRecording ? Color.vermillion : Color(white: 0.10))
                VStack(spacing: 8) {
                    Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(recorder.isRecording ? Color.paper : Color.vermillion)
                    if recorder.isRecording {
                        Text(timeString(recorder.elapsed))
                            .font(.title3.monospacedDigit())
                        if let s = recorder.secondsUntilAutoStop {
                            Text("Endet automatisch in \(s) s")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                            if recorder.canExtend {
                                Button {
                                    recorder.extend()
                                } label: {
                                    Text("Weiter aufnehmen")
                                        .font(.caption.bold())
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.yellow)
                                .foregroundStyle(.black)
                            } else {
                                Text("Maximale Länge erreicht")
                                    .font(.caption2)
                            }
                        } else {
                            Text("Tippen zum Stoppen")
                                .font(.caption2)
                        }
                    } else {
                        Text("Aufnahme")
                            .font(.headline)
                        HStack(spacing: 10) {
                            if recordingCount > 0 {
                                Text("\(recordingCount) ✓")
                                    .foregroundStyle(.secondary)
                            }
                            if let hr = workout.heartRate {
                                HStack(spacing: 2) {
                                    Image(systemName: "heart.fill")
                                        .foregroundStyle(.red)
                                    Text("\(Int(hr))")
                                }
                            }
                            if let meters = workout.distanceMeters {
                                HStack(spacing: 2) {
                                    Image(systemName: "figure.run")
                                        .foregroundStyle(.cyan)
                                    Text(kmString(meters))
                                }
                            }
                        }
                        .font(.caption2)
                        if let error = recorder.lastError {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)

        if #available(watchOS 11.0, *) {
            button.handGestureShortcut(.primaryAction)
        } else {
            button
        }
    }

    // MARK: End

    private var endPage: some View {
        VStack(spacing: 10) {
            Text("\(recordingCount) Aufnahmen")
                .font(.headline)
            if sync.pendingCount > 0 {
                Text("\(sync.pendingCount) warten auf Sync")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Alles synchronisiert")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
            Button(role: .destructive) {
                endSession()
            } label: {
                Label("Session beenden", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 4)
    }

    private func endSession() {
        phase = .ending
        let sessionEpoch = Int(workout.sessionStart?.timeIntervalSince1970 ?? 0)
        recorder.endSession()
        sync.retryOutbox()
        Task {
            let summary = await workout.finish()
            shareSessionMeta(summary, sessionEpoch: sessionEpoch)
            WKInterfaceDevice.current().play(.success)
            phase = .summary(
                recordings: recordingCount,
                duration: summary.duration,
                calories: summary.totalCalories,
                avgHeartRate: summary.averageHeartRate,
                distanceMeters: summary.distanceMeters,
                saveError: summary.saveError
            )
        }
    }

    /// Schreibt Dauer/Distanz/Puls/Kalorien als meta_<epoch>.json in die Outbox,
    /// damit die Web-Ansicht Spieldauer und Kilometer zeigen kann.
    private func shareSessionMeta(_ summary: WorkoutSummary, sessionEpoch: Int) {
        guard sessionEpoch > 0 else { return }
        let meta: [String: Double] = [
            "duration": summary.duration,
            "distanceMeters": summary.distanceMeters ?? 0,
            "calories": summary.totalCalories ?? 0,
            "avgHeartRate": summary.averageHeartRate ?? 0,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: meta) else { return }
        let url = Outbox.directory.appendingPathComponent("meta_\(sessionEpoch).json")
        try? data.write(to: url)
        sync.enqueue(url)
    }

    private var endingPage: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Session wird beendet…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Summary

    private func summaryPage(recordings: Int, duration: TimeInterval, calories: Double?, avgHeartRate: Double?, distanceMeters: Double?, saveError: String?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Label("Session beendet", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                summaryRow(icon: "clock", text: timeString(duration))
                summaryRow(icon: "mic.fill", text: String(localized: "\(recordings) Aufnahmen"))
                if sync.pendingCount > 0 {
                    summaryRow(icon: "arrow.triangle.2.circlepath", text: String(localized: "\(sync.pendingCount) syncen noch…"))
                } else if recordings > 0 {
                    summaryRow(icon: "iphone", text: String(localized: "Alle auf dem iPhone"))
                }
                if let meters = distanceMeters {
                    summaryRow(icon: "figure.run", text: kmString(meters))
                }
                if let hr = avgHeartRate {
                    summaryRow(icon: "heart.fill", text: String(localized: "Ø \(Int(hr)) bpm"))
                }
                if let kcal = calories {
                    summaryRow(icon: "flame.fill", text: "\(Int(kcal)) kcal")
                }
                if let saveError {
                    Text(saveError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else {
                    Text("Workout in Health gespeichert")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button("Fertig") {
                    phase = .idle
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
    }

    private func summaryRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(text)
        }
        .font(.body)
    }

    private func kmString(_ meters: Double) -> String {
        String(format: "%.2f km", meters / 1000).replacingOccurrences(of: ".", with: ",")
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let s = Int(interval)
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
