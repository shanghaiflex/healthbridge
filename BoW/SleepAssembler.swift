import Foundation
import HealthKit

/// HealthKit's sleep samples, translated one for one. Nothing is grouped or added up here: assembling nights is
/// the server's job, where a regrouping does not silently overwrite what is already stored (see SleepPayload).
enum SleepAssembler {
    static func stage(of sample: HKCategorySample) -> String {
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .asleepREM: return "rem"
        case .asleepDeep: return "deep"
        case .asleepCore: return "core"
        case .asleepUnspecified: return "asleep"
        case .awake: return "awake"
        case .inBed: return "inBed"
        default: return "asleep"
        }
    }

    static func payloads(samples: [HKCategorySample]) -> [SleepPayload] {
        samples.map { sample in
            SleepPayload(
                id: sample.uuid.uuidString,
                stage: stage(of: sample),
                start: sample.startDate,
                end: sample.endDate,
                minutes: sample.endDate.timeIntervalSince(sample.startDate) / 60.0
            )
        }
    }
}
