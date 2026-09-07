import SwiftUI
import SwiftData
import LERNCore
import WidgetKit
import UserNotifications

@MainActor @Observable final class AppState {
    private(set) var store: LibraryStore
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
    private var refreshing = false
    private var foregroundRefreshPending = false
    private var selectedFeedSource = ContentSource()
    var activeTheme: ThemeValue { themes.first { $0.id == preferences.themeID } ?? ThemeValue.starters[0] }
    init(store: LibraryStore) { self.store = store; self.scheduler = NotificationScheduler(store: store) }
    func load() async {
        do {
            preferences = try await store.get("preferences", default: Preferences())
            themes = try await store.get("themes", default: ThemeValue.starters)
            presets = try await store.get("presets", default: [WidgetPreset()])
            reminders = try await store.get("reminders", default: [])
            selectedFeedSource = preferences.feedSource
            try await refreshLibrary()
            if current == nil { await next() }
            loaded = true
            await scheduler.replenish()
            await WatchBridge.shared.update(store: store, source: preferences.watchSource)
        } catch { self.error = error.localizedDescription }
    }
    func refreshOnForeground() async {
        guard loaded, !refreshing else { return }
        guard !busy else { foregroundRefreshPending = true; return }
        refreshing = true; busy = true
        defer { refreshing = false; finishSelection() }
        do {
            // A new context also discards cached models changed by widget intents.
            let freshStore = try SharedStore.open()
            store = freshStore
            scheduler.useStore(freshStore)
            let eligible = Set(try await freshStore.eligibleIDs(source: preferences.feedSource))
            let currentID = current?.id
            var refreshed: [EntryValue] = []
            for entry in feedPast where eligible.contains(entry.id) {
                if let value = try await freshStore.entry(entry.id) { refreshed.append(value) }
            }
            feedPast = refreshed
            if let currentID, let position = refreshed.lastIndex(where: { $0.id == currentID }) {
                feedPosition = position; current = refreshed[position]
            } else {
                current = nil; feedPosition = -1
                busy = false
                await next()
                busy = true
            }
            try await refreshLibrary()
            await scheduler.replenish()
            await WatchBridge.shared.update(store: freshStore, source: preferences.watchSource)
        } catch { self.error = error.localizedDescription }
    }
    private func finishSelection() {
        busy = false
        if foregroundRefreshPending {
            foregroundRefreshPending = false
            Task { await refreshOnForeground() }
        }
    }
    func refreshLibrary() async throws { topics = try await store.topics(); total = try await store.totalCount() }
    func savePreferences() async {
        let sourceChanged = selectedFeedSource != preferences.feedSource
        if sourceChanged {
            selectedFeedSource = preferences.feedSource; current = nil; feedPast = []; feedPosition = -1
        }
        do { try await store.put("preferences", preferences); WidgetCenter.shared.reloadAllTimelines() }
        catch { self.error = error.localizedDescription }
        if sourceChanged { await next() }
    }
    func contentChanged() async {
        do {
            try await refreshLibrary()
            let eligible = Set(try await store.eligibleIDs(source: preferences.feedSource))
            if selectedFeedSource != preferences.feedSource || (current != nil && !eligible.contains(current!.id)) {
                current = nil; feedPast = []; feedPosition = -1; await next()
            } else {
                let currentID = current?.id
                feedPast = feedPast.filter { eligible.contains($0.id) }
                feedPosition = feedPast.lastIndex(where: { $0.id == currentID }) ?? -1
                if let currentID { current = try await store.entry(currentID) }
            }
            await scheduler.replenish(); WidgetCenter.shared.reloadAllTimelines()
            await WatchBridge.shared.update(store: store, source: preferences.watchSource)
        } catch { self.error = error.localizedDescription }
    }
    func next() async {
        guard !busy else { return }; busy = true; defer { finishSelection() }
        if selectedFeedSource != preferences.feedSource {
            selectedFeedSource = preferences.feedSource; current = nil; feedPast = []; feedPosition = -1
        }
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
        preferences.feedSource = source; selectedFeedSource = source; feedPast = []; feedPosition = -1; current = nil
        await savePreferences(); await next()
    }
    func open(_ id: String, kind: String = "viewed") async {
        do {
            guard let value = try await store.entry(id) else { notice = String(localized: "This entry is no longer in your library."); return }
            current = value; feedPast.append(value)
            if feedPast.count > 100 { feedPast.removeFirst() }
            feedPosition = feedPast.count - 1
            preferences.streak.read(on: Date())
            try await store.put("preferences", preferences)
            try await store.record(id, kind: kind); sheet = nil
            WidgetCenter.shared.reloadAllTimelines()
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
