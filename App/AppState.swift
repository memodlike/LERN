import SwiftUI
import SwiftData
import LERNCore
import WidgetKit
import UserNotifications

@MainActor @Observable final class AppState {
    let store: LibraryStore
    let scheduler: NotificationScheduler
    var preferences = Preferences()
    var themes = ThemeValue.starters
    var presets: [WidgetPreset] = []
    var reminders: [ReminderRule] = []
    var topics: [TopicValue] = []
    var current: EntryValue?
    var feedPast: [EntryValue] = []
    var feedPosition = -1
    var total = 0
    var error: String?
    var notice: String?
    var busy = false
    var loaded = false
    var sheet: AppSheet?
    var activeTheme: ThemeValue { themes.first { $0.id == preferences.themeID } ?? ThemeValue.starters[0] }
    init(store: LibraryStore) { self.store = store; self.scheduler = NotificationScheduler(store: store) }
    func load() async {
        do {
            preferences = try await store.get("preferences", default: Preferences())
            themes = try await store.get("themes", default: ThemeValue.starters)
            presets = try await store.get("presets", default: [WidgetPreset()])
            reminders = try await store.get("reminders", default: [])
            try await refreshLibrary()
            if current == nil { await next() }
            loaded = true
            await scheduler.replenish()
        } catch { self.error = error.localizedDescription }
    }
    func refreshLibrary() async throws { topics = try await store.topics(); total = try await store.totalCount() }
    func savePreferences() async {
        do { try await store.put("preferences", preferences); WidgetCenter.shared.reloadAllTimelines() }
        catch { self.error = error.localizedDescription }
    }
    func contentChanged() async {
        do { try await refreshLibrary(); await scheduler.replenish(); WidgetCenter.shared.reloadAllTimelines(); await WatchBridge.shared.update(store: store, source: preferences.watchSource) }
        catch { self.error = error.localizedDescription }
    }
    func next() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            if feedPosition + 1 < feedPast.count { feedPosition += 1; current = feedPast[feedPosition] }
            else if let item = try await store.next(source: preferences.feedSource, surface: "feed", mode: preferences.feedMode) {
                current = item; feedPast.append(item)
                if feedPast.count > 100 { feedPast.removeFirst() }
                feedPosition = feedPast.count - 1
            } else { current = nil }
            if let current {
                try await store.record(current.id, kind: "viewed")
                preferences.streak.read(on: Date())
                rotateTheme(); await savePreferences()
            }
        } catch { self.error = error.localizedDescription }
    }
    func previous() {
        guard feedPosition > 0 else { return }; feedPosition -= 1; current = feedPast[feedPosition]
    }
    func changeFeedSource(_ source: ContentSource) async {
        preferences.feedSource = source; feedPast = []; feedPosition = -1; current = nil
        await savePreferences(); await next()
    }
    func open(_ id: String, kind: String = "opened") async {
        do {
            guard let value = try await store.entry(id) else { notice = String(localized: "This entry is no longer in your library."); return }
            current = value; feedPast.append(value); feedPosition = feedPast.count - 1
            try await store.record(id, kind: kind); sheet = nil
        } catch { self.error = error.localizedDescription }
    }
    func flag(_ item: EntryValue, _ flag: String, _ value: Bool) async {
        do {
            try await store.setFlag(item.id, flag: flag, value: value)
            if current?.id == item.id { current = try await store.entry(item.id) }
            feedPast = feedPast.map { entry in guard entry.id == item.id else { return entry }; var updated = entry; if flag == "favorite" { updated.favorite = value }; return updated }
            if flag != "favorite" && value { feedPast = []; feedPosition = -1; await next() }
            await contentChanged()
        } catch { self.error = error.localizedDescription }
    }
    func saveReminders() async {
        do { try await store.put("reminders", reminders); await scheduler.replenish() }
        catch { self.error = error.localizedDescription }
    }
    func saveThemes() async {
        do { try await store.put("themes", themes); await savePreferences() }
        catch { self.error = error.localizedDescription }
    }
    func rotateTheme() {
        let eligible = themes.filter { preferences.themeMixIDs.contains($0.id) }
        guard !eligible.isEmpty else { return }
        if preferences.themeRotation == "entry" { preferences.themeID = eligible.randomElement()!.id }
        else if preferences.themeRotation == "day" {
            let day = Calendar.autoupdatingCurrent.ordinality(of: .day, in: .era, for: Date()) ?? 0
            preferences.themeID = eligible[day % eligible.count].id
        }
    }
}

enum AppSheet: String, Identifiable { case library, themes, profile, reminders, importFiles, compose, share, collections
    var id: String { rawValue }
}
