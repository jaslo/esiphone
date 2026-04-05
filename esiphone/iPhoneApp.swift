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

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.vtable.esiphone.fetch",
            using: nil
        ) { task in
            self.handleBackgroundFetch(task: task as! BGAppRefreshTask)
        }

        PhoneSessionManager.shared.activate()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }

        scheduleBackgroundFetch()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        Task { await APIClient.fetchAndSync() }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task {
            await APIClient.fetchAndSync()
            completionHandler(.newData)
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        let defaults = UserDefaults(suiteName: SharedKeys.appGroupID)
        let oldToken = defaults?.string(forKey: "deviceToken")
        guard oldToken != tokenString else { return }
        defaults?.set(tokenString, forKey: "deviceToken")
        if let old = oldToken {
            Task { await PushRegistration.unregister(token: old) }
        }
        Task { await PushRegistration.register(token: tokenString) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNs registration failed: \(error)")
    }

    private func handleBackgroundFetch(task: BGAppRefreshTask) {
        scheduleBackgroundFetch()
        let fetchTask = Task {
            await APIClient.fetchAndSync()
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

