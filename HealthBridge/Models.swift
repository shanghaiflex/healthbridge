import Foundation

enum MetricKind: String, Codable {
    case hrvSDNN = "hrv_sdnn"
    case restingHeartRate = "resting_heart_rate"
    case steps = "steps"
    case activeEnergy = "active_energy"
}

struct WorkoutPayload: Codable, Identifiable {
    let id: String
    let workoutType: String
    let start: Date
    let end: Date
    let durationMinutes: Double
    let distanceMeters: Double?
    let calories: Double?
    let averageHeartRate: Double?
}

struct SleepPayload: Codable, Identifiable {
    let id: String
    let start: Date
    let end: Date
    let totalMinutes: Double
    let breakdown: SleepBreakdown
}

struct SleepBreakdown: Codable {
    let remMinutes: Double
    let deepMinutes: Double
    let coreMinutes: Double
    let awakeMinutes: Double
}

struct MetricPayload: Codable, Identifiable {
    let id: String
    let kind: MetricKind
    let start: Date
    let end: Date
    let value: Double
    let unit: String
}

struct DeletionPayload: Codable, Identifiable {
    let id: String
    let sampleType: String
}

struct WorkoutsBatchPayload: Codable {
    let items: [WorkoutPayload]
    let deleted: [DeletionPayload]
}

struct SleepBatchPayload: Codable {
    let items: [SleepPayload]
    let deleted: [DeletionPayload]
}

struct MetricsBatchPayload: Codable {
    let items: [MetricPayload]
    let deleted: [DeletionPayload]
}

struct QueueStatus {
    let queuedCount: Int
    let nextRetryAt: Date?
}
