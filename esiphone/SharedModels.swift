// SharedModels.swift
// Add this file to BOTH the iPhone target and the Watch Extension target.

import Foundation

/// Keys used in WCSession application context and UserDefaults.
enum SharedKeys {
    static let displayText   = "displayText"
    static let lastUpdated   = "lastUpdated"
    static let appGroupID    = "group.com.vtable.esiphone"  // ← replace with your App Group ID
}

/// The data model shared between phone and watch.
struct ComplicationData: Codable {
    let displayText: String
    let lastUpdated: Date

    /// Convenience: how long ago the data was fetched, as a short string.
    var ageDescription: String {
        let mins = Int(Date().timeIntervalSince(lastUpdated) / 60)
        if mins < 1  { return "just now" }
        if mins < 60 { return "\(mins)m ago" }
        return "\(mins / 60)h ago"
    }
}

extension ComplicationData {
    /// Encode to a plain [String: Any] dictionary for WCSession application context.
    func toContext() -> [String: Any] {
        [
            SharedKeys.displayText: displayText,
            SharedKeys.lastUpdated: lastUpdated.timeIntervalSince1970
        ]
    }

    /// Decode from a WCSession application context dictionary.
    static func fromContext(_ context: [String: Any]) -> ComplicationData? {
        guard
            let text      = context[SharedKeys.displayText] as? String,
            let timestamp = context[SharedKeys.lastUpdated] as? TimeInterval
        else { return nil }
        return ComplicationData(displayText: text, lastUpdated: Date(timeIntervalSince1970: timestamp))
    }

    /// Persist to the shared App Group UserDefaults (readable by both targets).
    func save() {
        guard let defaults = UserDefaults(suiteName: SharedKeys.appGroupID) else { return }
        defaults.set(displayText, forKey: SharedKeys.displayText)
        defaults.set(lastUpdated.timeIntervalSince1970, forKey: SharedKeys.lastUpdated)
    }

    /// Load from the shared App Group UserDefaults.
    static func load() -> ComplicationData {
        let defaults   = UserDefaults(suiteName: SharedKeys.appGroupID)
        let text       = defaults?.string(forKey: SharedKeys.displayText) ?? "—"
        let timestamp  = defaults?.double(forKey: SharedKeys.lastUpdated) ?? 0
        let date       = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : Date()
        return ComplicationData(displayText: text, lastUpdated: date)
    }
}
