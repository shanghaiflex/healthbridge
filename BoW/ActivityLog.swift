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
        lock.unlock()
        if let data { try? data.write(to: fileURL, options: .atomic) }
        DispatchQueue.main.async { self.entries = list }
    }
}
