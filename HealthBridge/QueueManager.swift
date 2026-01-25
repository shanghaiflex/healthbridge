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

    enum CodingKeys: String, CodingKey {
        case id
        case endpoint
        case bodyData
        case createdAt
        case attemptCount
        case nextAttemptAt
    }
}

final class QueueManager {
    static let shared = QueueManager()

    private let fileManager = FileManager.default
    private let queueDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        queueDirectory = base.appendingPathComponent("Queue", isDirectory: true)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        ensureDirectory()
    }

    func enqueue(endpoint: String, bodyData: Data) {
        let item = QueuedRequest(endpoint: endpoint, bodyData: bodyData)
        save(item)
    }

    func nextBatch(limit: Int = 1) -> [QueuedRequest] {
        let items = loadAll().sorted { $0.nextAttemptAt < $1.nextAttemptAt }
        let ready = items.filter { $0.nextAttemptAt <= Date() }
        return Array(ready.prefix(limit))
    }

    func markSent(_ item: QueuedRequest) {
        let url = fileURL(for: item.id)
        try? fileManager.removeItem(at: url)
    }

    func markFailed(_ item: QueuedRequest) {
        var updated = item
        updated.attemptCount += 1
        let delay = min(pow(2.0, Double(updated.attemptCount)), 300.0)
        updated.nextAttemptAt = Date().addingTimeInterval(delay)
        save(updated)
    }

    func status() -> QueueStatus {
        let items = loadAll()
        let nextRetry = items.map { $0.nextAttemptAt }.sorted().first
        return QueueStatus(queuedCount: items.count, nextRetryAt: nextRetry)
    }

    private func ensureDirectory() {
        if !fileManager.fileExists(atPath: queueDirectory.path) {
            try? fileManager.createDirectory(at: queueDirectory, withIntermediateDirectories: true)
        }
    }

    private func fileURL(for id: UUID) -> URL {
        queueDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    private func save(_ item: QueuedRequest) {
        ensureDirectory()
        let url = fileURL(for: item.id)
        do {
            let data = try encoder.encode(item)
            try data.write(to: url, options: .atomic)
        } catch {
            Logger.shared.error("Failed to save queue item: \(error.localizedDescription)")
        }
    }

    private func loadAll() -> [QueuedRequest] {
        guard let files = try? fileManager.contentsOfDirectory(at: queueDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(QueuedRequest.self, from: data)
        }
    }
}
