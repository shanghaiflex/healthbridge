import Foundation
import HealthKit

@MainActor
final class SyncCoordinator: ObservableObject {
    /// One instance for the whole app: the observer queries started at launch sync through this object, and the
    /// UI observes the same one. A per-view instance would die with the view and take background delivery with it.
    static let shared = SyncCoordinator()

    private static var syncInProgress = false
    private let maxPreferredMetricsRequestBytes = 12_000

    @Published var lastSync: Date?
    @Published var lastError: String?
    @Published var serverReachable: Bool = false
    @Published var queueCount: Int = 0
    @Published var lastSyncTrigger: String?

    private let healthKit = HealthKitManager.shared
    private let queue = QueueManager.shared
    private let settings = SettingsStore.shared
    private let network = NetworkClient.shared

    /// Called from the app delegate on every launch, foreground or background. No UI and no permission prompt
    /// here: in a background relaunch there is nobody to answer one, and by then authorization is already granted.
    func startBackgroundDelivery() async {
        do {
            try await healthKit.enableBackgroundDelivery()
        } catch {
            // Expected on the very first launch, before the user has granted access; the UI path retries.
            Logger.shared.error("Background delivery not enabled yet: \(formatError(error))")
        }
        healthKit.startObserverQueries { typeName, completionHandler in
            Task { @MainActor in
                await self.syncNowCompletely(trigger: "healthkit:\(typeName)")
                // Only now is HealthKit told the update was handled.
                completionHandler()
            }
        }
    }

    /// Called when the UI appears: asks for permission if needed, then makes sure background delivery is on.
    func bootstrap() async {
        await refreshQueueStatus()
        do {
            try await healthKit.requestAuthorization()
        } catch {
            lastError = formatError(error)
        }
        await startBackgroundDelivery()
        await updateReachability()
    }

    func syncNow(trigger: String = "manual") async {
        await syncNowCompletely(trigger: trigger)
    }

    private var currentTrigger = "manual"
    private var sentThisRun = 0

    func syncNowCompletely(trigger: String = "manual") async {
        guard beginSyncIfAvailable() else {
            Logger.shared.info("Sync skipped: another sync operation is already running.")
            return
        }
        defer { endSync() }
        currentTrigger = trigger
        sentThisRun = 0

        do {
            try await enqueueHealthData()
            let queued = queue.status().queuedCount
            try await flushQueueCompletely()
            lastSync = Date()
            lastError = nil
            if sentThisRun > 0 || trigger != "foreground" {
                ActivityLog.shared.log("Здоровье (\(trigger))", detail: queued == 0 ? "нового нет" : "отправлено пачек: \(sentThisRun)")
            }
            lastSyncTrigger = trigger
        } catch {
            lastError = formatError(error)
            ActivityLog.shared.log("Здоровье не отправилось (\(trigger))", detail: lastError)
        }
        await refreshQueueStatus()
        await updateReachability()
    }

    func enqueueHealthData() async throws {
        // Each anchor is advanced only after its batches are written to the on-disk queue: from that point the
        // samples survive a crash and are retried forever, so it is safe to stop asking HealthKit for them.
        if settings.enableWorkouts {
            let workouts = try await healthKit.fetchWorkouts()
            try enqueueWorkouts(items: workouts.items, deleted: workouts.deleted)
            workouts.commit()
        }
        if settings.enableSleep {
            let sleep = try await healthKit.fetchSleep()
            try enqueueSleep(items: sleep.items, deleted: sleep.deleted)
            sleep.commit()
        }
        if !enabledMetricKinds.isEmpty {
            let metrics = try await healthKit.fetchMetrics(kinds: enabledMetricKinds)
            try enqueueMetrics(items: metrics.items, deleted: metrics.deleted)
            metrics.commit()
        }
    }

    private var enabledMetricKinds: Set<MetricKind> {
        var kinds: Set<MetricKind> = []
        if settings.enableHRV { kinds.insert(.hrvSDNN) }
        if settings.enableRestingHR { kinds.insert(.restingHeartRate) }
        if settings.enableSteps { kinds.insert(.steps) }
        if settings.enableActiveEnergy { kinds.insert(.activeEnergy) }
        return kinds
    }

    func flushQueue() async throws {
        await refreshQueueStatus()
        // Process up to 50 items per flush to handle larger queues more efficiently
        let batch = queue.nextBatch(limit: 50)
        guard !batch.isEmpty else { return }
        for item in batch {
            do {
                if try splitOversizedMetricsRequestIfNeeded(item) {
                    continue
                }
                try await network.send(endpoint: item.endpoint, bodyData: item.bodyData, baseURL: settings.serverURL, authToken: settings.apiToken, trigger: currentTrigger)
                queue.markSent(item)
                sentThisRun += 1
            } catch {
                queue.markFailed(item)
                throw error
            }
        }
    }

