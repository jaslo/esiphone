// WatchApp.swift  (Watch App target ONLY — do NOT tick Watch Widget Extension)

import SwiftUI
import WidgetKit
import WatchConnectivity

// ---------------------------------------------------------------------------
// MARK: - Watch app entry point
// ---------------------------------------------------------------------------

@main
struct WatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
    }
}

class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        WatchSessionManager.shared.activate()
    }
}

// ---------------------------------------------------------------------------
// MARK: - WatchConnectivity session receiver
// ---------------------------------------------------------------------------

final class WatchSessionManager: NSObject, WCSessionDelegate {
    static let shared = WatchSessionManager()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let data = ComplicationData.fromContext(context) else { return }
        data.save()
        // Tell the widget extension to reload its timeline with the new value.
        WidgetCenter.shared.reloadTimelines(ofKind: "ESiWatchComplication")
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
}

// ---------------------------------------------------------------------------
// MARK: - Watch companion app UI
// ---------------------------------------------------------------------------

struct WatchContentView: View {
    @State private var data = ComplicationData.load()

    var body: some View {
        VStack(spacing: 8) {
            Text(data.displayText)
                .font(.title2).fontWeight(.bold)
            Text("Updated \(data.ageDescription)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .onReceive(NotificationCenter.default.publisher(for: WKApplication.didBecomeActiveNotification)) { _ in
            data = ComplicationData.load()
        }
    }
}
