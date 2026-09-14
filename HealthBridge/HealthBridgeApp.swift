import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@main
struct HealthBridgeApp: App {
#if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
#endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

#if canImport(UIKit)
/// Everything that has to happen on *every* launch, including the ones iOS makes in the background with no UI.
/// This is why it lives in the app delegate and not in a SwiftUI view: when HealthKit background delivery
/// relaunches the app, no view is created, so a `.task` on ContentView never runs — the whole reason data used
/// to arrive only while the app was open on screen.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // BGTaskScheduler requires every identifier to be registered before launch finishes.
        BackgroundScheduler.shared.register()
        BackgroundScheduler.shared.schedule()

        Task { @MainActor in
            await SyncCoordinator.shared.startBackgroundDelivery()
        }
        return true
    }
}
#endif
