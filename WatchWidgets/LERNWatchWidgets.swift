import WidgetKit
import SwiftUI
import LERNCore

struct WatchEntry: TimelineEntry { let date: Date; let quote: String }
struct WatchProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchEntry { WatchEntry(date: Date(), quote: "LERN") }
    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) { completion(value()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) { completion(Timeline(entries: [value()], policy: .after(Date().addingTimeInterval(3600)))) }
    private func value() -> WatchEntry {
        let defaults = UserDefaults(suiteName: Product.appGroup) ?? .standard
        guard let data = defaults.data(forKey: "watch.entries"),
              let entries = WatchPayload.decodeEntries(data, version: defaults.object(forKey: "watch.entries.version") as? Int),
              !entries.isEmpty else { return WatchEntry(date: Date(), quote: String(localized: "Open LERN on iPhone")) }
        let savedIndex = defaults.integer(forKey: "watch.index")
        let index = entries.indices.contains(savedIndex) ? savedIndex : 0
        return WatchEntry(date: Date(), quote: entries[index].draft.text)
    }
}
struct WatchQuoteView: View {
    let entry: WatchEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        Group {
            if family == .accessoryCircular { Image(systemName: "text.quote").font(.title2) }
            else { VStack(alignment: .leading) { Text(Product.name).font(.caption2.bold()); Text(entry.quote).font(.caption).lineLimit(4) } }
        }.containerBackground(for: .widget) { Color.clear }
    }
}
@main struct LERNWatchWidgets: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LERNWatchThought", provider: WatchProvider()) { WatchQuoteView(entry: $0) }
            .configurationDisplayName("LERN thought").description("Your words on your wrist.")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
