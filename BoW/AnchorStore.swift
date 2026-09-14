import Foundation
import HealthKit

enum AnchorKey: String {
    case workout
    case sleep
    case hrv
    case restingHR
    case steps
    case activeEnergy
}

final class AnchorStore {
    struct AnchorResult {
        let samples: [HKSample]
        let deleted: [HKDeletedObject]
        /// Advances the stored anchor past these samples. Call it only once the samples are safely on their way
        /// to the server (i.e. written to the on-disk queue) — HealthKit hands every sample exactly once, so an
        /// anchor stored before delivery means anything lost in between is never offered again.
        let commit: () -> Void
    }

    private let defaults = UserDefaults.standard
    private let healthStore = HKHealthStore()

    func anchor(for key: AnchorKey) -> HKQueryAnchor? {
        guard let data = defaults.data(forKey: key.rawValue) else {
            return nil
        }
        do {
            return try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
        } catch {
            Logger.shared.error("Failed to decode anchor for \(key.rawValue): \(error.localizedDescription)")
            return nil
        }
    }

    func store(anchor: HKQueryAnchor?, for key: AnchorKey) {
        guard let anchor else {
            defaults.removeObject(forKey: key.rawValue)
            return
        }
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
            defaults.set(data, forKey: key.rawValue)
        } catch {
            Logger.shared.error("Failed to save anchor for \(key.rawValue): \(error.localizedDescription)")
        }
    }

    /// How far back the very first read goes. Years of step samples take longer to page through than a
    /// background launch lives; the site only looks at the last weeks anyway.
    static let initialHistoryDays = 365

    func resetAll() {
        for key in [AnchorKey.workout, .sleep, .hrv, .restingHR, .steps, .activeEnergy] {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    func perform(sampleType: HKSampleType, anchorKey: AnchorKey, limit: Int = HKObjectQueryNoLimit) async throws -> AnchorResult {
        try await withCheckedThrowingContinuation { continuation in
            let anchor = self.anchor(for: anchorKey)
            let predicate: NSPredicate? = anchor == nil
                ? HKQuery.predicateForSamples(withStart: Calendar.current.date(byAdding: .day, value: -Self.initialHistoryDays, to: Date()), end: nil)
                : nil
            let query = HKAnchoredObjectQuery(type: sampleType, predicate: predicate, anchor: anchor, limit: limit) { _, samples, deleted, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: AnchorResult(
                    samples: samples ?? [],
                    deleted: deleted ?? [],
                    commit: { self.store(anchor: newAnchor, for: anchorKey) }
                ))
            }
            self.healthStore.execute(query)
        }
    }
}
