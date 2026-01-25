import Foundation
import HealthKit

@MainActor
final class SyncCoordinator: ObservableObject {
    @Published var lastSync: Date?
    @Published var lastError: String?
    @Published var serverReachable: Bool = false
    @Published var queueCount: Int = 0

    private let healthKit = HealthKitManager.shared
    private let queue = QueueManager.shared
    private let settings = SettingsStore.shared
    private let network = NetworkClient.shared

    func bootstrap() async {
        await refreshQueueStatus()
        do {
            try await healthKit.requestAuthorization()
            try await healthKit.enableBackgroundDelivery()
            healthKit.startObserverQueries {
                Task { @MainActor in
                    await self.syncNow()
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
        await updateReachability()
    }

    func syncNow() async {
        do {
            try await enqueueHealthData()
            try await flushQueue()
            lastSync = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        await refreshQueueStatus()
        await updateReachability()
    }

    func enqueueHealthData() async throws {
        if settings.enableWorkouts {
            let workouts = try await healthKit.fetchWorkouts()
            try enqueueWorkouts(workouts)
        }
        if settings.enableSleep {
            let sleep = try await healthKit.fetchSleep()
            try enqueueSleep(sleep)
        }
        let metricsEnabled = settings.enableHRV || settings.enableRestingHR || settings.enableSteps || settings.enableActiveEnergy
        if metricsEnabled {
            let metrics = try await healthKit.fetchMetrics()
            let filtered = metrics.items.filter { payload in
                switch payload.kind {
                case .hrvSDNN: return settings.enableHRV
                case .restingHeartRate: return settings.enableRestingHR
                case .steps: return settings.enableSteps
                case .activeEnergy: return settings.enableActiveEnergy
                }
            }
            try enqueueMetrics(items: filtered, deleted: metrics.deleted)
        }
    }

    func flushQueue() async throws {
        await refreshQueueStatus()
        let batch = queue.nextBatch(limit: 5)
        guard !batch.isEmpty else { return }
        for item in batch {
            do {
                try await network.send(endpoint: item.endpoint, bodyData: item.bodyData, baseURL: settings.serverURL)
                queue.markSent(item)
            } catch {
                queue.markFailed(item)
                throw error
            }
        }
    }

    func updateReachability() async {
        do {
            serverReachable = try await network.healthCheck(baseURL: settings.serverURL)
        } catch {
            serverReachable = false
        }
    }

    func refreshQueueStatus() async {
        let status = queue.status()
        queueCount = status.queuedCount
    }

    func importSampleJSON() async {
        do {
            let payloads = try SampleDataLoader.load()
            try enqueue(payload: WorkoutsBatchPayload(items: payloads.workouts, deleted: []), endpoint: "v1/ingest/health/workouts")
            try enqueue(payload: SleepBatchPayload(items: payloads.sleep, deleted: []), endpoint: "v1/ingest/health/sleep")
            try enqueue(payload: MetricsBatchPayload(items: payloads.metrics, deleted: []), endpoint: "v1/ingest/health/metrics")
            try await flushQueue()
            lastSync = Date()
        } catch {
            lastError = error.localizedDescription
        }
        await refreshQueueStatus()
    }

    private func enqueueWorkouts(_ payload: (items: [WorkoutPayload], deleted: [DeletionPayload])) throws {
        try enqueueBatches(items: payload.items, deleted: payload.deleted, endpoint: "v1/ingest/health/workouts") { items, deleted in
            WorkoutsBatchPayload(items: items, deleted: deleted)
        }
    }

    private func enqueueSleep(_ payload: (items: [SleepPayload], deleted: [DeletionPayload])) throws {
        try enqueueBatches(items: payload.items, deleted: payload.deleted, endpoint: "v1/ingest/health/sleep") { items, deleted in
            SleepBatchPayload(items: items, deleted: deleted)
        }
    }

    private func enqueueMetrics(items: [MetricPayload], deleted: [DeletionPayload]) throws {
        try enqueueBatches(items: items, deleted: deleted, endpoint: "v1/ingest/health/metrics") { items, deleted in
            MetricsBatchPayload(items: items, deleted: deleted)
        }
    }

    private func enqueue<T: Encodable>(payload: T, endpoint: String) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        queue.enqueue(endpoint: endpoint, bodyData: data)
    }

    private func enqueueBatches<Item, Payload: Encodable>(items: [Item], deleted: [DeletionPayload], endpoint: String, build: ([Item], [DeletionPayload]) -> Payload) throws {
        let chunks = items.chunked(into: 200)
        for (index, chunk) in chunks.enumerated() {
            let deletions = index == 0 ? deleted : []
            let payload = build(chunk, deletions)
            try enqueue(payload: payload, endpoint: endpoint)
        }
        if items.isEmpty && !deleted.isEmpty {
            let payload = build([], deleted)
            try enqueue(payload: payload, endpoint: endpoint)
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
