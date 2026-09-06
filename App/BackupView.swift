import SwiftUI
import UniformTypeIdentifiers
import LERNCore

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct BackupView: View {
    @Environment(AppState.self) private var state
    @State private var exporting = false
    @State private var importing = false
    @State private var document = BackupDocument()
    @State private var preview: LibraryBackup?
    @State private var busy = false
    @State private var replaceConfirmation = false
    @State private var message: String?
    var body: some View {
        Form {
            Section {
                Text("Save a complete local copy of your library, themes, photos, favorites, collections and settings. Choose where it goes in Files.")
                Button("Export App Backup", systemImage: "square.and.arrow.up") { Task { await export() } }.disabled(busy)
                Button("Choose backup to restore", systemImage: "square.and.arrow.down") { importing = true }.disabled(busy)
            }
            if busy { ProgressView("Preparing your library") }
            if let preview {
                Section("Backup preview") {
                    LabeledContent("Entries", value: preview.entries.count.formatted()); LabeledContent("Topics", value: preview.topics.count.formatted()); Text(preview.createdAt, format: .dateTime)
                    Button("Merge content into library") { Task { await restore(merge: true) } }.disabled(busy)
                    Text("Merge adds missing content and collections while keeping your current settings.").font(.caption)
                    Button("Replace library and settings", role: .destructive) { replaceConfirmation = true }.disabled(busy)
                }
            }
            if let message { Text(message) }
        }.navigationTitle("Backup / Restore")
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "LERN-backup") { result in if case .failure(let error) = result { state.error = error.localizedDescription } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in if case .success(let url) = result { Task { await read(url) } } else if case .failure(let error) = result { state.error = error.localizedDescription } }
            .confirmationDialog("Replace the entire library and settings with this backup? Export a backup first if you want to keep the current version.", isPresented: $replaceConfirmation) { Button("Replace library", role: .destructive) { Task { await restore(merge: false) } } }
    }
    private func export() async {
        busy = true; defer { busy = false }
        do {
            let photos = try await Task.detached { () throws -> [String: Data] in
                let urls = (try? FileManager.default.contentsOfDirectory(at: SharedStore.photosDirectory, includingPropertiesForKeys: nil)) ?? []
                var output: [String: Data] = [:]
                for url in urls where LibraryBackup.safeAssetName(url.lastPathComponent) { output[url.lastPathComponent] = try Data(contentsOf: url) }
                return output
            }.value
            let backup = try await state.store.backup(photos: photos)
            document = BackupDocument(data: try await Task.detached { try JSONEncoder().encode(backup) }.value); exporting = true
        } catch { state.error = error.localizedDescription }
    }
    private func read(_ url: URL) async {
        busy = true; defer { busy = false }
        do { preview = try await Task.detached { () throws -> LibraryBackup in
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 500_000_000 else { throw ImportFailure.tooLarge }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            return try JSONDecoder().decode(LibraryBackup.self, from: data).validated()
        }.value } catch { state.error = error.localizedDescription }
    }
    private func restore(merge: Bool) async {
        guard let preview else { return }; busy = true; defer { busy = false }
        do {
            // Validate and stage all photos before committing database changes.
            try await Task.detached {
                try FileManager.default.createDirectory(at: SharedStore.photosDirectory, withIntermediateDirectories: true)
                for (name, bytes) in preview.photos { guard let url = SharedStore.photoURL(name) else { throw ImportFailure.malformed("Invalid photo name.") }; if merge && FileManager.default.fileExists(atPath: url.path) { continue }; try bytes.write(to: url, options: .atomic) }
            }.value
            try await state.store.restore(preview, merge: merge)
            state.current = nil; state.feedPast = []; state.feedPosition = -1; await state.load(); self.preview = nil; message = String(localized: "Backup restored")
        } catch { state.error = error.localizedDescription }
    }
}
