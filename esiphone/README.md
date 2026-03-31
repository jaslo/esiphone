# Watch Complication — Setup Guide

## Project structure

```
YourApp/
├── Shared/
│   └── SharedModels.swift          ← Add to BOTH targets
├── iPhone/
│   ├── iPhoneApp.swift
│   ├── PhoneSupport.swift
│   └── ContentView.swift
└── WatchExtension/
    └── WatchExtension.swift
```

---

## Step-by-step Xcode setup

### 1. Create the project
- New Project → iOS App → add a watchOS companion target when prompted.
- Enable "Include Notification Scene" = No (you don't need it).

### 2. Add an App Group
Both targets must share a UserDefaults suite so data persists across launches.

1. Select your **iPhone target** → Signing & Capabilities → + Capability → App Groups
2. Add `group.com.yourcompany.yourapp`
3. Repeat for the **Watch Extension target** with the **same** group ID
4. Replace `group.com.yourcompany.yourapp` in `SharedModels.swift` with your actual group ID

### 3. Register the background fetch task (iPhone target)
In your iPhone app's `Info.plist`, add:

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.yourcompany.yourapp.fetch</string>
</array>
```

Replace `com.yourcompany.yourapp.fetch` with your actual bundle ID prefix.
Also update the matching string in `iPhoneApp.swift`.

### 4. Enable Background Modes (iPhone target)
iPhone target → Signing & Capabilities → + Capability → Background Modes
Check:
- [x] Background fetch
- [x] Background processing  ← needed for BGTaskScheduler

### 5. Add files to targets
- `SharedModels.swift` → check **both** iPhone and Watch Extension in the target membership panel
- `iPhoneApp.swift`, `PhoneSupport.swift`, `ContentView.swift` → iPhone target only
- `WatchExtension.swift` → Watch Extension target only

### 6. Update your API endpoint
In `PhoneSupport.swift`, replace:
```swift
static let endpoint = URL(string: "https://api.example.com/data")!
```
with your real URL. Add any auth headers in the same block.

### 7. Register the Widget (Watch Extension target)
In `WatchExtension.swift` the `MyComplication` struct already conforms to `Widget`.
Make sure your Watch Extension's `@main` entry point does **not** also conform to `Widget` —
use the `WatchApp` struct provided (which uses `@WKApplicationDelegateAdaptor`).

---

## How offline resilience works

| Scenario | Behaviour |
|---|---|
| Watch in Bluetooth range of iPhone | Data pushed via WCSession within seconds of a background fetch |
| Watch out of range, wakes later | WCSession delivers the buffered `applicationContext` when Bluetooth reconnects |
| Watch never reconnects | Complication shows the last value saved to UserDefaults — never blank |
| iPhone has no cell signal | iPhone background fetch is deferred by iOS until connectivity returns |

---

## Testing background fetch in Xcode

iOS Simulator can trigger a background fetch on demand:
1. Run the iPhone app on Simulator
2. In Xcode menu: **Debug → Simulate Background Fetch**

Or use the lldb console after pausing:
```
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.yourcompany.yourapp.fetch"]
```

---

## Customising the complication display

The `CircularComplicationView` in `WatchExtension.swift` shows:
- A `ProgressView` ring that fades as data ages (over 1 hour)
- The text string centred inside
- A `widgetLabel` below the circle (visible on Infograph face)

To change the appearance, edit `CircularComplicationView`. Common tweaks:
- Remove the ring: delete the `ProgressView` block
- Change font size: adjust `size: 14` in the `.font` modifier
- Truncate long strings: the `lineLimit(2)` + `minimumScaleFactor(0.5)` combo
  already handles this — lower the scale factor for smaller text

---

## If your API returns JSON instead of plain text

Replace the fetch logic in `APIClient.fetchData()`:

```swift
struct APIResponse: Decodable {
    let value: String  // ← match your JSON key
}

let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
return ComplicationData(displayText: decoded.value, lastUpdated: Date())
```
