import SwiftUI
import LERNCore

private struct LibraryQuery: Hashable { let source: ContentSource; let search: String }

struct LibraryView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var source = ContentSource()
    @State private var entries: [EntryValue] = []
    @State private var loading = false
    @State private var hasMore = true
    @State private var newCollection = false
    @State private var collectionName = ""
    @State private var topicForDetails: TopicValue?
    @State private var topicForDeletion: TopicValue?
    @State private var topicForRename: TopicValue?
    @State private var renamedTopic = ""
    var body: some View {
        List {
            if search.isEmpty {
                Section {
                    NavigationLink { ImportView() } label: { Label("Import files", systemImage: "square.and.arrow.down") }
                    NavigationLink { EntryEditor() } label: { Label("Write a thought", systemImage: "square.and.pencil") }
                }
                Section("Feed source") {
                    Text("Search finds entries below. Choose a source here, then confirm before changing what the Feed reads.").font(.caption).foregroundStyle(.secondary)
                    sourceRow("All entries", symbol: "square.stack", value: ContentSource())
                    sourceRow("Favorites", symbol: "heart", value: ContentSource(favoritesOnly: true))
                    sourceRow("My Content", symbol: "pencil.line", value: ContentSource(myContentOnly: true))
                    ForEach(visibleTopics) { topic in
                        topicRow(topic)
                        if topic.kind == "import" {
                            ForEach(state.topics.filter { $0.parentTopicID == topic.id }) { section in sectionRow(section) }
                        }
                    }
                    NavigationLink { SourcePicker(source: Binding(get: { source }, set: { source = $0 })) } label: { Label("Mix topics or choose a tag", systemImage: "line.3.horizontal.decrease") }
                }
                Section {
                    Button("Start reading · \(selectedSourceName)") { Task { await state.changeFeedSource(source); dismiss() } }.accessibilityIdentifier("library.read")
                    Picker("Order", selection: Binding(get: { state.preferences.feedMode }, set: { state.preferences.feedMode = $0; state.feedPast = []; state.feedPosition = -1; Task { await state.savePreferences() } })) {
                        Text("Shuffle without repeats").tag(SelectionMode.shuffle); Text("Sequential").tag(SelectionMode.sequential); Text("Random").tag(SelectionMode.random)
                    }
                }
            }
            Section(search.isEmpty ? "Entries" : "Search results") {
                ForEach(entries) { entry in
                    Button { Task { await state.open(entry.id); dismiss() } } label: { EntryRow(entry: entry) }.foregroundStyle(.primary)
                        .swipeActions { Button { Task { await state.flag(entry, "favorite", !entry.favorite); await reload() } } label: { Image(systemName: entry.favorite ? "heart.slash" : "heart") }.tint(.pink) }
                }
                if loading { ProgressView().frame(maxWidth: .infinity) }
                else if entries.isEmpty { Text("No entries found").foregroundStyle(.secondary) }
                else if hasMore { Button("Load more") { Task { await loadMore() } } }
            }
        }
        .navigationTitle("Your library")
        .searchable(text: $search, prompt: "Text, author, source or tag")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(item: $topicForDetails) { LibraryDetailsView(topic: $0) }
        .alert("Rename library", isPresented: Binding(get: { topicForRename != nil }, set: { if !$0 { topicForRename = nil } })) {
            TextField("Library name", text: $renamedTopic)
            Button("Save") { if let topic = topicForRename { Task { await state.renameLibrary(id: topic.id, name: renamedTopic) }; topicForRename = nil } }
            Button("Cancel", role: .cancel) { topicForRename = nil }
        }
        .confirmationDialog("Delete this imported library?", isPresented: Binding(get: { topicForDeletion != nil }, set: { if !$0 { topicForDeletion = nil } }), titleVisibility: .visible) {
            Button("Delete library", role: .destructive) { if let topic = topicForDeletion { Task { await state.deleteImportedLibrary(id: topic.id) }; topicForDeletion = nil } }
            Button("Cancel", role: .cancel) { topicForDeletion = nil }
        } message: { Text("Entries shared with other libraries stay there. Favorite entries that would otherwise be orphaned move to My Content.") }
        .task(id: LibraryQuery(source: source, search: search)) { do { try await Task.sleep(for: .milliseconds(250)); try Task.checkCancellation(); await reload() } catch {} }
        .onAppear { Task { try? await state.refreshLibrary() } }
    }
    private var selectedSourceName: String {
        if source == ContentSource() { return String(localized: "All entries") }
        if source.favoritesOnly && !source.myContentOnly && source.topicIDs.isEmpty && source.tag.isEmpty { return String(localized: "Favorites") }
        if source.myContentOnly && !source.favoritesOnly && source.topicIDs.isEmpty && source.tag.isEmpty { return String(localized: "My Content") }
        if source.topicIDs.count == 1, let topic = state.topics.first(where: { $0.id == source.topicIDs[0] }) { return topic.name }
        if !source.tag.isEmpty { return source.tag }
        return String(localized: "Custom selection")
    }
    private func sourceRow(_ title: LocalizedStringKey, symbol: String, value: ContentSource) -> some View {
        Button { source = value } label: { HStack { Label(title, systemImage: symbol); Spacer(); if source == value { Image(systemName: "checkmark") } } }.foregroundStyle(.primary)
    }
    private func reload() async { entries = []; hasMore = true; await loadMore() }
    private func loadMore() async {
        loading = true; defer { loading = false }
        do { let page = try await state.store.page(source: source, search: search, offset: entries.count); if Task.isCancelled { return }; entries += page; hasMore = page.count == 50 }
        catch { if !Task.isCancelled { state.error = error.localizedDescription } }
    }
    private var visibleTopics: [TopicValue] { state.topics.filter { $0.parentTopicID == nil } }
    @ViewBuilder private func topicRow(_ topic: TopicValue) -> some View {
        HStack {
            Button { source = ContentSource(topicIDs: [topic.id]); Task { await reload() } } label: {
                Label { HStack { Text(topic.name); Spacer(); if topic.isPaused { Text("Paused").font(.caption).foregroundStyle(.orange) }; Text(topic.count.formatted()).foregroundStyle(.secondary) } } icon: { Image(systemName: topic.kind == "collection" ? "folder" : (topic.isPaused ? "pause.circle" : "doc.text")) }
            }.foregroundStyle(.primary)
            if source.topicIDs.contains(topic.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
        }
        .contextMenu {
            Button("Read this topic") { Task { await state.changeFeedSource(ContentSource(topicIDs: [topic.id])); dismiss() } }
            if topic.kind == "import" {
                Button(topic.isPaused ? "Reactivate library" : "Pause library") { Task { await state.setLibraryPaused(id: topic.id, paused: !topic.isPaused) } }
                Button("Rename library") { renamedTopic = topic.name; topicForRename = topic }
                Button("Library details") { topicForDetails = topic }
                Button("Delete library", role: .destructive) { topicForDeletion = topic }
            }
        }
    }
    private func sectionRow(_ section: TopicValue) -> some View {
        Button { source = ContentSource(topicIDs: [section.id]); Task { await reload() } } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary)
                Label { HStack { Text(section.name); Spacer(); Text(section.count.formatted()).foregroundStyle(.secondary) } } icon: { Image(systemName: "text.book.closed") }
                if source.topicIDs.contains(section.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }.padding(.leading, 22)
        }.foregroundStyle(.primary).accessibilityLabel("Section: \(section.name), \(section.count) entries")
    }
}

