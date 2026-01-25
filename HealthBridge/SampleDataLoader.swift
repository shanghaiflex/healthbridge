import Foundation

struct SampleDataBundle: Codable {
    let workouts: [WorkoutPayload]
    let sleep: [SleepPayload]
    let metrics: [MetricPayload]
}

enum SampleDataLoader {
    static func load() throws -> SampleDataBundle {
        guard let url = Bundle.main.url(forResource: "SampleData", withExtension: "json") else {
            throw NSError(domain: "HealthBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "SampleData.json not found."])
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SampleDataBundle.self, from: data)
    }
}
