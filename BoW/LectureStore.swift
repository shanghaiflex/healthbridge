import Foundation

/// The phone's copy of «what to keep offline». Asks the server for the list (which also makes the mini
/// fetch any audio it lacks), downloads what is missing locally, prunes what dropped off the list,
/// and pushes playback positions back. Works from its cache when there is no network.
@MainActor
final class LectureStore: ObservableObject {
    static let shared = LectureStore()

    @Published private(set) var items: [Lecture] = []
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var refreshing = false
    /// Preview-only: pretend these ids are on disk.
    var previewDownloaded: Set<String> = []

    private let defaults = UserDefaults.standard
    private let cacheKey = "preloadItems"
    private let pendingKey = "pendingPositions"
    private let listenedKey = "pendingListened"
    private let network = NetworkClient.shared
    private let settings = SettingsStore.shared
    private var refreshTask: Task<Void, Never>?

    private init() {
        if let data = defaults.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode([Lecture].self, from: data) {
            items = cached
        }
    }

    init(preview items: [Lecture], downloaded: Set<String>) {
        self.items = items
        self.previewDownloaded = downloaded
        self.lastRefresh = Date()
    }

    static let preview = LectureStore(preview: PreviewData.lectures, downloaded: [PreviewData.lectures[0].id])

    func isDownloaded(_ lecture: Lecture) -> Bool {
        previewDownloaded.contains(lecture.id) || DownloadManager.isDownloaded(lecture)
    }

    var downloadedCount: Int { items.filter { isDownloaded($0) }.count }

    // MARK: - Refresh

    /// One refresh at a time; a second caller just waits for the running one.
    func refresh(trigger: String) async {
        if let running = refreshTask {
            await running.value
            return
        }
        let task = Task { await performRefresh(trigger: trigger) }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func performRefresh(trigger: String) async {
        refreshing = true
        defer { refreshing = false }
        await flushPendingListened()
        await flushPendingPositions()
        do {
            let data = try await network.get(path: "api/lectures/preload", baseURL: settings.serverURL, authToken: settings.apiToken)
            let response = try JSONDecoder().decode(PreloadResponse.self, from: data)
            apply(response.items)
            lastRefresh = Date()
            lastError = nil
            let waiting = response.items.filter { $0.audio == nil }.count
            let toGet = response.items.filter { $0.audio != nil && !isDownloaded($0) }.count
            ActivityLog.shared.log("Список лекций (\(trigger))",
                                   detail: "\(response.items.count) в списке, скачать: \(toGet)" + (waiting > 0 ? ", сервер ещё качает: \(waiting)" : ""))
            for lecture in response.items where lecture.audio != nil && !isDownloaded(lecture) {
                DownloadManager.shared.start(lecture)
            }
            prune()
            SiteController.shared.pushDownloaded()
        } catch {
            lastError = describe(error)
            ActivityLog.shared.log("Список лекций не получен (\(trigger))", detail: lastError)
        }
    }

    private func apply(_ fresh: [Lecture]) {
        // Never let the server's older position overwrite what is playing right now on this phone.
        var merged = fresh
        if let current = PlayerEngine.shared.current, let i = merged.firstIndex(where: { $0.id == current.id }) {
            merged[i].position = max(merged[i].position, Int(PlayerEngine.shared.time))
        }
        items = merged
        if let data = try? JSONEncoder().encode(merged) { defaults.set(data, forKey: cacheKey) }
    }

    /// Drop files the server no longer lists (listened, dequeued) — except whatever is playing.
    private func prune() {
        let keep = Set(items.map(\.safeId))
        let playing = PlayerEngine.shared.current?.safeId
        for (safeId, url) in DownloadManager.storedFiles() where !keep.contains(safeId) && safeId != playing {
            try? FileManager.default.removeItem(at: url)
            ActivityLog.shared.log("Удалил файл", detail: safeId)
        }
    }

    nonisolated func downloadFinished(_ id: String) async {
        await MainActor.run {
            objectWillChange.send()
            SiteController.shared.pushDownloaded()
        }
    }

    // MARK: - Positions & status

    func savePosition(_ lecture: Lecture, seconds: Int) async {
        if let i = items.firstIndex(where: { $0.id == lecture.id }) {
            items[i].position = seconds
            if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: cacheKey) }
        }
        var pending = defaults.dictionary(forKey: pendingKey) as? [String: Int] ?? [:]
        pending[lecture.id] = seconds
        defaults.set(pending, forKey: pendingKey)
        await flushPendingPositions()
    }

    /// Positions that could not be sent (no network on the metro) wait here and go with the next request.
    private func flushPendingPositions() async {
        guard var pending = defaults.dictionary(forKey: pendingKey) as? [String: Int], !pending.isEmpty else { return }
        for (id, seconds) in pending {
            do {
                _ = try await network.patch(path: "api/lecture/\(id)", json: ["position": seconds],
                                            baseURL: settings.serverURL, authToken: settings.apiToken)
                pending[id] = nil
            } catch {
                break
            }
        }
        defaults.set(pending, forKey: pendingKey)
    }

    func markListened(_ lecture: Lecture) async {
        ActivityLog.shared.log("Прослушано", detail: lecture.title)
        var pending = defaults.dictionary(forKey: pendingKey) as? [String: Int] ?? [:]
        pending[lecture.id] = nil
        defaults.set(pending, forKey: pendingKey)
        var done = defaults.stringArray(forKey: listenedKey) ?? []
        if !done.contains(lecture.id) { done.append(lecture.id) }
        defaults.set(done, forKey: listenedKey)
        DownloadManager.shared.remove(lecture)
        items.removeAll { $0.id == lecture.id }
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: cacheKey) }
        await refresh(trigger: "next")
    }

    /// «Прослушано» verdicts that have not reached the server yet (finished on the metro).
    private func flushPendingListened() async {
        guard var done = defaults.stringArray(forKey: listenedKey), !done.isEmpty else { return }
        for id in done {
            do {
                _ = try await network.patch(path: "api/lecture/\(id)", json: ["status": "listened", "position": 0],
                                            baseURL: settings.serverURL, authToken: settings.apiToken)
                done.removeAll { $0 == id }
            } catch {
                break
            }
        }
        defaults.set(done, forKey: listenedKey)
    }

    /// The lecture to show in the hero: what played last, else the first on the list.
    var featured: Lecture? {
        if let id = defaults.string(forKey: "lastLectureId"), let l = items.first(where: { $0.id == id }) { return l }
        return items.first
    }

    func rememberFeatured(_ lecture: Lecture) {
        defaults.set(lecture.id, forKey: "lastLectureId")
    }

    /// Next downloaded lecture after the given one, for auto-advance.
    func next(after lecture: Lecture) -> Lecture? {
        guard let i = items.firstIndex(where: { $0.id == lecture.id }) else { return items.first { isDownloaded($0) } }
        return items[(i + 1)...].first { isDownloaded($0) } ?? items[..<i].first { isDownloaded($0) }
    }

    private func describe(_ error: Error) -> String {
        if let e = error as? URLError { return e.code == .notConnectedToInternet ? "нет сети" : e.localizedDescription }
        return error.localizedDescription
    }
}
