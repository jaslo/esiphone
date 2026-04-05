// iOSWidgets.swift  (Widget Extension target)

import SwiftUI
import WidgetKit

// ---------------------------------------------------------------------------
// MARK: - Timeline entry & provider
// ---------------------------------------------------------------------------

struct EversenseEntry: TimelineEntry {
    let date: Date
    let data: ComplicationData
}

struct EversenseProvider: TimelineProvider {
    func placeholder(in context: Context) -> EversenseEntry {
        EversenseEntry(date: Date(), data: ComplicationData(displayText: "118 →", lastUpdated: Date()))
    }
    
    func getSnapshot(in context: Context, completion: @escaping (EversenseEntry) -> Void) {
        completion(EversenseEntry(date: Date(), data: ComplicationData.load()))
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<EversenseEntry>) -> Void) {
        let data = ComplicationData.load()
        let now  = Date()
        
        // Generate one entry per minute for the next 10 minutes
        // so the ring animates smoothly between pushes
        var entries: [EversenseEntry] = []
        for minute in 0..<5 {
            let entryDate = now.addingTimeInterval(Double(minute) * 60)
            entries.append(EversenseEntry(date: entryDate, data: data))
        }
        
        let timeline = Timeline(entries: entries, policy: .never)
        completion(timeline)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Lock screen circular
// ---------------------------------------------------------------------------

struct LockCircularView: View {
    let entry: EversenseEntry

    var body: some View {
        let age = min(1.0, entry.data.lastUpdated.timeIntervalSinceNow / -300)
        ZStack {
            ProgressView(value: 1 - age)
                .progressViewStyle(.circular)
            Text(entry.data.displayText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(4)
        }
        .widgetLabel {
            Text(entry.data.ageDescription)
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Lock screen rectangular
// ---------------------------------------------------------------------------

struct LockRectangularView: View {
    let entry: EversenseEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Eversense CGM", systemImage: "waveform.path.ecg")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(entry.data.displayText)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(entry.data.lastUpdated, style: .relative)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// ---------------------------------------------------------------------------
// MARK: - StandBy / Home Screen small
// ---------------------------------------------------------------------------

struct StandbySmallView: View {
    let entry: EversenseEntry

    private var trendColor: Color {
        if entry.data.displayText.contains("↓↓") { return .red }
        if entry.data.displayText.contains("↑↑") { return .orange }
        if entry.data.displayText.contains("↓")  { return .yellow }
        if entry.data.displayText.contains("↑")  { return .green }
        return .primary
    }

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "waveform.path.ecg")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Eversense")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(entry.data.displayText)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(trendColor)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(entry.data.lastUpdated, style: .relative)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .containerBackground(for: .widget) { Color.black.opacity(0.85) }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Accessory widget (lock screen)
// ---------------------------------------------------------------------------

struct EversenseAccessoryWidget: Widget {
    let kind = "EversenseAccessoryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EversenseProvider()) { entry in
            Group {
                if entry.data.displayText.isEmpty {
                    // placeholder branch
                    Text("—")
                } else {
                    switch EversenseAccessoryWidget.family(for: entry) {
                    case .accessoryRectangular:
                        LockRectangularView(entry: entry)
                    default:
                        LockCircularView(entry: entry)
                    }
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Eversense CGM")
        .description("Current glucose on your lock screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }

    // WidgetFamily isn't available at Widget init time, so we infer from kind.
    // We use separate Widget structs per family group to avoid this problem.
    static func family(for entry: EversenseEntry) -> WidgetFamily { .accessoryCircular }
}

// ---------------------------------------------------------------------------
// MARK: - System widget (StandBy / Home Screen)
// ---------------------------------------------------------------------------

struct EversenseSystemWidget: Widget {
    let kind = "EversenseSystemWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EversenseProvider()) { entry in
            StandbySmallView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.black.opacity(0.85)
                }
        }
        .configurationDisplayName("Eversense CGM")
        .description("Current glucose on StandBy or Home Screen.")
        .supportedFamilies([.systemSmall])
    }
}

// ---------------------------------------------------------------------------
// MARK: - Entry view that reads widgetFamily from environment
// ---------------------------------------------------------------------------

struct EversenseEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: EversenseEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            LockCircularView(entry: entry)
        case .accessoryRectangular:
            LockRectangularView(entry: entry)
        default:
            StandbySmallView(entry: entry)
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Widget bundle
// ---------------------------------------------------------------------------

@main
struct EversenseWidgetBundle: WidgetBundle {
    var body: some Widget {
        EversenseAccessoryWidget()
        EversenseSystemWidget()
    }
}

