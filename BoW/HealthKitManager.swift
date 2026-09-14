import Foundation
import HealthKit

/// What one anchored read produced, plus the closure that advances the anchor past it.
struct FetchResult<Item> {
    let items: [Item]
    let deleted: [DeletionPayload]
    let commit: () -> Void
}

final class HealthKitManager {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()
    private let anchorStore = AnchorStore()
    private var observersStarted = false

    private init() {}

    /// Forget every anchor: the next sync re-reads the last year from scratch.
    func resetAnchors() { anchorStore.resetAll() }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let typesToShare: Set<HKSampleType> = []
        let typesToRead: Set<HKObjectType> = Set([
            HKObjectType.workoutType(),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            HKObjectType.quantityType(forIdentifier: .restingHeartRate),
            HKObjectType.quantityType(forIdentifier: .stepCount),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        ].compactMap { $0 as HKObjectType? })

        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
    }

    func enableBackgroundDelivery() async throws {
        let types: [HKSampleType] = [
            HKObjectType.workoutType(),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            HKObjectType.quantityType(forIdentifier: .restingHeartRate),
            HKObjectType.quantityType(forIdentifier: .stepCount),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        ].compactMap { $0 }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for type in types {
                group.addTask {
                    try await self.healthStore.enableBackgroundDelivery(for: type, frequency: .hourly)
                }
            }
            try await group.waitForAll()
        }
    }

    /// Starts the long-lived observer queries that let iOS wake the app on new HealthKit data.
    /// Must run at launch (see AppDelegate) — when iOS relaunches us in the background there is no UI, so
    /// anything hung off a SwiftUI view never runs and the update is dropped.
    /// `onUpdate` receives HealthKit's completion handler and must call it once the samples are handled:
    /// calling it early tells iOS the update was dealt with and it stops waking us as reliably.
    func startObserverQueries(onUpdate: @escaping (String, @escaping () -> Void) -> Void) {
        guard !observersStarted else { return }
        observersStarted = true

        let sampleTypes: [HKSampleType] = [
            HKObjectType.workoutType(),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            HKObjectType.quantityType(forIdentifier: .restingHeartRate),
            HKObjectType.quantityType(forIdentifier: .stepCount),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        ].compactMap { $0 }

        for type in sampleTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, error in
                if let error {
                    Logger.shared.error("Observer query error: \(error.localizedDescription)")
                    completionHandler()
                    return
                }
                onUpdate(type.identifier.replacingOccurrences(of: "HKQuantityTypeIdentifier", with: "").replacingOccurrences(of: "HKCategoryTypeIdentifier", with: "").replacingOccurrences(of: "HKWorkoutTypeIdentifier", with: "Workout"), completionHandler)
            }
            healthStore.execute(query)
        }
    }

    func fetchWorkouts() async throws -> FetchResult<WorkoutPayload> {
        let type = HKObjectType.workoutType()
        let result = try await anchorStore.perform(sampleType: type, anchorKey: .workout)
        let workouts = result.samples.compactMap { $0 as? HKWorkout }.map { workout in
            WorkoutPayload(
                id: workout.uuid.uuidString,
                workoutType: workout.workoutActivityType.name,
                start: workout.startDate,
                end: workout.endDate,
                durationMinutes: workout.duration / 60.0,
                distanceMeters: workout.totalDistance?.doubleValue(for: .meter()),
                calories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                averageHeartRate: workout.averageHeartRate
            )
        }
        let deletions = result.deleted.map { DeletionPayload(id: $0.uuid.uuidString, sampleType: "workout") }
        return FetchResult(items: workouts, deleted: deletions, commit: result.commit)
    }

    func fetchSleep() async throws -> FetchResult<SleepPayload> {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return FetchResult(items: [], deleted: [], commit: {})
        }
        let result = try await anchorStore.perform(sampleType: type, anchorKey: .sleep)
        let sleepSamples = result.samples.compactMap { $0 as? HKCategorySample }
        let payloads = SleepAssembler.assemble(samples: sleepSamples)
        let deletions = result.deleted.map { DeletionPayload(id: $0.uuid.uuidString, sampleType: "sleep") }
        return FetchResult(items: payloads, deleted: deletions, commit: result.commit)
    }

    /// Reads only the kinds the user has switched on. Reading a disabled kind would advance its anchor and the
    /// samples would be dropped by the filter downstream — silently lost for good.
    func fetchMetrics(kinds: Set<MetricKind>) async throws -> FetchResult<MetricPayload> {
        var items: [MetricPayload] = []
        var deletions: [DeletionPayload] = []
        var commits: [() -> Void] = []
        for metricType in MetricSampleType.allCases where kinds.contains(metricType.kind) {
            let result = try await fetchMetric(type: metricType)
            items.append(contentsOf: result.items)
            deletions.append(contentsOf: result.deleted)
            commits.append(result.commit)
        }
        return FetchResult(items: items, deleted: deletions, commit: { commits.forEach { $0() } })
    }

    /// One page of a single kind; the caller loops while pages come back full and commits after each one,
    /// so a first import interrupted by iOS resumes where it stopped instead of starting over.
    func fetchMetricPage(kind: MetricKind, limit: Int) async throws -> FetchResult<MetricPayload> {
        guard let metricType = MetricSampleType.allCases.first(where: { $0.kind == kind }) else {
            return FetchResult(items: [], deleted: [], commit: {})
        }
        return try await fetchMetric(type: metricType, limit: limit)
    }

    private func fetchMetric(type metricType: MetricSampleType, limit: Int = HKObjectQueryNoLimit) async throws -> FetchResult<MetricPayload> {
        guard let sampleType = metricType.hkType else { return FetchResult(items: [], deleted: [], commit: {}) }
        let result = try await anchorStore.perform(sampleType: sampleType, anchorKey: metricType.anchorKey, limit: limit)
        let quantitySamples = result.samples.compactMap { $0 as? HKQuantitySample }
        let mapped = quantitySamples.map { sample in
            MetricPayload(
                id: sample.uuid.uuidString,
                kind: metricType.kind,
                start: sample.startDate,
                end: sample.endDate,
                value: sample.quantity.doubleValue(for: metricType.unit),
                unit: metricType.unit.unitString
            )
        }
        let deletionType = metricType.kind.rawValue
        let deletedPayload = result.deleted.map { DeletionPayload(id: $0.uuid.uuidString, sampleType: deletionType) }
        return FetchResult(items: mapped, deleted: deletedPayload, commit: result.commit)
    }
}

