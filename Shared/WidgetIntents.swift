import AppIntents
import WidgetKit
import SwiftUI
import LERNCore

struct PresetEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Widget preset")
    static var defaultQuery = PresetQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
struct PresetQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PresetEntity] { try await suggestedEntities().filter { identifiers.contains($0.id) } }
    func suggestedEntities() async throws -> [PresetEntity] {
        let store = try SharedStore.open()
        let presets: [WidgetPreset] = try await store.get("presets", default: [])
        return presets.map { PresetEntity(id: $0.id, name: $0.name) }
    }
    func defaultResult() async -> PresetEntity? { try? await suggestedEntities().first }
}
struct QuoteConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose your thoughts"
    static var description = IntentDescription("Choose a preset saved in LERN.")
    @Parameter(title: "Preset") var preset: PresetEntity?
}
struct FavoriteEntryIntent: AppIntent {
    static var title: LocalizedStringResource = "Favorite a thought"
    @Parameter(title: "Entry") var entryID: String
    init() {}
    init(entryID: String) { self.entryID = entryID }
    func perform() async throws -> some IntentResult {
        let store = try SharedStore.open()
        if let entry = try await store.entry(entryID) {
            try await store.setFlag(entryID, flag: "favorite", value: !entry.favorite)
            SharedStore.markNotificationScheduleDirty()
        }
        WidgetCenter.shared.reloadAllTimelines(); return .result()
    }
}
struct NextFortuneIntent: AppIntent {
    static var title: LocalizedStringResource = "Reveal a thought"
    @Parameter(title: "Preset") var presetID: String
    init() {}
    init(presetID: String) { self.presetID = presetID }
    func perform() async throws -> some IntentResult {
        let store = try SharedStore.open()
        let presets: [WidgetPreset] = try await store.get("presets", default: [])
        if let preset = presets.first(where: { $0.id == presetID }), let next = try await store.next(source: preset.source, surface: "fortune." + presetID, mode: .random) {
            try await store.put("fortune.current." + presetID, next.id)
        }
        WidgetCenter.shared.reloadAllTimelines(); return .result()
    }
}
#if !WIDGET_EXTENSION
struct GetWallpaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Wallpaper"
    static var description = IntentDescription("Create a wallpaper image from your local LERN source. Pass it to Set Wallpaper Photo in Shortcuts.")
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let store = try SharedStore.open()
        let preferences = try await store.get("preferences", default: Preferences())
        let themes = try await store.get("themes", default: ThemeValue.starters)
        guard let entry = try await store.next(source: preferences.wallpaperSource, surface: "wallpaper", mode: .shuffle) else { throw ImportFailure.empty }
        let theme = themes.first { $0.id == preferences.themeID } ?? ThemeValue.starters[0]
        let renderer = ImageRenderer(content: QuoteArtwork(entry: entry, theme: theme, watermark: preferences.watermark).frame(width: 430, height: 932))
        renderer.scale = 3
        guard let data = renderer.uiImage?.pngData() else { throw ImportFailure.malformed("Could not render wallpaper.") }
        return .result(value: IntentFile(data: data, filename: "LERN-wallpaper.png", type: .png))
    }
}
struct LERNShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: GetWallpaperIntent(), phrases: ["Get a wallpaper from \(.applicationName)"], shortTitle: "Get Wallpaper", systemImageName: "photo")
    }
}
#endif
