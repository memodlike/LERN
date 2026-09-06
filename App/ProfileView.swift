import SwiftUI
import LERNCore
import WidgetKit

struct ProfileView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        @Bindable var state = state
        Form {
            Section("Personal") { TextField("Name", text: $state.preferences.name); TextField("Gender identity (optional)", text: $state.preferences.gender) }
            Section("Content") {
                NavigationLink("Content Preferences") { SourcePicker(source: $state.preferences.feedSource) }
                NavigationLink("My Content") { EntryListScreen(title: "My Content", source: ContentSource(myContentOnly: true)) }
                NavigationLink("Favorites") { EntryListScreen(title: "Favorites", source: ContentSource(favoritesOnly: true)) }
                NavigationLink("Collections") { CollectionsView() }
                NavigationLink("Past Content") { HistoryView() }
                NavigationLink("Muted Content") { EntryListScreen(title: "Muted Content", review: "muted") }
                NavigationLink("Disliked content") { EntryListScreen(title: "Disliked content", review: "disliked") }
                NavigationLink("Muted words") { MutedWordsView() }
            }
            Section("Experience") {
                NavigationLink("Reminders") { RemindersView() }
                NavigationLink("Home Screen Widgets") { WidgetPresetsView() }
                NavigationLink("Lock Screen Widgets") { SurfaceSettings(surface: "lock") }
                NavigationLink("Apple Watch") { SurfaceSettings(surface: "watch") }
                NavigationLink("Themes") { ThemesView() }
                NavigationLink("Wallpapers") { WallpaperView() }
                NavigationLink("App Icon") { AppIconsView() }
                NavigationLink("Streak") { StreakView() }
                NavigationLink("Resources / Books") { ResourcesView() }
            }
            Section("General") {
                Picker("Language", selection: $state.preferences.language) { Text("System").tag("system"); Text("English").tag("en"); Text("Русский").tag("ru") }
                Toggle("Haptics", isOn: $state.preferences.haptics)
                NavigationLink("Backup / Restore") { BackupView() }
                NavigationLink("Diagnostics") { DiagnosticsView() }
                NavigationLink("About") { Form { Text(Product.name).font(.largeTitle.bold()); Text("Your own words, always close. A private, local reading library."); Label("No account, ads or subscriptions", systemImage: "checkmark.shield"); Text("Version 1.0 · iOS 18+"); Text("Sample thoughts, icons and sounds are original. This app is not affiliated with Monkey Taps.").font(.footnote) }.navigationTitle("About") }
            }
        }.navigationTitle("Your space")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { Task { await state.savePreferences(); await state.contentChanged(); dismiss() } } } }
            .onDisappear { Task { await state.savePreferences() } }
    }
}
struct EntryListScreen: View {
    @Environment(AppState.self) private var state
    let title: LocalizedStringKey
    var source = ContentSource()
    var review = ""
    @State private var entries: [EntryValue] = []
    @State private var search = ""
    @State private var editing: EntryValue?
    @State private var delete: EntryValue?
    var body: some View {
        List {
            ForEach(entries) { entry in
                Button { Task { await state.open(entry.id) } } label: { EntryRow(entry: entry) }.foregroundStyle(.primary)
                    .contextMenu {
                        Button("Edit") { editing = entry }
                        Button(entry.favorite ? "Remove favorite" : "Favorite") { Task { await state.flag(entry, "favorite", !entry.favorite); await reload() } }
                        if !review.isEmpty { Button("Restore") { Task { await state.flag(entry, review, false); await reload() } } }
                        Button("Delete entry", role: .destructive) { delete = entry }
                    }
            }
            if entries.isEmpty { ContentUnavailableView("No entries found", systemImage: "text.page") }
            if entries.count >= 50 { Button("Load more") { Task { do { entries += try await state.store.page(source: source, search: search, offset: entries.count, review: review) } catch { state.error = error.localizedDescription } } } }
        }.navigationTitle(title).searchable(text: $search)
            .task(id: search) { await reload() }
            .sheet(item: $editing) { entry in NavigationStack { EntryEditor(existing: entry) }.environment(state) }
            .confirmationDialog("Delete this entry from your library and collections?", isPresented: Binding(get: { delete != nil }, set: { if !$0 { delete = nil } })) {
                Button("Delete entry", role: .destructive) { if let delete { Task { do { try await state.store.deleteEntry(delete.id); await state.contentChanged(); await reload() } catch { state.error = error.localizedDescription } } } }
            }
    }
    private func reload() async { do { entries = try await state.store.page(source: source, search: search, review: review) } catch { state.error = error.localizedDescription } }
}
struct MutedWordsView: View {
    @Environment(AppState.self) private var state
    @State private var word = ""
    var body: some View {
        Form {
            Section { TextField("Word or phrase", text: $word); Button("Mute") { let value = word.trimmingCharacters(in: .whitespacesAndNewlines); guard !value.isEmpty else { return }; state.preferences.mutedWords.append(value); word = ""; save() }.disabled(word.trimmingCharacters(in: .whitespaces).isEmpty) }
            Section("Muted words and phrases") { ForEach(state.preferences.mutedWords, id: \.self) { Text($0) }.onDelete { state.preferences.mutedWords.remove(atOffsets: $0); save() } }
        }.navigationTitle("Muted words")
    }
    private func save() { Task { await state.savePreferences(); await state.contentChanged() } }
}
struct StreakView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        @Bindable var state = state
        Form {
            Section { Text("\(state.preferences.streak.current)").font(.system(size: 72, weight: .light, design: .rounded)); Text("Days of reading"); LabeledContent("Longest streak", value: state.preferences.streak.longest.formatted()); LabeledContent("Available freezes", value: "\(state.preferences.streak.freezes) / 3") }
            Section { Toggle("Track my streak", isOn: $state.preferences.streak.enabled); Toggle("Evening streak reminder", isOn: $state.preferences.streakReminder) }
            Section { Text("A day counts when you read a thought in the feed. A freeze automatically covers one missed day. Earn one freeze every seven reading days, up to three. Opening the app twice never counts as two days.") }
        }.navigationTitle("Streak").onDisappear { Task { await state.savePreferences(); await state.scheduler.replenish() } }
    }
}
struct HistoryView: View {
    @Environment(AppState.self) private var state
    @State private var items: [HistoryValue] = []
    @State private var entries: [String: EntryValue] = [:]
    @State private var clear = false
    var body: some View {
        List {
            ForEach(items) { item in
                if let entry = entries[item.entryID] {
                    Button { Task { await state.open(entry.id) } } label: { VStack(alignment: .leading, spacing: 6) { EntryRow(entry: entry); HStack { Text(LocalizedStringKey(item.kind)); Spacer(); Text(item.date, format: .dateTime.month().day().hour().minute()) }.font(.caption).foregroundStyle(.secondary) } }.foregroundStyle(.primary)
                }
            }
            if items.isEmpty { Text("Your reading history will appear here.").foregroundStyle(.secondary) }
            if !items.isEmpty { Button("Load more") { Task { await load(more: true) } } }
        }.navigationTitle("Past Content").task { await load() }
            .toolbar { Button("Clear") { clear = true }.disabled(items.isEmpty) }
            .confirmationDialog("Clear reading history?", isPresented: $clear) { Button("Clear history", role: .destructive) { Task { do { try await state.store.clearHistory(); items = []; entries = [:] } catch { state.error = error.localizedDescription } } } }
    }
    private func load(more: Bool = false) async {
        do { let values = try await state.store.history(offset: more ? items.count : 0); if !more { items = [] }; items += values; for item in values { if entries[item.entryID] == nil { entries[item.entryID] = try await state.store.entry(item.entryID) } } } catch { state.error = error.localizedDescription }
    }
}
struct CollectionsView: View {
    @Environment(AppState.self) private var state
    @State private var name = ""
    @State private var deleting: TopicValue?
    var body: some View {
        List {
            Section { TextField("Collection name", text: $name); Button("Create collection") { Task { do { _ = try await state.store.createTopic(name: name); name = ""; try await state.refreshLibrary() } catch { state.error = error.localizedDescription } } }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
            ForEach(state.topics.filter { $0.kind == "collection" }) { topic in NavigationLink(topic.name) { CollectionDetail(topic: topic) }.swipeActions { Button("Delete", role: .destructive) { deleting = topic } } }
        }.navigationTitle("Collections")
            .confirmationDialog("Delete this collection? Entries stay in your library.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) { Button("Delete collection", role: .destructive) { if let deleting { Task { do { try await state.store.deleteTopic(deleting.id); await state.contentChanged() } catch { state.error = error.localizedDescription } } } } }
    }
}
struct CollectionDetail: View {
    @Environment(AppState.self) private var state
    let topic: TopicValue
    @State private var name = ""
    @State private var entries: [EntryValue] = []
    @State private var search = ""
    var body: some View {
        List {
            Section { TextField("Name", text: $name).onSubmit { Task { do { try await state.store.renameTopic(id: topic.id, name: name); try await state.refreshLibrary() } catch { state.error = error.localizedDescription } } }; Button("Read collection") { Task { await state.changeFeedSource(ContentSource(topicIDs: [topic.id])); state.sheet = nil } } }
            ForEach(entries) { entry in Button { Task { await state.open(entry.id) } } label: { EntryRow(entry: entry) }.foregroundStyle(.primary) }
                .onDelete { indices in let removed = indices.map { entries[$0].id }; Task { do { for id in removed { try await state.store.removeFromCollection(entryID: id, topicID: topic.id) }; await load() } catch { state.error = error.localizedDescription } } }
                .onMove { from, to in entries.move(fromOffsets: from, toOffset: to); Task { do { try await state.store.reorder(topicID: topic.id, ids: entries.map(\.id)) } catch { state.error = error.localizedDescription } } }
            if entries.count >= 200 { Text("Showing the first 200 matching entries. Search to narrow this collection.").font(.caption) }
        }.navigationTitle(topic.name).searchable(text: $search).toolbar { EditButton() }.task(id: search) { name = topic.name; await load() }
    }
    private func load() async { do { let ids = try await state.store.eligibleIDs(source: ContentSource(topicIDs: [topic.id])); let values = try await state.store.page(source: ContentSource(topicIDs: [topic.id]), search: search, limit: 200); let positions = Dictionary(ids.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { a, _ in a }); entries = values.sorted { (positions[$0.id] ?? 0) < (positions[$1.id] ?? 0) } } catch { state.error = error.localizedDescription } }
}
