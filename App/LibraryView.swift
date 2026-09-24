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
                    ActiveFeedSourceBanner()
                }
                Section {
                    NavigationLink { ImportView() } label: { Label("Import files", systemImage: "square.and.arrow.down") }
                    NavigationLink { EntryEditor() } label: { Label("Write a thought", systemImage: "square.and.pencil") }
                }
                Section("Feed source") {
                    Text("Search finds entries below. Choose a source here, or tap Read to immediately switch what the Feed plays.").font(.caption).foregroundStyle(.secondary)
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
                        .swipeActions(edge: .leading) {
                            Button {
                                Task { await state.flag(entry, "favorite", !entry.favorite); await reload() }
                            } label: {
                                Label(entry.favorite ? "Unfavorite" : "Favorite", systemImage: entry.favorite ? "heart.slash" : "heart.fill")
                            }
                            .tint(.pink)
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                state.sheet = .share
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .tint(.blue)

                            Button {
                                state.sheet = .collections
                            } label: {
                                Label("Collection", systemImage: "folder.badge.plus")
                            }
                            .tint(.indigo)
                        }
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
        let isFeedActive = state.preferences.feedSource == value
        let isSelected = source == value

        return HStack(spacing: 12) {
            Button {
                source = value
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 18))
                        .foregroundStyle(isFeedActive ? Color.green : Color.accentColor)
                        .frame(width: 24)

                    Text(title)
                        .font(.body.weight(isSelected ? .semibold : .regular))

                    if isFeedActive {
                        Text("Active")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green, in: Capsule())
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)

            if !isFeedActive {
                Button {
                    Task {
                        await state.changeFeedSource(value)
                        dismiss()
                    }
                } label: {
                    Text("Read")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.tint.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Read this source in feed"))
            }
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
    private func reload() async { entries = []; hasMore = true; await loadMore() }
    private func loadMore() async {
        loading = true; defer { loading = false }
        do { let page = try await state.store.page(source: source, search: search, offset: entries.count); if Task.isCancelled { return }; entries += page; hasMore = page.count == 50 }
        catch { if !Task.isCancelled { state.error = error.localizedDescription } }
    }
    private var visibleTopics: [TopicValue] { state.topics.filter { $0.parentTopicID == nil } }
    @ViewBuilder private func topicRow(_ topic: TopicValue) -> some View {
        let topicSource = ContentSource(topicIDs: [topic.id])
        let isFeedActive = state.preferences.feedSource == topicSource
        let isSelected = source.topicIDs.contains(topic.id)

        HStack(spacing: 12) {
            Button {
                source = topicSource
                Task { await reload() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: topic.kind == "collection" ? "folder.fill" : (topic.isPaused ? "pause.circle.fill" : "doc.text.fill"))
                        .font(.system(size: 18))
                        .foregroundStyle(topic.isPaused ? Color(hex: "8A4500") : (isFeedActive ? Color.green : Color.accentColor))
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(topic.name)
                                .font(.body.weight(isSelected ? .semibold : .regular))

                            if isFeedActive {
                                Text("Active")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green, in: Capsule())
                            }
                        }

                        if topic.isPaused {
                            Text("Paused")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color(hex: "8A4500"))
                        }
                    }

                    Spacer()

                    Text(topic.count.formatted())
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)

            if !isFeedActive {
                Button {
                    Task {
                        await state.changeFeedSource(topicSource)
                        dismiss()
                    }
                } label: {
                    Text("Read")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.tint.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Read \(topic.name) in feed")
            }
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .contextMenu {
            Button("Read this topic") { Task { await state.changeFeedSource(topicSource); dismiss() } }
            if topic.kind == "import" {
                Button(topic.isPaused ? "Reactivate library" : "Pause library") { Task { await state.setLibraryPaused(id: topic.id, paused: !topic.isPaused) } }
                Button("Rename library") { renamedTopic = topic.name; topicForRename = topic }
                Button("Library details") { topicForDetails = topic }
                Button("Delete library", role: .destructive) { topicForDeletion = topic }
            }
        }
    }
    private func sectionRow(_ section: TopicValue) -> some View {
        let sectionSource = ContentSource(topicIDs: [section.id])
        let isSelected = source.topicIDs.contains(section.id)

        return Button { source = sectionSource; Task { await reload() } } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary)
                Label { HStack { Text(section.name); Spacer(); Text(section.count.formatted()).foregroundStyle(.secondary) } } icon: { Image(systemName: "text.book.closed") }
                if isSelected { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }.padding(.leading, 22)
        }
        .foregroundStyle(.primary)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel("Section: \(section.name), \(section.count) entries")
    }
}

struct ActiveFeedSourceBanner: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("ACTIVE IN FEED", systemImage: "bolt.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.gradient, in: Capsule())

                Spacer()

                Text(selectionModeTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Image(systemName: activeSourceIcon)
                    .font(.title2)
                    .foregroundStyle(Color(hex: state.activeTheme.secondary))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(activeSourceName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("\(state.total) thoughts in rotation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.green.opacity(0.35), lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Active in feed: \(activeSourceName), \(selectionModeTitle), \(state.total) thoughts in rotation")
    }

    private var activeSourceName: String {
        let feedSource = state.preferences.feedSource
        if feedSource.favoritesOnly { return String(localized: "Favorites") }
        if feedSource.myContentOnly { return String(localized: "My Content") }
        if let id = feedSource.topicIDs.first, let topic = state.topics.first(where: { $0.id == id }) {
            return topic.name
        }
        return String(localized: "All entries")
    }

    private var activeSourceIcon: String {
        let feedSource = state.preferences.feedSource
        if feedSource.favoritesOnly { return "heart.fill" }
        if feedSource.myContentOnly { return "pencil.line" }
        return "square.stack.3d.up.fill"
    }

    private var selectionModeTitle: String {
        switch state.preferences.feedMode {
        case .shuffle: return String(localized: "Shuffle")
        case .sequential: return String(localized: "Sequential")
        case .random: return String(localized: "Random")
        }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let entry: EntryValue
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(entry.draft.text)
                    .font(.body)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 8 : 3)
                    .lineSpacing(3)
                Spacer(minLength: 4)
                if entry.favorite {
                    Image(systemName: "heart.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.pink)
                        .accessibilityLabel("Favorite")
                }
            }

            if !entry.draft.author.isEmpty || !entry.draft.source.isEmpty {
                HStack(spacing: 6) {
                    if !entry.draft.author.isEmpty {
                        Text(entry.draft.author)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    if !entry.draft.author.isEmpty && !entry.draft.source.isEmpty {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !entry.draft.source.isEmpty {
                        Text(entry.draft.source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !entry.draft.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(entry.draft.tags.prefix(3), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
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
