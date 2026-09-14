import BackgroundTasks
import Foundation
import UIKit

/// Two background tasks: a light app-refresh (health sync + «what to keep offline») that iOS runs when it
/// sees fit, and a processing task with network required, which is what gets a long download queue moving
/// at night on the charger. Neither runs if the user force-quits the app from the switcher — iOS rule.
final class BackgroundScheduler {
    static let shared = BackgroundScheduler()
    static let refreshId = "cc.bodywithoutorgans.bow.refresh"
    static let preloadId = "cc.bodywithoutorgans.bow.preload"

    private init() {}

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshId, using: nil) { task in
            self.handle(task, trigger: "bg-refresh")
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.preloadId, using: nil) { task in
            self.handle(task, trigger: "bg-processing")
        }
    }

    func schedule() {
        let refresh = BGAppRefreshTaskRequest(identifier: Self.refreshId)
        refresh.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do { try BGTaskScheduler.shared.submit(refresh) } catch { ActivityLog.shared.log("BG refresh не запланирован", detail: "\(error)") }

        let preload = BGProcessingTaskRequest(identifier: Self.preloadId)
        preload.requiresNetworkConnectivity = true
        preload.requiresExternalPower = false
        preload.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        do { try BGTaskScheduler.shared.submit(preload) } catch { ActivityLog.shared.log("BG processing не запланирован", detail: "\(error)") }
    }

    private func handle(_ task: BGTask, trigger: String) {
        schedule()
        ActivityLog.shared.log("Фоновая задача", detail: trigger)
        let work = Task { @MainActor in
            await LectureStore.shared.refresh(trigger: trigger)
            await SyncCoordinator.shared.syncNowCompletely(trigger: trigger)
        }
        task.expirationHandler = {
            work.cancel()
            ActivityLog.shared.log("Фоновая задача прервана", detail: trigger)
        }
        Task {
            _ = await work.result
            task.setTaskCompleted(success: !work.isCancelled)
        }
    }

    /// «Обновление контента» must be on for the app in iOS Settings, otherwise nothing above ever runs.
    static var refreshStatusText: String {
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: return "включено"
        case .denied: return "выключено в Настройках"
        case .restricted: return "запрещено (родительский контроль / MDM)"
        @unknown default: return "?"
        }
    }
}