    func flushQueueCompletely() async throws {
        // Keep flushing until the queue is empty
        var hasMore = true
        // Splitting re-enqueues work instead of sending it, so a round can legitimately end with nothing sent —
        // but only a handful of times, since each split halves the payload. Anything beyond that is a bug eating
        // the loop, and hanging here would also leave `syncInProgress` set and block every later sync.
        var roundsWithoutSend = 0
        while hasMore {
            await refreshQueueStatus()
            let batch = queue.nextBatch(limit: 50)
            guard !batch.isEmpty else {
                hasMore = false
                break
            }
            var sentSomething = false
            for item in batch {
                do {
                    if try splitOversizedMetricsRequestIfNeeded(item) {
                        continue
                    }
                    try await network.send(endpoint: item.endpoint, bodyData: item.bodyData, baseURL: settings.serverURL, authToken: settings.apiToken, trigger: currentTrigger)
                    queue.markSent(item)
                    sentThisRun += 1
                    sentSomething = true
                } catch {
                    queue.markFailed(item)
                    throw error
                }
            }
            roundsWithoutSend = sentSomething ? 0 : roundsWithoutSend + 1
            if roundsWithoutSend > 32 {
                Logger.shared.error("Flush made no progress in \(roundsWithoutSend) rounds; giving up to avoid spinning.")
                break
            }
        }
    }

    func updateReachability() async {
        do {
            serverReachable = try await network.healthCheck(baseURL: settings.serverURL, authToken: settings.apiToken)
        } catch {
            // Swallowing this silently made "Server reachable: No" impossible to tell apart from a stale value.
            Logger.shared.error("Health check failed: \(formatError(error))")
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
            lastError = formatError(error)
        }
        await refreshQueueStatus()
    }

    private func formatError(_ error: Error) -> String {
        if let networkError = error as? NetworkError {
            return networkError.localizedDescription
        }
        if let urlError = error as? URLError {
            return "Network error \(urlError.code.rawValue): \(urlError.localizedDescription)"
        }
        return error.localizedDescription
    }

    private func beginSyncIfAvailable() -> Bool {
        guard !Self.syncInProgress else { return false }
        Self.syncInProgress = true
        return true
    }

    private func endSync() {
        Self.syncInProgress = false
    }

    private func splitOversizedMetricsRequestIfNeeded(_ item: QueuedRequest) throws -> Bool {
        guard item.endpoint == "v1/ingest/health/metrics", item.bodyData.count > maxPreferredMetricsRequestBytes else {
            return false
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let batch = try? decoder.decode(MetricsBatchPayload.self, from: item.bodyData) else {
            Logger.shared.error("Failed to decode oversized metrics payload (\(item.bodyData.count) bytes). Sending as-is.")
            return false
        }

        // Every split must strictly shrink the payload. Re-chunking at the size the batch already has hands back
        // a byte-for-byte identical request, and the flush loop then splits it again forever: nothing is ever
        // sent, the queue never drains and the sync never returns.
        let unitCount = max(batch.items.count, batch.deleted.count)
        guard unitCount > 1 else {
            // A single sample that is still over the limit cannot be divided — send it and let the server judge.
            return false
        }
        let chunkSize = max(1, unitCount / 2)

        try enqueueMetrics(items: batch.items, deleted: batch.deleted, chunkSize: chunkSize)
        queue.markSent(item)
        Logger.shared.info("Split oversized metrics payload (\(item.bodyData.count) bytes, \(unitCount) units) into chunks of \(chunkSize).")
        return true
    }

    private func enqueueWorkouts(items: [WorkoutPayload], deleted: [DeletionPayload]) throws {
        try enqueueBatches(items: items, deleted: deleted, endpoint: "v1/ingest/health/workouts") { items, deleted in
            WorkoutsBatchPayload(items: items, deleted: deleted)
        }
    }

    private func enqueueSleep(items: [SleepPayload], deleted: [DeletionPayload]) throws {
        try enqueueBatches(items: items, deleted: deleted, endpoint: "v1/ingest/health/sleep") { items, deleted in
            SleepBatchPayload(items: items, deleted: deleted)
        }
    }

    private func enqueueMetrics(items: [MetricPayload], deleted: [DeletionPayload], chunkSize: Int = 50) throws {
        try enqueueBatches(items: items, deleted: deleted, endpoint: "v1/ingest/health/metrics", chunkSize: chunkSize) { items, deleted in
            MetricsBatchPayload(items: items, deleted: deleted)
        }
    }

    private func enqueue<T: Encodable>(payload: T, endpoint: String) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        queue.enqueue(endpoint: endpoint, bodyData: data)
    }

    private func enqueueBatches<Item, Payload: Encodable>(
        items: [Item],
        deleted: [DeletionPayload],
        endpoint: String,
        chunkSize: Int = 200,
        build: ([Item], [DeletionPayload]) -> Payload
    ) throws {
        let itemChunks = items.chunked(into: chunkSize)
        let deletionChunks = deleted.chunked(into: chunkSize)

        if !itemChunks.isEmpty {
            for (index, chunk) in itemChunks.enumerated() {
                let deletions = index < deletionChunks.count ? deletionChunks[index] : []
                let payload = build(chunk, deletions)
                try enqueue(payload: payload, endpoint: endpoint)
            }

            if deletionChunks.count > itemChunks.count {
                for index in itemChunks.count..<deletionChunks.count {
                    let payload = build([], deletionChunks[index])
                    try enqueue(payload: payload, endpoint: endpoint)
                }
            }
            return
        }

        if !deletionChunks.isEmpty {
            for chunk in deletionChunks {
                let payload = build([], chunk)
                try enqueue(payload: payload, endpoint: endpoint)
            }
            return
        }

        // No items and no deletions -> nothing to enqueue.
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
