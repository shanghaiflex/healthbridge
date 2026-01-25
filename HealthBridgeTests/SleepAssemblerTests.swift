import HealthKit
import XCTest
@testable import HealthBridge

final class SleepAssemblerTests: XCTestCase {
    func testSleepAssemblerAggregatesSamples() {
        let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 3600)
        let rem = HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.asleepREM.rawValue, start: start, end: start.addingTimeInterval(600))
        let deep = HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.asleepDeep.rawValue, start: start.addingTimeInterval(600), end: start.addingTimeInterval(1200))
        let core = HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: start.addingTimeInterval(1200), end: start.addingTimeInterval(2400))
        let awake = HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.awake.rawValue, start: start.addingTimeInterval(2400), end: end)

        let payloads = SleepAssembler.assemble(samples: [rem, deep, core, awake])
        XCTAssertEqual(payloads.count, 1)
        let payload = payloads[0]
        XCTAssertEqual(payload.totalMinutes, 60, accuracy: 0.01)
        XCTAssertEqual(payload.breakdown.remMinutes, 10, accuracy: 0.01)
        XCTAssertEqual(payload.breakdown.deepMinutes, 10, accuracy: 0.01)
        XCTAssertEqual(payload.breakdown.coreMinutes, 20, accuracy: 0.01)
        XCTAssertEqual(payload.breakdown.awakeMinutes, 20, accuracy: 0.01)
    }
}
