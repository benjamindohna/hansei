import Foundation
import HealthKit

struct WorkoutSummary {
    let duration: TimeInterval
    let totalCalories: Double?
    let averageHeartRate: Double?
    let distanceMeters: Double?
    let saveError: String?
}

/// Hält die App über eine HKWorkoutSession im Vordergrund (beim Armheben
/// erscheint die App statt des Zifferblatts) und zeichnet über den
/// HKLiveWorkoutBuilder Herzfrequenz + Kalorien auf. Beim Beenden wird das
/// Spiel als normales Outdoor-Fußball-Workout in Health gespeichert —
/// Fehlermap ersetzt damit die native Workout-App komplett.
@MainActor
final class WorkoutManager: NSObject, ObservableObject {
    @Published var isActive = false
    @Published var sessionStart: Date?
    @Published var heartRate: Double?
    @Published var distanceMeters: Double?
    @Published var lastError: String?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    func start() async -> Bool {
        lastError = nil
        do {
            let read: Set<HKObjectType> = [
                HKQuantityType(.heartRate),
                HKQuantityType(.activeEnergyBurned),
                HKQuantityType(.distanceWalkingRunning),
            ]
            try await store.requestAuthorization(toShare: [.workoutType()], read: read)

            let config = HKWorkoutConfiguration()
            config.activityType = .soccer
            config.locationType = .outdoor

            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self

            let start = Date()
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)

            self.session = session
            self.builder = builder
            self.sessionStart = start
            self.isActive = true
            return true
        } catch {
            lastError = "Workout-Start fehlgeschlagen: \(error.localizedDescription)"
            return false
        }
    }

    /// Beendet die Session und speichert das Workout in Health.
    /// Liefert in jedem Fall eine Zusammenfassung für den Abschluss-Screen.
    func finish() async -> WorkoutSummary {
        let start = sessionStart ?? Date()
        let duration = Date().timeIntervalSince(start)
        defer {
            session = nil
            builder = nil
            isActive = false
            sessionStart = nil
            heartRate = nil
            distanceMeters = nil
        }
        guard let session, let builder else {
            return WorkoutSummary(duration: duration, totalCalories: nil, averageHeartRate: nil, distanceMeters: nil, saveError: nil)
        }

        session.end()
        var saveError: String?
        do {
            try await builder.endCollection(at: Date())
        } catch {
            saveError = "Workout-Daten unvollständig: \(error.localizedDescription)"
        }

        let calories = builder.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?.doubleValue(for: .kilocalorie())
        let avgHR = builder.statistics(for: HKQuantityType(.heartRate))?
            .averageQuantity()?.doubleValue(for: .count().unitDivided(by: .minute()))
        let distance = builder.statistics(for: HKQuantityType(.distanceWalkingRunning))?
            .sumQuantity()?.doubleValue(for: .meter())

        do {
            _ = try await builder.finishWorkout()
        } catch {
            saveError = "Workout konnte nicht gespeichert werden: \(error.localizedDescription)"
        }

        return WorkoutSummary(
            duration: duration,
            totalCalories: calories,
            averageHeartRate: avgHR,
            distanceMeters: distance,
            saveError: saveError
        )
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastError = "Workout-Fehler: \(error.localizedDescription)"
        }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        let hrType = HKQuantityType(.heartRate)
        if collectedTypes.contains(hrType),
           let bpm = workoutBuilder.statistics(for: hrType)?.mostRecentQuantity()?
            .doubleValue(for: .count().unitDivided(by: .minute())) {
            Task { @MainActor in self.heartRate = bpm }
        }
        let distType = HKQuantityType(.distanceWalkingRunning)
        if collectedTypes.contains(distType),
           let meters = workoutBuilder.statistics(for: distType)?.sumQuantity()?
            .doubleValue(for: .meter()) {
            Task { @MainActor in self.distanceMeters = meters }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
