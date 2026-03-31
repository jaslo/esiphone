// WatchWidgetExtension.swift  (Watch Widget Extension target ONLY — do NOT tick Watch App)

import SwiftUI
import WidgetKit

// ---------------------------------------------------------------------------
// MARK: - Timeline entry & provider
// ---------------------------------------------------------------------------

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let data: ComplicationData
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), data: ComplicationData(displayText: "118 ↑", lastUpdated: Date()))
    }
    
    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationEntry(date: Date(), data: ComplicationData.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let data = ComplicationData.load()
        let now  = Date()
        
        // Generate one entry per minute for the next 10 minutes
        // so the ring animates smoothly between pushes
        var entries: [ComplicationEntry] = []
        for minute in 0..<10 {
            let entryDate = now.addingTimeInterval(Double(minute) * 60)
            entries.append(ComplicationEntry(date: entryDate, data: data))
        }
        
        let timeline = Timeline(entries: entries, policy: .never)
        completion(timeline)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Complication view
// ---------------------------------------------------------------------------

struct CircularComplicationView: View {
    let entry: ComplicationEntry

    var body: some View {
        let age = min(1.0, entry.data.lastUpdated.timeIntervalSinceNow / -300)
        ZStack {
            ProgressView(value: 1 - age)
                .progressViewStyle(.circular)
                .tint(.white.opacity(0.4))
            Text(entry.data.displayText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(6)
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetLabel {
            Text(entry.data.ageDescription)
                .foregroundStyle(.secondary)
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Widget & bundle
// ---------------------------------------------------------------------------

struct ESiWatchComplication: Widget {
    let kind = "ESiWatchComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ComplicationProvider()) { entry in
            CircularComplicationView(entry: entry)
        }
        .configurationDisplayName("Eversense CGM")
        .description("Current glucose reading.")
        .supportedFamilies([.accessoryCircular])
    }
}

@main
struct ESiWatchComplicationBundle: WidgetBundle {
    var body: some Widget {
        ESiWatchComplication()
    }
}
