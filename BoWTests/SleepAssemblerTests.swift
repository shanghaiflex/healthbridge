import HealthKit
import XCTest
@testable import BoW

final class SleepAssemblerTests: XCTestCase {
    func testStagesAreSentOneForOne() {
        let type = HKCategoryType(.sleepAnalysis)
        let start = Date()
        let rem = HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                                   start: start, end: start.addingTimeInterval(600))
        let awake = HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.awake.rawValue,
                                     start: start.addingTimeInterval(600), end: start.addingTimeInterval(1200))

        let payloads = SleepAssembler.payloads(samples: [rem, awake])

        XCTAssertEqual(payloads.count, 2)
        XCTAssertEqual(payloads[0].stage, "rem")
        XCTAssertEqual(payloads[0].minutes, 10, accuracy: 0.01)
        XCTAssertEqual(payloads[1].stage, "awake")
        XCTAssertEqual(payloads[1].minutes, 10, accuracy: 0.01)
        // The sample's own id, so sending the same night twice updates instead of storing it a second time.
        XCTAssertEqual(payloads[0].id, rem.uuid.uuidString)
    }
}
