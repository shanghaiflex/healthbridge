import Foundation
import UIKit

/// Background downloads of lecture audio. A background URLSession keeps going after the app is suspended
/// or even killed by iOS; when a file lands the system relaunches us (see AppDelegate) and the delegate
/// below moves it into place. Files live in Application Support/Lectures, excluded from iCloud backup.
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()
    static let sessionId = "cc.bodywithoutorgans.bow.downloads"

    /// lecture id → 0…1
    @Published private(set) var progress: [String: Double] = [:]
    @Published private(set) var active: Set<String> = []
    var backgroundCompletion: (() -> Void)?

    private var session: URLSession?
    private let lock = NSLock()
    /// lecture id → how many times a broken download was resumed (the mini restarts on every deploy).
    private var resumes: [String: Int] = [:]

    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        var dir = base.appendingPathComponent("Lectures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return dir
    }()

    static func fileURL(for lecture: Lecture) -> URL {
        let ext = (lecture.audio as NSString?)?.pathExtension ?? "m4a"
        return directory.appendingPathComponent("\(lecture.safeId).\(ext.isEmpty ? "m4a" : ext)")
    }

    static func localFile(for lecture: Lecture) -> URL? {
        let url = fileURL(for: lecture)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func isDownloaded(_ lecture: Lecture) -> Bool { localFile(for: lecture) != nil }

    /// Every file we hold, keyed by safe id — used to prune what the server no longer asks for.
    static func storedFiles() -> [String: URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var out: [String: URL] = [:]
        for u in urls where !u.lastPathComponent.hasPrefix(".") {
            out[u.deletingPathExtension().lastPathComponent] = u
        }
        return out
    }

    /// (Re)creates the background session. Called at launch and when iOS hands us background-session events:
    /// the delegate only receives them if a session with the same identifier exists in this process.
    func reconnect() {
        lock.lock(); defer { lock.unlock() }
        guard session == nil else { return }
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionId)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.allowsCellularAccess = !SettingsStore.shared.wifiOnly
        config.allowsExpensiveNetworkAccess = !SettingsStore.shared.wifiOnly
        config.timeoutIntervalForResource = 6 * 3600
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        session?.getAllTasks { tasks in
            let ids = Set(tasks.compactMap { $0.taskDescription })
            DispatchQueue.main.async { self.active.formUnion(ids) }
        }
    }

    /// The Wi-Fi-only switch lives in the session configuration, so a change means a new session.
    /// In-flight tasks keep their old rules — only new downloads see the change.
    func applySettingsChange() {
        lock.lock()
        session?.finishTasksAndInvalidate()
        session = nil
        lock.unlock()
        reconnect()
    }

    func start(_ lecture: Lecture) {
        guard let path = lecture.audio, !Self.isDownloaded(lecture) else { return }
        if active.contains(lecture.id) { return }
        guard let url = NetworkClient.shared.absoluteURL(path: path, baseURL: SettingsStore.shared.serverURL) else { return }
        reconnect()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(SettingsStore.shared.apiToken)", forHTTPHeaderField: "Authorization")
        let task = session!.downloadTask(with: request)
        task.taskDescription = lecture.id
        task.countOfBytesClientExpectsToReceive = Int64(lecture.size ?? 200_000_000)
        DispatchQueue.main.async {
            self.active.insert(lecture.id)
            self.progress[lecture.id] = 0
        }
        ActivityLog.shared.log("Скачиваю", detail: "\(lecture.title) (\(Fmt.megabytes(lecture.size)))")
        task.resume()
    }

    func cancel(_ lectureId: String) {
        session?.getAllTasks { tasks in
            tasks.filter { $0.taskDescription == lectureId }.forEach { $0.cancel() }
        }
    }

    func remove(_ lecture: Lecture) {
        cancel(lecture.id)
        try? FileManager.default.removeItem(at: Self.fileURL(for: lecture))
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            ActivityLog.shared.log("Скачивание не удалось", detail: "\(id): HTTP \(status)")
            return
        }
        // The temp file is gone once this method returns, so the move must happen here, synchronously.
        let ext = downloadTask.originalRequest?.url?.pathExtension ?? "m4a"
        let dest = Self.directory.appendingPathComponent("\(id.replacingOccurrences(of: ":", with: "_")).\(ext.isEmpty ? "m4a" : ext)")
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: location, to: dest)
            let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? 0
            ActivityLog.shared.log("Скачано", detail: "\(id), \(Fmt.megabytes(size))")
            Task { await LectureStore.shared.downloadFinished(id) }
        } catch {
            ActivityLog.shared.log("Не смог сохранить файл", detail: "\(id): \(error.localizedDescription)")
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription, totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { self.progress[id] = p }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription else { return }
        if let error, (error as NSError).code != NSURLErrorCancelled {
            // A dropped connection (server restart, Wi-Fi handoff) leaves resume data: pick up where it stopped.
            let tries = resumes[id, default: 0]
            if let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data, tries < 8 {
                resumes[id] = tries + 1
                ActivityLog.shared.log("Докачиваю", detail: "\(id), попытка \(tries + 1)")
                let retry = session.downloadTask(withResumeData: data)
                retry.taskDescription = id
                retry.resume()
                return
            }
            ActivityLog.shared.log("Скачивание оборвалось", detail: "\(id): \(error.localizedDescription)")
        }
        resumes[id] = nil
        DispatchQueue.main.async {
            self.active.remove(id)
            self.progress[id] = nil
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletion?()
            self.backgroundCompletion = nil
        }
    }
}