private enum MetricSampleType: CaseIterable {
    case hrv
    case restingHeartRate
    case steps
    case activeEnergy

    var kind: MetricKind {
        switch self {
        case .hrv: return .hrvSDNN
        case .restingHeartRate: return .restingHeartRate
        case .steps: return .steps
        case .activeEnergy: return .activeEnergy
        }
    }

    var hkType: HKQuantityType? {
        switch self {
        case .hrv:
            return HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        case .restingHeartRate:
            return HKObjectType.quantityType(forIdentifier: .restingHeartRate)
        case .steps:
            return HKObjectType.quantityType(forIdentifier: .stepCount)
        case .activeEnergy:
            return HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        }
    }

    var unit: HKUnit {
        switch self {
        case .hrv:
            return HKUnit.secondUnit(with: .milli)
        case .restingHeartRate:
            return HKUnit.count().unitDivided(by: HKUnit.minute())
        case .steps:
            return HKUnit.count()
        case .activeEnergy:
            return HKUnit.kilocalorie()
        }
    }

    var anchorKey: AnchorKey {
        switch self {
        case .hrv: return .hrv
        case .restingHeartRate: return .restingHR
        case .steps: return .steps
        case .activeEnergy: return .activeEnergy
        }
    }
}

private extension HKUnit {
    var unitString: String {
        switch self {
        case HKUnit.secondUnit(with: .milli): return "ms"
        case HKUnit.count().unitDivided(by: HKUnit.minute()): return "count/min"
        case HKUnit.count(): return "count"
        case HKUnit.kilocalorie(): return "kcal"
        default: return "unit"
        }
    }
}

private extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: return "running"
        case .cycling: return "cycling"
        case .walking: return "walking"
        case .swimming: return "swimming"
        case .yoga: return "yoga"
        case .functionalStrengthTraining: return "functional_strength_training"
        case .other: return "other"
        default: return String(describing: self)
        }
    }
}

private extension HKWorkout {
    var averageHeartRate: Double? {
        guard let stats = statistics(for: HKQuantityType.quantityType(forIdentifier: .heartRate)!) else {
            return nil
        }
        let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
        return stats.averageQuantity()?.doubleValue(for: unit)
    }
}

private extension HKHealthStore {
    func enableBackgroundDelivery(for sampleType: HKSampleType, frequency: HKUpdateFrequency) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            enableBackgroundDelivery(for: sampleType, frequency: frequency) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(domain: "HealthBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "Background delivery not enabled."]))
                }
            }
        }
    }
}

private extension HKHealthStore {
    func requestAuthorization(toShare shareTypes: Set<HKSampleType>, read readTypes: Set<HKObjectType>) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            requestAuthorization(toShare: shareTypes, read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NSError(domain: "HealthBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "Authorization not granted."]))
                }
            }
        }
    }
}
