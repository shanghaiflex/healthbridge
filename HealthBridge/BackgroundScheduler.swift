import Foundation

#if canImport(BackgroundTasks) && !os(macOS)
import BackgroundTasks

final class BackgroundScheduler {
    static let shared = BackgroundScheduler()

    private init() {}

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.healthbridge.sync", using: nil) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.healthbridge.queueflush", using: nil) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }

    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: "com.healthbridge.sync")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)

        let queueRequest = BGAppRefreshTaskRequest(identifier: "com.healthbridge.queueflush")
        queueRequest.earliestBeginDate = Date(timeIntervalSinceNow: 10 * 60)
        try? BGTaskScheduler.shared.submit(queueRequest)
    }

    private func handleAppRefresh(task: BGAppRefreshTask) {
        BackgroundScheduler.shared.schedule()
        let coordinator = SyncCoordinator()
        let operation = Task {
            await coordinator.syncNow()
        }
        task.expirationHandler = {
            operation.cancel()
        }
        Task {
            await coordinator.refreshQueueStatus()
            task.setTaskCompleted(success: true)
        }
    }
}
#else
final class BackgroundScheduler {
    static let shared = BackgroundScheduler()

    private init() {}

    func register() {}
    func schedule() {}
}
#endif
