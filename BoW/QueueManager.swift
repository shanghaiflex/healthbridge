import Foundation

struct QueuedRequest: Codable, Identifiable {
    let id: UUID
    let endpoint: String
    let bodyData: Data
    let createdAt: Date
    var attemptCount: Int
    var nextAttemptAt: Date

    init(endpoint: String, bodyData: Data, createdAt: Date = Date(), attemptCount: Int = 0, nextAttemptAt: Date = Date()) {
        self.id = UUID()
        self.endpoint = endpoint
        self.bodyData = bodyData
        self.createdAt = createdAt
        self.attemptCount = attemptCount
        self.nextAttemptAt = nextAttemptAt
    }
}

/// On-disk retry queue, one JSON file per request, with an in-memory index so nothing ever re-reads the whole
/// directory. The old version decoded every file on every `status()` call — with a first import of a year of
/// steps (thousands of files) that pinned the main thread for seconds and the watchdog killed the app
/// (0x8BADF00D) before a single batch went out. Being an actor also keeps the IO off the main thread.
actor QueueManager {
    static let shared = QueueManager()

    private struct Meta {
        let id: UUID
        let endpoint: String
        let createdAt: Date
        var attemptCount: Int
        var nextAttemptAt: Date
        let size: Int
    }

    private let fileManager = FileManager.default
    private let queueDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var index: [UUID: Meta] = [:]
    private var loaded = false

    private init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        queueDirectory = base.appendingPathComponent("Queue", isDirectory: true)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        if !fileManager.fileExists(atPath: queueDirectory.path) {
            try? fileManager.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
        }
    }

    /// One pass over the directory, the first time the queue is touched after launch.
    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let files = try? fileManager.contentsOfDirectory(at: queueDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return }
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url), let item = try? decoder.decode(QueuedRequest.self, from: data) else { continue }
            index[item.id] = Meta(id: item.id, endpoint: item.endpoint, createdAt: item.createdAt,
                                  attemptCount: item.attemptCount, nextAttemptAt: item.nextAttemptAt, size: item.bodyData.count)
        }
    }

    func enqueue(endpoint: String, bodyData: Data) {
        loadIfNeeded()
        let item = QueuedRequest(endpoint: endpoint, bodyData: bodyData)
        save(item)
    }

    /// The next requests that are due, oldest first. Bodies are read from disk for this batch only.
    func nextBatch(limit: Int = 1) -> [QueuedRequest] {
        loadIfNeeded()
        let now = Date()
        let due = index.values.filter { $0.nextAttemptAt <= now }.sorted { $0.createdAt < $1.createdAt }.prefix(limit)
        var out: [QueuedRequest] = []
        for meta in due {
            let url = fileURL(for: meta.id)
            guard let data = try? Data(contentsOf: url), let item = try? decoder.decode(QueuedRequest.self, from: data) else {
                index[meta.id] = nil   // a file that vanished or rotted is not worth retrying forever
                try? fileManager.removeItem(at: url)
                continue
            }
            out.append(item)
        }
        return out
    }

    func markSent(_ item: QueuedRequest) {
        index[item.id] = nil
        try? fileManager.removeItem(at: fileURL(for: item.id))
    }

    func markFailed(_ item: QueuedRequest) {
        var updated = item
        updated.attemptCount += 1
        let delay = min(pow(2.0, Double(updated.attemptCount)), 300.0)
        updated.nextAttemptAt = Date().addingTimeInterval(delay)
        save(updated)
    }

    /// Drops every queued request. Used once when the import format changes (see SyncCoordinator.resetImportIfNeeded).
    func removeAll() -> Int {
        loadIfNeeded()
        let n = index.count
        index.removeAll()
        if let files = try? fileManager.contentsOfDirectory(at: queueDirectory, includingPropertiesForKeys: nil) {
            for url in files { try? fileManager.removeItem(at: url) }
        }
        return n
    }

    func status() -> QueueStatus {
        loadIfNeeded()
        let nextRetry = index.values.map(\.nextAttemptAt).min()
        return QueueStatus(queuedCount: index.count, nextRetryAt: nextRetry)
    }

    private func fileURL(for id: UUID) -> URL {
        queueDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    private func save(_ item: QueuedRequest) {
        do {
            let data = try encoder.encode(item)
            try data.write(to: fileURL(for: item.id), options: .atomic)
            index[item.id] = Meta(id: item.id, endpoint: item.endpoint, createdAt: item.createdAt,
                                  attemptCount: item.attemptCount, nextAttemptAt: item.nextAttemptAt, size: item.bodyData.count)
        } catch {
            Logger.shared.error("Failed to save queue item: \(error.localizedDescription)")
        }
    }
}
