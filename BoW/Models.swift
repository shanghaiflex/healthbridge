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

/// One stretch of one stage of sleep, exactly as HealthKit holds it. Until 2026-09-14 the app added the stages up
/// per calendar day and sent one summary with a fresh UUID: a re-sync stored the same night again (the server saw
/// 20-hour nights), and a night that began before midnight was filed together with the next evening, so the two
/// could no longer be told apart. The sample's own uuid is stable, so sending the stages raw is idempotent, and
/// the server groups them into nights itself.
struct SleepPayload: Codable, Identifiable {
    let id: String
    let stage: String
    let start: Date
    let end: Date
    let minutes: Double
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
