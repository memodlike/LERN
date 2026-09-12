import SwiftUI
import LERNCore
import WidgetKit

struct ProfileView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        @Bindable var state = state
        Form {
            Section("Personal") {
                TextField("Name", text: $state.preferences.name)
                TextField("Gender identity (optional)", text: $state.preferences.gender)
            }
            Section("Sanctuary Activity") {
                NavigationLink {
                    StreakView()
                } label: {
                    ProfileNavigationRow(title: "Reading Streak", subtitle: "Daily reading sanctuary progress", icon: "flame.fill", iconColor: .orange, badge: "\(state.preferences.streak.current) days")
                }
            }
            Section("Saved & Curated") {
                NavigationLink {
                    EntryListScreen(title: "Favorites", source: ContentSource(favoritesOnly: true))
                } label: {
                    ProfileNavigationRow(title: "Favorites", subtitle: "Your starred and cherished thoughts", icon: "heart.fill", iconColor: .pink)
                }
                NavigationLink {
                    EntryListScreen(title: "My Content", source: ContentSource(myContentOnly: true))
                } label: {
                    ProfileNavigationRow(title: "My Content", subtitle: "Original thoughts written by you", icon: "pencil.line", iconColor: .blue)
                }
                NavigationLink {
                    CollectionsView()
                } label: {
                    ProfileNavigationRow(title: "Collections", subtitle: "Organized thought folders", icon: "folder.fill", iconColor: .indigo, badge: "\(state.topics.filter { $0.kind == "collection" }.count)")
                }
                NavigationLink {
                    HistoryView()
                } label: {
                    ProfileNavigationRow(title: "Past Content", subtitle: "Review your recent reading history", icon: "clock.arrow.circlepath", iconColor: .teal)
                }
            }
            Section {
                NavigationLink {
                    SettingsView()
                } label: {
                    ProfileNavigationRow(title: "Settings", subtitle: "Preferences, appearance, surfaces and system", icon: "gearshape.fill", iconColor: .gray)
                }
            }
        }
        .navigationTitle("Your space")
        .toolbar {
            ToolbarItem(placement: .principal) { LogoGlassChrome() }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    Task {
                        await state.savePreferences(notificationImpact: false, reloadWidgets: false)
                        await state.contentChanged()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        @Bindable var state = state
        Form {
            Section("Reading Sources") {
                NavigationLink {
                    SourcePicker(source: $state.preferences.feedSource)
                } label: {
                    ProfileNavigationRow(title: "Feed Source Preferences", subtitle: "Choose active topics, tags, and filters", icon: "slider.horizontal.2.square", iconColor: .purple)
                }
                NavigationLink {
                    ResourcesView()
                } label: {
                    ProfileNavigationRow(title: "Resources / Books", subtitle: "Imported literature and catalogs", icon: "books.vertical.fill", iconColor: .orange)
                }
                Picker("Feed order", selection: Binding(get: { state.preferences.feedMode }, set: { state.preferences.feedMode = $0; state.feedPast = []; state.feedPosition = -1; Task { await state.savePreferences() } })) {
                    Text("Shuffle without repeats").tag(SelectionMode.shuffle)
                    Text("Sequential").tag(SelectionMode.sequential)
                    Text("Random").tag(SelectionMode.random)
                }
            }
            Section("Muting & Moderation") {
                NavigationLink {
                    MutedWordsView()
                } label: {
                    ProfileNavigationRow(title: "Muted words", subtitle: "Suppress thoughts matching specific phrases", icon: "text.badge.minus", iconColor: .gray, badge: "\(state.preferences.mutedWords.count)")
                }
                NavigationLink {
                    EntryListScreen(title: "Muted Content", review: "muted")
                } label: {
                    ProfileNavigationRow(title: "Muted Content", subtitle: "Thoughts manually hidden from your feed", icon: "speaker.slash.fill", iconColor: .brown)
                }
                NavigationLink {
                    EntryListScreen(title: "Disliked content", review: "disliked")
                } label: {
                    ProfileNavigationRow(title: "Disliked content", subtitle: "Thoughts excluded from rotations", icon: "hand.thumbsdown.fill", iconColor: .red)
                }
            }
            Section("Routine") {
                NavigationLink {
                    RemindersView()
                } label: {
                    ProfileNavigationRow(title: "Reminders", subtitle: "Daily schedule and alarms", icon: "bell.fill", iconColor: .red)
                }
                Toggle("Show thought text in notifications", isOn: $state.preferences.showNotificationPreview)
                Toggle("Evening streak reminder", isOn: $state.preferences.streakReminder)
            }
            Section("Surfaces") {
                NavigationLink {
                    WidgetPresetsView()
                } label: {
                    ProfileNavigationRow(title: "Home Screen Widgets", subtitle: "Custom layouts, sizes, and refresh rates", icon: "rectangle.3.group.fill", iconColor: .cyan, badge: "\(state.presets.count)")
                }
                NavigationLink {
                    SurfaceSettings(surface: "lock")
                } label: {
                    ProfileNavigationRow(title: "Lock Screen Widgets", subtitle: "Subtle inline and circular accessories", icon: "lock.iphone", iconColor: .mint)
                }
                NavigationLink {
                    SurfaceSettings(surface: "watch")
                } label: {
                    ProfileNavigationRow(title: "Apple Watch", subtitle: "Independent wrist reading sync", icon: "applewatch", iconColor: .green, badge: "\(WatchBridge.shared.syncedCount)")
                }
                NavigationLink {
                    WallpaperView()
                } label: {
                    ProfileNavigationRow(title: "Wallpapers", subtitle: "Dynamic typographic wallpapers & Shortcuts", icon: "photo.artframe", iconColor: .blue)
                }
            }
            Section("Personalize") {
                NavigationLink {
                    ThemesView()
                } label: {
                    ProfileNavigationRow(title: "Themes", subtitle: "Atmospheric color & typographic styling", icon: "paintpalette.fill", iconColor: .pink)
                }
                NavigationLink {
                    AppIconsView()
                } label: {
                    ProfileNavigationRow(title: "App Icon", subtitle: "Choose your Home Screen icon", icon: "app.gift.fill", iconColor: .purple)
                }
                NavigationLink {
                    AppearanceCustomizationView()
                } label: {
                    ProfileNavigationRow(title: "Glass Effect", subtitle: "iOS 18 translucent glass materials", icon: "sparkles", iconColor: .indigo)
                }
            }
            Section("General") {
                Picker("Language", selection: $state.preferences.language) {
                    Text("System").tag("system")
                    Text("English").tag("en")
                    Text("Русский").tag("ru")
                }
                Toggle("Haptics", isOn: $state.preferences.haptics)
                NavigationLink("Backup / Restore") { BackupView() }
                NavigationLink("Diagnostics") { DiagnosticsView() }
                NavigationLink("About") {
                    Form {
                        Text(Product.name).font(.largeTitle.bold())
                        Text("Your own words, always close. A private, local reading library.")
                        Label("No account, ads or subscriptions", systemImage: "checkmark.shield")
                        Text("Version 1.0 · iOS 18+")
                        Text("Sample thoughts, icons and sounds are original. This app is not affiliated with Monkey Taps.").font(.footnote)
                    }.navigationTitle("About")
                }
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    Task {
                        await state.savePreferences(notificationImpact: false, reloadWidgets: false)
                        await state.contentChanged()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ProfileNavigationRow: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let icon: String
    let iconColor: Color
    var badge: String? = nil

    init(title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, icon: String, iconColor: Color, badge: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColor = iconColor
        self.badge = badge
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(iconColor.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let badge {
                Text(badge)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
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
    @State private var hasMore = true
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
            if hasMore { Button("Load more") { Task { await loadMore() } } }
        }.navigationTitle(title).searchable(text: $search)
            .task(id: search) { await reload() }
            .sheet(item: $editing) { entry in NavigationStack { EntryEditor(existing: entry) }.environment(state) }
            .confirmationDialog("Delete this entry from your library and collections?", isPresented: Binding(get: { delete != nil }, set: { if !$0 { delete = nil } })) {
                Button("Delete entry", role: .destructive) { if let delete { Task { do { try await state.store.deleteEntry(delete.id); await state.contentChanged(); await reload() } catch { state.error = error.localizedDescription } } } }
            }
    }
    private func reload() async {
        do { let page = try await state.store.page(source: source, search: search, review: review); entries = page; hasMore = page.count == 50 }
        catch { state.error = error.localizedDescription }
    }
    private func loadMore() async {
        do { let page = try await state.store.page(source: source, search: search, offset: entries.count, review: review); guard !Task.isCancelled else { return }; entries += page.filter { next in !entries.contains(where: { $0.id == next.id }) }; hasMore = page.count == 50 }
        catch { state.error = error.localizedDescription }
    }
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
    @ScaledMetric(relativeTo: .largeTitle) private var streakSize: CGFloat = 72
    var body: some View {
        @Bindable var state = state
        Form {
            Section {
                VStack(spacing: 8) {
                    Text("\(state.preferences.streak.current)")
                        .font(.system(size: streakSize, weight: .light, design: .rounded))
                    Text("Days of reading")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(state.preferences.streak.current) days of reading")

                LabeledContent("Longest streak", value: state.preferences.streak.longest.formatted())
                LabeledContent("Available freezes", value: "\(state.preferences.streak.freezes) / 3")
                    .accessibilityLabel("Available freezes: \(state.preferences.streak.freezes) of 3")
            }
            Section {
                Toggle("Track my streak", isOn: $state.preferences.streak.enabled)
                Toggle("Evening streak reminder", isOn: $state.preferences.streakReminder)
            }
            Section {
                Text("A day counts when you read a thought in the feed. A freeze automatically covers one missed day. Earn one freeze every seven reading days, up to three. Opening the app twice never counts as two days.")
            }
        }
        .navigationTitle("Streak")
        .onDisappear { Task { await state.savePreferences(); await state.scheduler.replenish() } }
    }
}
struct HistoryView: View {
    @Environment(AppState.self) private var state
    @State private var items: [HistoryValue] = []
    @State private var entries: [String: EntryValue] = [:]
    @State private var clear = false
    @State private var hasMore = true
    var body: some View {
        List {
            ForEach(items) { item in
                if let entry = entries[item.entryID] {
                    Button { Task { await state.open(entry.id) } } label: { VStack(alignment: .leading, spacing: 6) { EntryRow(entry: entry); HStack { Text(LocalizedStringKey(item.kind)); Spacer(); Text(item.date, format: .dateTime.month().day().hour().minute()) }.font(.caption).foregroundStyle(.secondary) } }.foregroundStyle(.primary)
                }
            }
            if items.isEmpty { Text("Your reading history will appear here.").foregroundStyle(.secondary) }
            if hasMore { Button("Load more") { Task { await load(more: true) } } }
        }.navigationTitle("Past Content").task { await load() }
            .toolbar { Button("Clear") { clear = true }.disabled(items.isEmpty) }
            .confirmationDialog("Clear reading history?", isPresented: $clear) { Button("Clear history", role: .destructive) { Task { do { try await state.store.clearHistory(); items = []; entries = [:] } catch { state.error = error.localizedDescription } } } }
    }
    private func load(more: Bool = false) async {
        do {
            let values = try await state.store.history(offset: more ? items.count : 0)
            if !more { items = []; entries = [:] }
            let newItems = values.filter { value in !items.contains(where: { $0.id == value.id }) }
            items += newItems
            entries.merge(try await state.store.entries(ids: newItems.map(\.entryID)), uniquingKeysWith: { _, latest in latest })
            hasMore = values.count == 100
        } catch { state.error = error.localizedDescription }
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
                .onDelete { indices in let removed = indices.map { entries[$0].id }; Task { do { for id in removed { try await state.store.removeFromCollection(entryID: id, topicID: topic.id) }; await state.contentChanged(); await load() } catch { state.error = error.localizedDescription } } }
                .onMove { from, to in entries.move(fromOffsets: from, toOffset: to); Task { do { try await state.store.reorder(topicID: topic.id, ids: entries.map(\.id)) } catch { state.error = error.localizedDescription } } }
            if entries.count >= 200 { Text("Showing the first 200 matching entries. Search to narrow this collection.").font(.caption) }
        }.navigationTitle(topic.name).searchable(text: $search).toolbar { EditButton() }.task(id: search) { name = topic.name; await load() }
    }
    private func load() async { do { let ids = try await state.store.eligibleIDs(source: ContentSource(topicIDs: [topic.id])); let values = try await state.store.page(source: ContentSource(topicIDs: [topic.id]), search: search, limit: 200); let positions = Dictionary(ids.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { a, _ in a }); entries = values.sorted { (positions[$0.id] ?? 0) < (positions[$1.id] ?? 0) } } catch { state.error = error.localizedDescription } }
}
