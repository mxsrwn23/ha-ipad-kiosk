import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Kiosk display must never dim/lock.
        application.isIdleTimerDisabled = true

        // Legacy Background Fetch (BGTaskScheduler needs iOS 13+, this target is iOS 12).
        application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = DashboardViewController()
        window.makeKeyAndVisible()
        self.window = window

        return true
    }

    func application(
        _ application: UIApplication,
        performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Give the dashboard a chance to recover its connection even if it was
        // briefly backgrounded (e.g. a phone call overlay) before returning to kiosk mode.
        (window?.rootViewController as? DashboardViewController)?.reloadIfNeeded()
        completionHandler(.newData)
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        (window?.rootViewController as? DashboardViewController)?.reloadIfNeeded()
    }
}
