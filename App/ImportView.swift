import SwiftUI
import UniformTypeIdentifiers
import LERNCore

struct ImportView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var picker = false
    @State private var previews: [ImportPreview] = []
    @State private var errors: [String] = []
    @State private var loading = false
    @State private var task: Task<Void, Never>?
    @State private var mode: TextImportMode = .automatic
    @State private var action: ImportAction = .new
    @State private var target = ""
    @State private var mergeFiles = false
    @State private var splitSections = false
    @State private var finished = false
    @State private var summary = ""
    var body: some View {
        Form {
            Section {
                Label("Your files are processed locally", systemImage: "lock.shield")
                Text("Import Markdown, TXT, CSV, TSV, JSON or JSONL. Each file becomes a topic. Up to 100 MB and 100,000 entries per file.").font(.subheadline).foregroundStyle(.secondary)
                Picker("TXT layout", selection: $mode) { Text("Detect automatically").tag(TextImportMode.automatic); Text("One entry per line").tag(TextImportMode.lines); Text("Blank-separated paragraphs").tag(TextImportMode.paragraphs) }.disabled(loading)
                Button("Choose files", systemImage: "folder") { picker = true }.disabled(loading).accessibilityIdentifier("import.choose")
            }
            if loading { Section { ProgressView("Processing on this device"); Button("Cancel import", role: .cancel) { task?.cancel() } } }
            ForEach(Array(previews.enumerated()), id: \.offset) { index, preview in
                Section(preview.name) {
                    LabeledContent("Format", value: preview.format)
                    LabeledContent("Valid entries", value: preview.entries.count.formatted())
                    LabeledContent("Duplicates in file", value: preview.duplicates.formatted())
                    LabeledContent("Malformed", value: preview.malformed.formatted())
                    ForEach(Array(preview.firstFive.enumerated()), id: \.offset) { _, entry in Text(entry.text).lineLimit(4).font(.subheadline) }
                    ForEach(preview.issues, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
            }
            if !previews.isEmpty && !finished {
                Section("Import options") {
                    Toggle("Merge files into one topic", isOn: $mergeFiles)
                    Toggle("Make topics from Markdown sections", isOn: $splitSections)
                    Picker("Action", selection: $action) { Text("Import as new").tag(ImportAction.new); Text("Merge into topic").tag(ImportAction.merge); Text("Replace topic entries").tag(ImportAction.replace) }
                    if action != .new { Picker("Existing topic", selection: $target) { Text("Choose a topic").tag(""); ForEach(state.topics.filter { $0.kind != "collection" }) { Text($0.name).tag($0.id) } } }
                    Text("Exact duplicates already in the library reuse the original entry, keeping favorites and collections.").font(.caption).foregroundStyle(.secondary)
                    Button("Import entries") { commit() }.disabled(loading || (action != .new && target.isEmpty)).accessibilityIdentifier("import.commit")
                }
            }
            if finished { Section { Label(summary, systemImage: "checkmark.circle"); Button("Start reading") { Task { await state.next(); dismiss() } } } }
            if !errors.isEmpty { Section("Needs attention") { ForEach(errors, id: \.self) { Text($0).foregroundStyle(.red) } } }
        }.navigationTitle("Import your words")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { task?.cancel(); dismiss() } } }
            .fileImporter(isPresented: $picker, allowedContentTypes: [.plainText, .commaSeparatedText, .json, .text, .data], allowsMultipleSelection: true) { result in
                switch result { case .success(let urls): read(urls); case .failure(let error): errors = [error.localizedDescription] }
            }
            .onDisappear { task?.cancel() }
    }
    private func read(_ urls: [URL]) {
        task?.cancel(); previews = []; errors = []; finished = false; loading = true
        let selectedMode = mode
        task = Task {
            for url in urls {
                if Task.isCancelled { break }
                let work = Task.detached(priority: .userInitiated) { () throws -> ImportPreview in
                    let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= ImportService.byteLimit else { throw ImportFailure.tooLarge }
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    return try ImportService().preview(data: data, filename: url.lastPathComponent, mode: selectedMode)
                }
                do {
                    let preview = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                    if !Task.isCancelled { previews.append(preview) }
                } catch { if !Task.isCancelled { errors.append("\(url.lastPathComponent): \(error.localizedDescription)") } }
            }
            loading = false
        }
    }
    private func commit() {
        loading = true; errors = []
        task = Task {
            do {
                var inserted = 0, duplicates = 0
                var destination: String? = target.isEmpty ? nil : target
                for (index, preview) in previews.enumerated() {
                    try Task.checkCancellation()
                    let useAction = (mergeFiles || action != .new) && index > 0 ? ImportAction.merge : action
                    let result = try await state.store.importEntries(preview, action: useAction, topicID: destination, splitSections: splitSections)
                    if mergeFiles || action != .new { destination = result.topic.id }
                    inserted += result.inserted; duplicates += result.duplicates
                }
                await state.contentChanged(); finished = true
                summary = String(localized: "Imported \(inserted) entries. Reused \(duplicates) duplicates.")
            } catch { errors.append(error is CancellationError ? String(localized: "Import cancelled. Completed files remain in your library.") : error.localizedDescription) }
            loading = false
        }
    }
}
