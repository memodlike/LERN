import SwiftUI
import UniformTypeIdentifiers
import LERNCore
import ImageIO

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
            guard data.count <= 500_000_000, let text = String(data: data, encoding: .utf8) else { throw ImportFailure.tooLarge }
            var budget = JSONResourceBudget(maxTokens: 8_000_000, maxContainerItems: 1_000_000, maxNestedContainerItems: 1_000_000, maxStringBytes: 28_000_000)
            try budget.validate(text)
            return try JSONDecoder().decode(LibraryBackup.self, from: data).validated()
        }.value } catch { state.error = error.localizedDescription }
    }
    private func restore(merge: Bool) async {
        guard let preview else { return }; busy = true; defer { busy = false }
        var written: [URL] = []
        do {
            var restored = try preview.validated()
            let prepared = try await Task.detached { () throws -> (LibraryBackup, [URL]) in
                var restored = preview
                try FileManager.default.createDirectory(at: SharedStore.photosDirectory, withIntermediateDirectories: true)
                var names: [String: String] = [:], files: [URL] = []
                do {
                    for (name, bytes) in preview.photos {
                        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2048, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary), let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.9) else { throw ImportFailure.malformed("A backup photo is invalid.") }
                        let newName = UUID().uuidString + ".jpg"
                        let url = SharedStore.photosDirectory.appendingPathComponent(newName)
                        try jpeg.write(to: url, options: .atomic); files.append(url); names[name] = newName
                    }
                    for index in restored.themes.indices { if let name = restored.themes[index].photoName { restored.themes[index].photoName = names[name] } }
                    for index in restored.resources.indices { if let name = restored.resources[index].coverName { restored.resources[index].coverName = names[name] } }
                    restored.photos = [:]
                    return (restored, files)
                } catch { for file in files { try? FileManager.default.removeItem(at: file) }; throw error }
            }.value
            restored = prepared.0; written = prepared.1
            try await state.store.restore(restored, merge: merge)
            state.current = nil; state.feedPast = []; state.feedPosition = -1; await state.load(); self.preview = nil; message = String(localized: "Backup restored")
        } catch {
            for file in written { try? FileManager.default.removeItem(at: file) }
            state.error = error.localizedDescription
        }
    }
}
