import HealthKit
import XCTest
@testable import BoW

final class SleepAssemblerTests: XCTestCase {
    func testSleepAssemblerAggregatesSamples() {
        Supported Destinationst core = HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, start: start.addingTimeInterval(1200), end: start.addingTimeInterval(2400))
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
