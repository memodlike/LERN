import SwiftUI
import LERNCore
import UniformTypeIdentifiers

struct ResourcesView: View {
    @Environment(AppState.self) private var state
    @State private var books: [ResourceBook] = []
    @State private var search = ""
    @State private var editing: ResourceBook?
    @State private var importing = false
    var body: some View {
        List {
            Section { Button("Add a resource", systemImage: "plus") { editing = ResourceBook() }; Button("Import JSON or CSV", systemImage: "square.and.arrow.down") { importing = true } }
            ForEach(books.filter { search.isEmpty || ($0.title + " " + $0.author + " " + $0.note).localizedCaseInsensitiveContains(search) }) { book in
                Button { editing = book } label: { VStack(alignment: .leading, spacing: 5) { HStack { Text(book.title).font(.headline); if book.favorite { Image(systemName: "heart.fill") } }; Text(book.author).foregroundStyle(.secondary); Text(book.note).font(.subheadline).lineLimit(2) } }.foregroundStyle(.primary)
            }.onDelete { books.remove(atOffsets: $0); save() }
        }.navigationTitle("Resources / Books").searchable(text: $search)
            .task { do { books = try await state.store.get("resources", default: []) } catch { state.error = error.localizedDescription } }
            .sheet(item: $editing) { book in NavigationStack { BookEditor(book: book) { value in if let index = books.firstIndex(where: { $0.id == value.id }) { books[index] = value } else { books.append(value) }; save() } } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .commaSeparatedText]) { result in
                if case .success(let url) = result { Task {
                    do {
                        let parsed = try await Task.detached { () throws -> [ResourceBook] in
                            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) < 10_000_000 else { throw ImportFailure.tooLarge }
                            let data = try Data(contentsOf: url)
                            if url.pathExtension.lowercased() == "json" {
                                guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: String]] else { throw ImportFailure.malformed("Expected objects with title, author, note and url.") }
                                return rows.compactMap { row in guard let title = row["title"], !title.isEmpty else { return nil }; var book = ResourceBook(); book.title = title; book.author = row["author"] ?? ""; book.note = row["note"] ?? ""; book.url = row["url"] ?? ""; return book }
                            }
                            guard let text = String(data: data, encoding: .utf8) else { throw ImportFailure.encoding }
                            // The shared parser handles quote escaping; title is the CSV text alias for resources.
                            let converted = text.replacingOccurrences(of: "title", with: "text", options: [.anchored, .caseInsensitive])
                            return try DelimitedImporter().parse(converted, mode: .automatic).entries.map { entry in var book = ResourceBook(); book.title = entry.text; book.author = entry.author; book.note = entry.source; return book }
                        }.value
                        books += parsed; save()
                    } catch { state.error = error.localizedDescription }
                } }
            }
    }
    private func save() { Task { do { try await state.store.put("resources", books) } catch { state.error = error.localizedDescription } } }
}
struct BookEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var book: ResourceBook
    var save: (ResourceBook) -> Void
    var body: some View {
        Form {
            TextField("Title", text: $book.title); TextField("Author", text: $book.author)
            TextField("Note", text: $book.note, axis: .vertical).lineLimit(3...10)
            TextField("URL (optional)", text: $book.url).textInputAutocapitalization(.never).keyboardType(.URL)
            Toggle("Favorite", isOn: $book.favorite)
            if let url = URL(string: book.url), ["https", "http"].contains(url.scheme?.lowercased() ?? "") { Link("Open resource website", destination: url) }
        }.navigationTitle("Resource").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save(book); dismiss() }.disabled(book.title.trimmingCharacters(in: .whitespaces).isEmpty) } }
    }
}
