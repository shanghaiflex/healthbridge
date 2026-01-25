import Foundation
import HealthKit

final class HealthKitManager {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()
    private let anchorStore = AnchorStore()

    private init() {}

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let typesToShare: Set<HKSampleType> = []
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            HKObjectType.quantityType(forIdentifier: .restingHeartRate),
            HKObjectType.quantityType(forIdentifier: .stepCount),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        ].compactMap { $0 }

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

    func startObserverQueries(updateHandler: @escaping () -> Void) {
        let sampleTypes: [HKSampleType] = [
            HKObjectType.workoutType(),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            HKObjectType.quantityType(forIdentifier: .restingHeartRate),
            HKObjectType.quantityType(forIdentifier: .stepCount),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
        ].compactMap { $0 }

        for type in sampleTypes {
            let query = observerQuery(for: type) {
                updateHandler()
            }
            healthStore.execute(query)
        }
    }

    func observerQuery(for sampleType: HKSampleType, updateHandler: @escaping () -> Void) -> HKObserverQuery {
        return HKObserverQuery(sampleType: sampleType, predicate: nil) { _, completionHandler, error in
            if let error {
                Logger.shared.error("Observer query error: \(error.localizedDescription)")
            }
            updateHandler()
            completionHandler()
        }
    }

    func fetchWorkouts() async throws -> (items: [WorkoutPayload], deleted: [DeletionPayload]) {
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
        return (workouts, deletions)
    }

    func fetchSleep() async throws -> (items: [SleepPayload], deleted: [DeletionPayload]) {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return ([], [])
        }
        let result = try await anchorStore.perform(sampleType: type, anchorKey: .sleep)
        let sleepSamples = result.samples.compactMap { $0 as? HKCategorySample }
        let payloads = SleepAssembler.assemble(samples: sleepSamples)
        let deletions = result.deleted.map { DeletionPayload(id: $0.uuid.uuidString, sampleType: "sleep") }
        return (payloads, deletions)
    }

    func fetchMetrics() async throws -> (items: [MetricPayload], deleted: [DeletionPayload]) {
        var items: [MetricPayload] = []
        var deletions: [DeletionPayload] = []
        for metricType in MetricSampleType.allCases {
            let result = try await fetchMetric(type: metricType)
            items.append(contentsOf: result.items)
            deletions.append(contentsOf: result.deleted)
        }
        return (items, deletions)
    }

    private func fetchMetric(type metricType: MetricSampleType) async throws -> (items: [MetricPayload], deleted: [DeletionPayload]) {
        guard let sampleType = metricType.hkType else { return ([], []) }
        let result = try await anchorStore.perform(sampleType: sampleType, anchorKey: metricType.anchorKey)
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
        return (mapped, deletedPayload)
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
        case .strengthTraining: return "strength_training"
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
        try await withCheckedThrowingContinuation { continuation in
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
        try await withCheckedThrowingContinuation { continuation in
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
