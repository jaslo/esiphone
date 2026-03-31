// iPhoneApp.swift  (iPhone target)

import SwiftUI
import BackgroundTasks
import WatchConnectivity
import WidgetKit
import UserNotifications

@main
struct iPhoneApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Fetch fresh data whenever app comes to foreground
        Task { await performFetch() }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            print("📱 Authorization status: \(settings.authorizationStatus.rawValue)")
            // 0=notDetermined, 1=denied, 2=authorized, 3=provisional, 4=ephemeral
        }
    }
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 1. Register background fetch task (fallback when push isn't available).
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.vtable.esiphone.fetch",
            using: nil
        ) { task in
            self.handleBackgroundFetch(task: task as! BGAppRefreshTask)
        }

        // 2. Start WatchConnectivity.
        PhoneSessionManager.shared.activate()

        // 3. Register for silent push notifications.
        //application.registerForRemoteNotifications()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            print("📱 Push authorization granted: \(granted), error: \(error?.localizedDescription ?? "none")")
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
        
        // 4. Schedule background fetch as a fallback.
        scheduleBackgroundFetch()

        return true
    }

    // ---------------------------------------------------------------------------
    // MARK: - Silent push handler
    // Called by iOS when a silent push arrives (content-available: 1).
    // We have ~30 seconds to fetch and process data.
    // ---------------------------------------------------------------------------

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task {
            await performFetch()
            completionHandler(.newData)
        }
    }

    // ---------------------------------------------------------------------------
    // MARK: - APNs device token registration
    // ---------------------------------------------------------------------------

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("📱 Device token: \(tokenString)")
        // Get previous token if it exists
        let defaults = UserDefaults(suiteName: SharedKeys.appGroupID)
        let oldToken = defaults?.string(forKey: "deviceToken")
        // No change — nothing to do
        guard oldToken != tokenString else {
            print("📱 Token unchanged, skipping registration")
            return
        }

        // Save new token (replaces the old UserDefaults line)
        defaults?.set(tokenString, forKey: "deviceToken")
        
        // Unregister old token if different from new one
        if let old = oldToken {
            Task { await PushRegistration.unregister(token: old) }
        }
        Task { await PushRegistration.register(token: tokenString) }
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ APNs registration failed: \(error)")
    }

    // Shared fetch function called from all entry points
    func performFetch() async {
        await APIClient.fetchAndSync()
    }
    // ---------------------------------------------------------------------------
    // MARK: - Background fetch (fallback)
    // ---------------------------------------------------------------------------

    private func handleBackgroundFetch(task: BGAppRefreshTask) {
        scheduleBackgroundFetch()
        let fetchTask = Task {
            await performFetch()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            fetchTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    private func scheduleBackgroundFetch() {
        let request = BGAppRefreshTaskRequest(identifier: "com.vtable.esiphone.fetch")
        request.earliestBeginDate = nil
        try? BGTaskScheduler.shared.submit(request)
    }
}
