import SwiftUI
import WidgetKit
import AppIntents
import LERNCore
import os

private let widgetLogger = Logger(subsystem: "com.memodlike.lern", category: "widget.timeline")

struct QuoteTimelineEntry: TimelineEntry {
    let date: Date
    var entry: EntryValue?
    var theme = ThemeValue.starters[0]
    var preset = WidgetPreset()
    var streak = StreakState()
}
struct QuoteProvider: AppIntentTimelineProvider {
    typealias Intent = QuoteConfigurationIntent
    typealias Entry = QuoteTimelineEntry
    func placeholder(in context: Context) -> Entry { Entry(date: Date()) }
    func snapshot(for configuration: Intent, in context: Context) async -> Entry { await make(configuration, family: context.family) }
    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let entry = await make(configuration, family: context.family)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(Double(max(30, entry.preset.refreshMinutes)) * 60)))
    }
    private func make(_ config: Intent, family: WidgetFamily) async -> Entry {
        do {
            let store = try SharedStore.open()
            let presets: [WidgetPreset] = try await store.get("presets", default: [WidgetPreset()])
            let prefs = try await store.get("preferences", default: Preferences())
            let themes = try await store.get("themes", default: ThemeValue.starters)
            var preset = presets.first { $0.id == config.preset?.id } ?? presets.first ?? WidgetPreset()
            let lock = family == .accessoryCircular || family == .accessoryInline || family == .accessoryRectangular
            if lock { preset.source = prefs.lockSource; preset.id = "lock" }
            var value: EntryValue?
            if preset.kind == "fortune" {
                let key = "fortune.current." + preset.id
                let id = try await store.get(key, default: "")
                let eligible = try await store.eligibleIDs(source: preset.source)
                if eligible.contains(id) { value = try await store.entry(id) }
                if value == nil {
                    value = try await store.next(source: preset.source, surface: "fortune." + preset.id, mode: .random)
                    try await store.put(key, value?.id ?? "")
                }
            } else {
                value = try await store.next(source: preset.source, surface: "widget." + preset.id, mode: preset.mode)
            }
            return Entry(date: Date(), entry: value, theme: themes.first { $0.id == preset.themeID } ?? themes.first ?? ThemeValue.starters[0], preset: preset, streak: prefs.streak)
        } catch {
            widgetLogger.error("timeline fallback kind=LERNQuoteWidget operation=load error=\(String(describing: type(of: error)), privacy: .public)")
            return Entry(date: Date())
        }
    }
}
struct QuoteWidgetView: View {
    let entry: QuoteTimelineEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        Group {
            if family == .accessoryCircular {
                VStack { Image(systemName: "text.quote"); Text(entry.streak.current.formatted()).font(.headline) }
            } else if family == .accessoryInline {
                Text(entry.entry?.draft.text ?? String(localized: "Open LERN to choose your words"))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if entry.preset.kind == "streak" { Label("\(entry.streak.current) days", systemImage: "flame").font(.caption) }
                    if entry.preset.kind == "fortune" && family != .accessoryRectangular { Label("A thought for you", systemImage: "sparkle").font(.caption) }
                    if let quote = entry.entry {
                        Text(quote.draft.text).font(.system(family == .systemLarge ? .title2 : .body, design: entry.theme.design)).fontWeight(entry.theme.fontWeight).minimumScaleFactor(0.65).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center).multilineTextAlignment(entry.theme.textAlignment)
                        if !quote.draft.author.isEmpty && family != .accessoryRectangular { Text(quote.draft.author).font(.caption).lineLimit(1) }
                        if entry.preset.showButtons && (family == .systemMedium || family == .systemLarge) {
                            HStack {
                                Button(intent: FavoriteEntryIntent(entryID: quote.id)) { Image(systemName: quote.favorite ? "heart.fill" : "heart") }.accessibilityLabel("Favorite")
                                Spacer()
                                if entry.preset.kind == "fortune" { Button(intent: NextFortuneIntent(presetID: entry.preset.id)) { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Reveal a thought") }
                                if let shareURL = URL(string: "lern://entry/\(quote.id)?share=1") {
                                    Link(destination: shareURL) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Open and share")
                                }
                            }.buttonStyle(.plain).font(.title3)
                        }
                    } else { Text("Open LERN to import your words.").font(.body) }
                }.padding(entry.preset.border ? 8 : 0).overlay { if entry.preset.border { RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.5), lineWidth: 1) } }
            }
        }.foregroundStyle(isAccessory ? Color.primary : entry.theme.textColor)
            .containerBackground(for: .widget) { Color(hex: entry.theme.background) }
            .widgetURL(URL(string: entry.entry.map { "lern://entry/\($0.id)" } ?? "lern://library"))
    }
    private var isAccessory: Bool { family == .accessoryCircular || family == .accessoryInline || family == .accessoryRectangular }
}
struct LERNQuoteWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "LERNQuoteWidget", intent: QuoteConfigurationIntent.self, provider: QuoteProvider()) { QuoteWidgetView(entry: $0) }
            .configurationDisplayName("Your thoughts").description("Daily content, streaks and fortunes from your own library.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}
@main struct LERNWidgets: WidgetBundle { var body: some Widget { LERNQuoteWidget() } }