struct LibraryDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    let topic: TopicValue
    var body: some View {
        NavigationStack {
            List {
                Section("Library") {
                    LabeledContent("Name", value: topic.name)
                    LabeledContent("Status", value: topic.isPaused ? "Paused" : "Active")
                    LabeledContent("Entries", value: topic.count.formatted())
                    if let filename = topic.originalFilename, !filename.isEmpty { LabeledContent("Original file", value: filename) }
                    if let format = topic.format, !format.isEmpty { LabeledContent("Format", value: format) }
                    if topic.warningCount > 0 { LabeledContent("Import warnings", value: topic.warningCount.formatted()) }
                    if !topic.sourceManifest.isEmpty { LabeledContent("Sources", value: topic.sourceManifest.count.formatted()) }
                }
                if !topic.sourceManifest.isEmpty {
                    Section("Import sources") {
                        ForEach(topic.sourceManifest) { source in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(source.filename)
                                Text("\(source.format) · \(source.importedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                                if source.warningCount > 0 { Text("\(source.warningCount) warnings").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                Section("Dates") { LabeledContent("Created", value: topic.createdAt.formatted(date: .abbreviated, time: .shortened)); LabeledContent("Updated", value: topic.updatedAt.formatted(date: .abbreviated, time: .shortened)) }
            }
            .navigationTitle("Library details")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
struct EntryRow: View {
    let entry: EntryValue
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) { Text(entry.draft.text).lineLimit(3); if entry.favorite { Image(systemName: "heart.fill").font(.caption).accessibilityLabel("Favorite") } }
            if !entry.draft.author.isEmpty { Text(entry.draft.author).font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}
struct SourcePicker: View {
    @Environment(AppState.self) private var state
    @Binding var source: ContentSource
    @State private var customMode = false
    var body: some View {
        Form {
            Section("Source") {
                Picker("Read from", selection: Binding(get: { customMode }, set: { custom in customMode = custom; if !custom { source = ContentSource() } })) { Text("All entries").tag(false); Text("Custom").tag(true) }.pickerStyle(.segmented)
            }
            if customMode {
                Section("Custom filters") { Toggle("Favorites only", isOn: $source.favoritesOnly); Toggle("My Content", isOn: $source.myContentOnly) }
                Section("Topics and collections") {
                ForEach(state.topics.filter { !$0.isPaused }) { topic in
                    Toggle(topic.name, isOn: Binding(get: { source.topicIDs.contains(topic.id) }, set: { selected in if selected { source.topicIDs.append(topic.id) } else { source.topicIDs.removeAll { $0 == topic.id } } }))
                }
                }
                Section { TextField("Tag or section (optional)", text: $source.tag).autocorrectionDisabled() } footer: { Text("Custom filters are combined. Sources for feed, reminders, widgets, Watch, and wallpaper stay independent.") }
            }
        }.navigationTitle("Type of Content").onAppear { customMode = isCustom }
    }
    private var isCustom: Bool { source.favoritesOnly || source.myContentOnly || !source.topicIDs.isEmpty || !source.tag.isEmpty }
}
struct EntryEditor: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    var existing: EntryValue? = nil
    @State private var text = ""
    @State private var author = ""
    @State private var source = ""
    @State private var tags = ""
    @State private var saving = false
    var body: some View {
        Form {
            Section("Your words") { TextEditor(text: $text).autocorrectionDisabled().frame(minHeight: 180).accessibilityLabel("Entry text").accessibilityIdentifier("editor.text"); Text("\(text.count) / 20,000").font(.caption).foregroundStyle(.secondary) }
            Section("Details") { TextField("Author (optional)", text: $author); TextField("Source (optional)", text: $source); TextField("Tags, separated by commas", text: $tags) }
        }.navigationTitle(existing == nil ? "Write a thought" : "Edit thought")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 20_000 || author.count > 2_000 || source.count > 2_000 || tags.split(separator: ",").count > 64 || tags.split(separator: ",").contains(where: { $0.count > 256 }) || saving).accessibilityIdentifier("editor.save") }
            }
            .task { if let entry = existing { text = entry.draft.text; author = entry.draft.author; source = entry.draft.source; tags = entry.draft.tags.joined(separator: ", ") } }
    }
    private func save() async {
        saving = true; defer { saving = false }
        do {
            let entry = try await state.store.addOwn(EntryDraft(text: text, author: author, source: source, tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }), replacing: existing?.id)
            await state.contentChanged(); await state.open(entry.id); dismiss()
        } catch { state.error = error.localizedDescription }
    }
}
struct CollectionPicker: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let entry: EntryValue
    @State private var name = ""
    var body: some View {
        Form {
            Section { TextField("New collection name", text: $name); Button("Create and add") { Task { do { let topic = try await state.store.createTopic(name: name); try await state.store.addToCollection(entryID: entry.id, topicID: topic.id); await state.contentChanged(); dismiss() } catch { state.error = error.localizedDescription } } }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
            Section("Your collections") { ForEach(state.topics.filter { $0.kind == "collection" }) { topic in Button(topic.name) { Task { do { try await state.store.addToCollection(entryID: entry.id, topicID: topic.id); await state.contentChanged(); dismiss() } catch { state.error = error.localizedDescription } } } } }
        }
        .navigationTitle("Add to collection").toolbar { Button("Done") { dismiss() } }
    }
}
