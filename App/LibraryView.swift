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
    var body: some View {
        List {
            if search.isEmpty {
                Section {
                    NavigationLink { ImportView() } label: { Label("Import files", systemImage: "square.and.arrow.down") }
                    NavigationLink { EntryEditor() } label: { Label("Write a thought", systemImage: "square.and.pencil") }
                }
                Section("Read from") {
                    sourceRow("All entries", symbol: "square.stack", value: ContentSource())
                    sourceRow("Favorites", symbol: "heart", value: ContentSource(favoritesOnly: true))
                    sourceRow("My Content", symbol: "pencil.line", value: ContentSource(myContentOnly: true))
                    ForEach(state.topics) { topic in
                        HStack {
                            Button { source = ContentSource(topicIDs: [topic.id]); Task { await reload() } } label: {
                                Label { HStack { Text(topic.name); Spacer(); Text(topic.count.formatted()).foregroundStyle(.secondary) } } icon: { Image(systemName: topic.kind == "collection" ? "folder" : "doc.text") }
                            }.foregroundStyle(.primary)
                            if source.topicIDs.contains(topic.id) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                        .contextMenu {
                            Button("Read this topic") { Task { await state.changeFeedSource(ContentSource(topicIDs: [topic.id])); dismiss() } }
                        }
                    }
                    NavigationLink { SourcePicker(source: Binding(get: { source }, set: { source = $0 })) } label: { Label("Mix topics or choose a tag", systemImage: "line.3.horizontal.decrease") }
                }
                Section {
                    Button("Read selected source") { Task { await state.changeFeedSource(source); dismiss() } }.accessibilityIdentifier("library.read")
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
        .task(id: LibraryQuery(source: source, search: search)) { do { try await Task.sleep(for: .milliseconds(250)); try Task.checkCancellation(); await reload() } catch {} }
        .onAppear { Task { try? await state.refreshLibrary() } }
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
    var body: some View {
        Form {
            Section { Button("All entries") { source = ContentSource() }; Toggle("Favorites only", isOn: $source.favoritesOnly); Toggle("My Content", isOn: $source.myContentOnly) }
            Section("Topics and collections") {
                ForEach(state.topics) { topic in
                    Toggle(topic.name, isOn: Binding(get: { source.topicIDs.contains(topic.id) }, set: { selected in if selected { source.topicIDs.append(topic.id) } else { source.topicIDs.removeAll { $0 == topic.id } } }))
                }
            }
            Section { TextField("Tag or section (optional)", text: $source.tag).autocorrectionDisabled() } footer: { Text("This source applies only to the screen you are editing. Other sources stay independent.") }
        }.navigationTitle("Type of Content")
    }
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
