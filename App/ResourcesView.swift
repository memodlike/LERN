import SwiftUI
import LERNCore
import UniformTypeIdentifiers
import PhotosUI
import ImageIO

struct ResourcesView: View {
    @Environment(AppState.self) private var state
    @State private var books: [ResourceBook] = []
    @State private var search = ""
    @State private var editing: ResourceBook?
    @State private var importing = false
    @State private var importPreview: ResourceImportPreview?
    @State private var importLoading = false
    private var filtered: [ResourceBook] { books.filter { search.isEmpty || ($0.title + " " + $0.author + " " + $0.note).localizedCaseInsensitiveContains(search) } }
    var body: some View {
        List {
            Section { Button("Add a resource", systemImage: "plus") { editing = ResourceBook() }; Button("Import JSON or CSV", systemImage: "square.and.arrow.down") { importing = true } }
            if importLoading { Section { ProgressView("Preparing import preview") } }
            if let importPreview {
                Section("Import preview") {
                    LabeledContent("File", value: importPreview.filename)
                    LabeledContent("Format", value: importPreview.format)
                    LabeledContent("Valid resources", value: importPreview.valid.count.formatted())
                    LabeledContent("Duplicates", value: importPreview.duplicates.formatted())
                    LabeledContent("Malformed", value: importPreview.malformed.formatted())
                    ForEach(importPreview.firstFive) { book in Text(book.title).font(.subheadline) }
                    ForEach(importPreview.issues, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    Button("Import resources") {
                        guard books.count + importPreview.valid.count <= DataLimits.resources else { state.error = ImportFailure.resourceCountExceeded.localizedDescription; return }
                        books += importPreview.valid; save(); self.importPreview = nil
                    }.accessibilityIdentifier("resources.import.commit")
                    Button("Discard preview", role: .cancel) { self.importPreview = nil }
                }
            }
            ForEach(filtered) { book in
                Button { editing = book } label: { HStack(alignment: .top) { if let name = book.coverName, let url = SharedStore.photoURL(name), let cover = UIImage(contentsOfFile: url.path) { Image(uiImage: cover).resizable().scaledToFill().frame(width: 48, height: 66).clipped().accessibilityHidden(true) }; VStack(alignment: .leading, spacing: 5) { HStack { Text(book.title).font(.headline); if book.favorite { Image(systemName: "heart.fill") } }; Text(book.author).foregroundStyle(.secondary); Text(book.note).font(.subheadline).lineLimit(2) } } }.foregroundStyle(.primary)
            }.onDelete { offsets in let ids = Set(offsets.map { filtered[$0].id }); books.removeAll { ids.contains($0.id) }; save() }
        }.navigationTitle("Resources / Books").searchable(text: $search)
            .task { do { books = try await state.store.get("resources", default: []) } catch { state.error = error.localizedDescription } }
            .sheet(item: $editing) { book in NavigationStack { BookEditor(book: book) { value in if let index = books.firstIndex(where: { $0.id == value.id }) { books[index] = value } else { books.append(value) }; save() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: ["csv", "json"].compactMap { UTType(filenameExtension: $0) }) { result in
                if case .success(let url) = result { Task {
                    importLoading = true
                    do {
                        let existing = books
                        let parsed = try await Task.detached { () throws -> ResourceImportPreview in
                            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= DataLimits.resourceImportBytes else { throw ImportFailure.resourceTooLarge }
                            return try ResourceImporter.preview(data: Data(contentsOf: url), filename: url.lastPathComponent, existing: existing)
                        }.value
                        importPreview = parsed
                    } catch { state.error = error.localizedDescription }
                    importLoading = false
                } }
            }
    }
    private func save() { Task { do { try await state.store.put("resources", books) } catch { state.error = error.localizedDescription } } }
}
struct BookEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var book: ResourceBook
    @State private var photo: PhotosPickerItem?
    @State private var photoBusy = false
    @State private var error: String?
    var save: (ResourceBook) -> Void
    var body: some View {
        Form {
            TextField("Title", text: $book.title); TextField("Author", text: $book.author)
            TextField("Note", text: $book.note, axis: .vertical).lineLimit(3...10)
            TextField("URL (optional)", text: $book.url).textInputAutocapitalization(.never).keyboardType(.URL)
            Toggle("Favorite", isOn: $book.favorite)
            Section {
                if let name = book.coverName, let url = SharedStore.photoURL(name), let image = UIImage(contentsOfFile: url.path) { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 200) }
                PhotosPicker(selection: $photo, matching: .images) { Label("Choose cover photo", systemImage: "photo") }
                if book.coverName != nil { Button("Remove photo", role: .destructive) { book.coverName = nil } }
                if photoBusy { ProgressView() }
            }
            if let url = URL(string: book.url), ["https", "http"].contains(url.scheme?.lowercased() ?? "") { Link("Open resource website", destination: url) }
        }.navigationTitle("Resource").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save(book); dismiss() }.disabled(book.title.trimmingCharacters(in: .whitespaces).isEmpty || book.title.count > 2_000 || book.author.count > 2_000 || book.note.count > 20_000 || book.url.count > 2_000 || photoBusy) } }
            .task(id: photo) {
                guard let photo else { return }; photoBusy = true; defer { photoBusy = false }
                do {
                    guard let data = try await photo.loadTransferable(type: Data.self), data.count <= 20_000_000 else { throw ImportFailure.tooLarge }
                    book.coverName = try await Task.detached { () throws -> String in
                        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2048, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary), let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.88) else { throw ImportFailure.malformed("Choose a valid photo.") }
                        try FileManager.default.createDirectory(at: SharedStore.photosDirectory, withIntermediateDirectories: true)
                        let name = UUID().uuidString + ".jpg"
                        try jpeg.write(to: SharedStore.photosDirectory.appendingPathComponent(name), options: .atomic); return name
                    }.value
                } catch { self.error = error.localizedDescription }
            }
            .alert("Something needs attention", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }

    }
}
