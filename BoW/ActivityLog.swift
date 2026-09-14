import Foundation

/// A small persisted journal of what the app did and when — the only way to see whether iOS really wakes
/// us in the background (HealthKit delivery, BGTask, finished downloads) without a cable and Console.app.
final class ActivityLog: ObservableObject {
    static let shared = ActivityLog()

    struct Entry: Codable, Identifiable {
        let id: UUID
        let at: Date
        let event: String
        let detail: String?
    }

    @Published private(set) var entries: [Entry] = []
    private let lock = NSLock()
    private let limit = 300
    private let fileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("activity.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
    }

    func log(_ event: String, detail: String? = nil) {
        let entry = Entry(id: UUID(), at: Date(), event: event, detail: detail)
        print("[BoW] \(event)\(detail.map { " — " + $0 } ?? "")")
        lock.lock()
        var list = entries
        list.insert(entry, at: 0)
        if list.count > limit { list.removeLast(list.count - limit) }
        let data = try? JSONEncoder().encode(list)
        unsent.append(entry)
        lock.unlock()
        if let data { try? data.write(to: fileURL, options: .atomic) }
        DispatchQueue.main.async { self.entries = list }
        scheduleUpload()
    }

    // MARK: - Mirror to the server (logs/bow.log on the mini)

    private var unsent: [Entry] = []
    private var uploadScheduled = false

    private func scheduleUpload() {
        lock.lock()
        let already = uploadScheduled
        uploadScheduled = true
        lock.unlock()
        guard !already else { return }
        // A short delay batches the burst of lines a launch or a sync produces into one request.
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { self.upload() }
    }

    private func upload() {
        lock.lock()
        let batch = unsent
        unsent.removeAll()
        uploadScheduled = false
        lock.unlock()
        guard !batch.isEmpty,
              let url = NetworkClient.shared.absoluteURL(path: "v1/app/log", baseURL: SettingsStore.shared.baseURL) else { return }
        let iso = ISO8601DateFormatter()
        let payload: [String: Any] = ["entries": batch.reversed().map { e -> [String: Any] in
            var d: [String: Any] = ["at": iso.string(from: e.at), "event": e.event]
            if let x = e.detail { d["detail"] = x }
            return d
        }]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(SettingsStore.shared.apiToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let ok = ((response as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2
            if !ok {
                // Keep them for the next attempt (offline, server restart); cap so a dead server can't grow this forever.
                self.lock.lock()
                self.unsent = Array((batch + self.unsent).suffix(200))
                self.lock.unlock()
            }
        }.resume()
    }
}
