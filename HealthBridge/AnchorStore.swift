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

    func perform(sampleType: HKSampleType, anchorKey: AnchorKey) async throws -> AnchorResult {
        try await withCheckedThrowingContinuation { continuation in
            let anchor = self.anchor(for: anchorKey)
            let query = HKAnchoredObjectQuery(type: sampleType, predicate: nil, anchor: anchor, limit: HKObjectQueryNoLimit) { _, samples, deleted, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                self.store(anchor: newAnchor, for: anchorKey)
                continuation.resume(returning: AnchorResult(samples: samples ?? [], deleted: deleted ?? []))
            }
            self.healthStore.execute(query)
        }
    }
}
