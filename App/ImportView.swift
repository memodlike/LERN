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
    @State private var delimiter: CSVDelimiter = .automatic
    @State private var headerMode: CSVHeaderMode = .automatic
    @State private var action: ImportAction = .new
    @State private var target = ""
    @State private var mergeFiles = false
    @State private var splitSections = false
    @State private var finished = false
    @State private var summary = ""
    @State private var showHelp = false
    @State private var showAIHelper = false
    @State private var selectedURLs: [URL] = []
    @State private var previewByURL: [URL: ImportPreview] = [:]
    @State private var errorsByURL: [URL: String] = [:]
    @State private var generation = UUID()
    var body: some View {
        Form {
            Section {
                Label("Your files are processed locally", systemImage: "lock.shield")
                Text("TXT · Markdown · CSV · TSV · JSON · JSONL").font(.subheadline).foregroundStyle(.secondary)
                Button("Choose files", systemImage: "folder") { picker = true }.disabled(loading).accessibilityIdentifier("import.choose")
                Button("Build with AI", systemImage: "sparkles") { showAIHelper = true }
                Button("Format help", systemImage: "questionmark.circle") { showHelp = true }
            }
            if loading { Section { ProgressView("Processing on this device"); Button("Cancel import", role: .cancel) { task?.cancel() } } }
            ForEach(Array(previews.enumerated()), id: \.offset) { index, preview in
                Section(preview.name) {
                    LabeledContent("Format", value: preview.format)
                    LabeledContent("Valid entries", value: preview.entries.count.formatted())
                    LabeledContent("Duplicates in file", value: preview.duplicates.formatted())
                    LabeledContent("Malformed", value: preview.malformed.formatted())
                    if let layout = preview.detectedLayout { LabeledContent("Detected TXT layout", value: layout == .paragraphs ? "Paragraphs" : "Lines") }
                    if let delimiter = preview.detectedDelimiter { LabeledContent("Detected delimiter", value: delimiter.label) }
                    if let header = preview.detectedHeader { LabeledContent("Detected header", value: header.label) }
                    if preview.sectionCount > 0 { LabeledContent("Sections", value: preview.sectionCount.formatted()) }
                    if preview.shortenedInNotifications > 0 { Label("\(preview.shortenedInNotifications) entries will be shortened in notifications.", systemImage: "bell.badge").font(.caption).foregroundStyle(.secondary) }
                    ForEach(Array(preview.firstFive.enumerated()), id: \.offset) { _, entry in Text(entry.text).lineLimit(4).font(.subheadline) }
                    ForEach(preview.issues, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
            }
            if !previews.isEmpty && !finished {
                Section("Import options") {
                    Picker("Action", selection: $action) { Text("Import as new").tag(ImportAction.new); Text("Merge into topic").tag(ImportAction.merge); Text("Replace topic entries").tag(ImportAction.replace) }
                    if action != .new { Picker("Existing topic", selection: $target) { Text("Choose a topic").tag(""); ForEach(state.topics.filter { $0.parentTopicID == nil && $0.kind != "collection" }) { Text($0.name).tag($0.id) } } }
                    DisclosureGroup("Advanced import options") {
                        if hasFormat("txt") { Picker("TXT layout", selection: $mode) { Text("Detect automatically").tag(TextImportMode.automatic); Text("One entry per line").tag(TextImportMode.lines); Text("Blank-separated paragraphs").tag(TextImportMode.paragraphs) }.disabled(loading) }
                        Toggle("Merge files into one topic", isOn: $mergeFiles)
                        if previews.contains(where: { $0.sectionCount > 0 }) { Toggle("Create topics from sections/categories", isOn: $splitSections) }
                        if hasFormat("csv") { Picker("CSV delimiter", selection: $delimiter) { ForEach(CSVDelimiter.allCases, id: \.self) { Text($0.label).tag($0) } } }
                        if hasFormat("csv") || hasFormat("tsv") { Picker("CSV/TSV header", selection: $headerMode) { Text("Detect automatically").tag(CSVHeaderMode.automatic); Text("Header row present").tag(CSVHeaderMode.present); Text("No header row").tag(CSVHeaderMode.absent) } }
                    }
                    Text("Matching entries use normalized text, author and source. Case, spacing, tags and sections do not create a new entry.").font(.caption).foregroundStyle(.secondary)
                    Button("Import entries") { commit() }.disabled(loading || (action != .new && target.isEmpty)).accessibilityIdentifier("import.commit")
                }
            }
            if finished { Section { Label(summary, systemImage: "checkmark.circle"); Button("Start reading") { Task { await state.next(); dismiss() } } } }
            if !errors.isEmpty { Section("Needs attention") { ForEach(errors, id: \.self) { Text($0).foregroundStyle(.red) } } }
        }.navigationTitle("Import your words")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { task?.cancel(); dismiss() } } }
            .fileImporter(isPresented: $picker, allowedContentTypes: supportedTypes, allowsMultipleSelection: true) { result in
                switch result { case .success(let urls): read(urls); case .failure(let error): errors = [error.localizedDescription] }
            }
            .sheet(isPresented: $showHelp) { ImportFormatHelpView() }
            .sheet(isPresented: $showAIHelper) { ImportAIHelperView() }
            .onChange(of: delimiter) { _, _ in reparse(formats: ["csv"]) }
            .onChange(of: headerMode) { _, _ in reparse(formats: ["csv", "tsv"]) }
            .onChange(of: mode) { _, _ in reparse(formats: ["txt"]) }
            .onDisappear { task?.cancel() }
    }
    private func hasFormat(_ format: String) -> Bool {
        selectedURLs.contains { $0.pathExtension.lowercased() == format }
    }
    private func reparse(formats: Set<String>) {
        guard !selectedURLs.isEmpty else { return }
        read(selectedURLs, formats: formats)
    }
    private func read(_ urls: [URL], formats: Set<String>? = nil) {
        task?.cancel(); selectedURLs = urls; errors = []; finished = false; loading = true
        let current = UUID(); generation = current
        if formats == nil { previewByURL = [:]; errorsByURL = [:]; previews = [] }
        let selectedMode = mode
        let selectedDelimiter = delimiter
        let selectedHeaderMode = headerMode
        task = Task {
            var nextPreviews = previewByURL
            var nextErrors = errorsByURL
            for url in urls where formats == nil || formats!.contains(url.pathExtension.lowercased()) {
                if Task.isCancelled { break }
                let work = Task.detached(priority: .userInitiated) { () throws -> ImportPreview in
                    let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= ImportService.byteLimit else { throw ImportFailure.tooLarge }
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    return try ImportService().preview(data: data, filename: url.lastPathComponent, mode: selectedMode, delimiter: selectedDelimiter, headerMode: selectedHeaderMode)
                }
                do {
                    let preview = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                    guard !Task.isCancelled, generation == current else { return }
                    nextPreviews[url] = preview; nextErrors[url] = nil
                } catch {
                    guard !Task.isCancelled, generation == current else { return }
                    nextPreviews[url] = nil; nextErrors[url] = "\(url.lastPathComponent): \(error.localizedDescription)"
                }
            }
            guard !Task.isCancelled, generation == current else { return }
            previewByURL = nextPreviews; errorsByURL = nextErrors
            previews = urls.compactMap { nextPreviews[$0] }
            errors = urls.compactMap { nextErrors[$0] }
            loading = false
        }
    }
    private func commit() {
        loading = true; errors = []
        task = Task {
            var progress = MultiFileImportProgress()
            var currentFilename = ""
            do {
                var destination: String? = target.isEmpty ? nil : target
                for (index, preview) in previews.enumerated() {
                    try Task.checkCancellation()
                    currentFilename = preview.filename.isEmpty ? preview.name : preview.filename
                    let useAction = (mergeFiles || action != .new) && index > 0 ? ImportAction.merge : action
                    let result = try await state.store.importEntries(preview, action: useAction, topicID: destination, splitSections: splitSections)
                    if mergeFiles || action != .new { destination = result.topic.id }
                    progress.record(result)
                }
                await state.contentChanged(); finished = true
                summary = String(localized: "Imported \(progress.insertedEntries) entries. Reused \(progress.reusedDuplicates) duplicates.")
            } catch {
                if error is CancellationError {
                    errors.append(String(localized: "Import cancelled. Completed files remain in your library."))
                } else if progress.completedFiles > 0 {
                    errors.append(String(localized: "Imported \(progress.completedFiles) completed files with \(progress.insertedEntries) entries. Reused \(progress.reusedDuplicates) duplicates. \(currentFilename) could not be imported. Completed files were preserved."))
                } else {
                    errors.append(error.localizedDescription)
                }
            }
            loading = false
        }
    }
    private var supportedTypes: [UTType] {
        ["txt", "md", "markdown", "csv", "tsv", "json", "jsonl"].compactMap { UTType(filenameExtension: $0) }
    }
}
