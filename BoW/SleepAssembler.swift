import Foundation
import HealthKit

struct SleepAssembler {
    static func assemble(samples: [HKCategorySample]) -> [SleepPayload] {
        guard !samples.isEmpty else { return [] }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: samples) { sample in
            calendar.startOfDay(for: sample.endDate)
        }

        return grouped.map { _, daySamples in
            let sorted = daySamples.sorted(by: { $0.startDate < $1.startDate })
            let start = sorted.first?.startDate ?? Date()
            let end = sorted.last?.endDate ?? Date()
            var rem: TimeInterval = 0
            var deep: TimeInterval = 0
            var core: TimeInterval = 0
            var awake: TimeInterval = 0

            for sample in sorted {
                let duration = sample.endDate.timeIntervalSince(sample.startDate)
                switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
                case .asleepREM: rem += duration
                case .asleepDeep: deep += duration
                case .asleepCore: core += duration
                case .awake: awake += duration
                default:
                    core += duration
                }
            }

            let total = rem + deep + core + awake
            return SleepPayload(
                id: UUID().uuidString,
                start: start,
                end: end,
                totalMinutes: total / 60.0,
                breakdown: SleepBreakdown(
                    remMinutes: rem / 60.0,
                    deepMinutes: deep / 60.0,
                    coreMinutes: core / 60.0,
                    awakeMinutes: awake / 60.0
                )
            )
        }
    }
}
