import SwiftUI
import UIKit
import UserNotifications

@main
struct BoWApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                SiteController.resumeAll()
                Task { await LectureStore.shared.refresh(trigger: "foreground") }
                Task { await SyncCoordinator.shared.syncNowCompletely(trigger: "foreground") }
                Task { await Notifier.shared.check(trigger: "foreground") }
            case .background:
                PlayerEngine.shared.flushPosition(force: true)
                BackgroundScheduler.shared.schedule()
            default:
                break
            }
        }
    }
}

/// Everything that has to happen on *every* launch, including the ones iOS makes in the background with no UI
/// (HealthKit background delivery, BGTaskScheduler, a finished background download). A `.task` on a SwiftUI
/// view never runs in those launches, which is why background sync used to work only while the app was on screen.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Theme.configureAppearance()
        ActivityLog.shared.log("Запуск", detail: application.applicationState == .background ? "в фоне, системой" : "пользователем")
        // BGTaskScheduler requires every identifier to be registered before launch finishes.
        BackgroundScheduler.shared.register()
        // Делегат ставится до конца запуска, иначе тап по уведомлению, которым открыли приложение, пропадёт.
        UNUserNotificationCenter.current().delegate = self
        BackgroundScheduler.shared.schedule()
        PlayerEngine.shared.configure()
        DownloadManager.shared.reconnect()
        Task { @MainActor in
            await SyncCoordinator.shared.startBackgroundDelivery()
            await SyncCoordinator.shared.resetImportIfNeeded()
            // Every launch syncs — including the ones with no UI (locked phone, background relaunch by iOS):
            // waiting for a view to appear meant a launch on a locked phone did nothing at all.
            await LectureStore.shared.refresh(trigger: "launch")
            await SyncCoordinator.shared.syncNowCompletely(trigger: "launch")
            await Notifier.shared.check(trigger: "launch")
        }
        return true
    }

    /// Уведомление пришло, пока приложение открыто: показать его баннером, а не проглотить.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// Тап по уведомлению — открыть ту страницу, о которой оно было.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let page = response.notification.request.content.userInfo["page"] as? String ?? ""
        await MainActor.run { Notifier.open(page: page) }
    }

    /// iOS relaunched us because a background download finished (or all of them did). The completion handler
    /// must be called after the session delegate has processed the events, or iOS stops trusting the app.
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        DownloadManager.shared.backgroundCompletion = completionHandler
        DownloadManager.shared.reconnect()
    }
}
