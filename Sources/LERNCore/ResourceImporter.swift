import Foundation

public enum ResourceImporter {
    public static func parse(data: Data, filename: String) throws -> [ResourceBook] {
        guard data.count <= 10_000_000 else { throw ImportFailure.tooLarge }
        guard var text = String(data: data, encoding: .utf8) else { throw ImportFailure.encoding }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let books: [ResourceBook]
        if (filename as NSString).pathExtension.lowercased() == "json" {
            var budget = JSONResourceBudget(maxTokens: 150_000, maxContainerItems: 10_000, maxNestedContainerItems: 16, maxStringBytes: 120_000)
            try budget.validate(text)
            guard let rows = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: String]] else { throw ImportFailure.malformed("Expected objects with title, author, note and url.") }
            books = rows.map { row in
                var book = ResourceBook(); book.title = row["title"] ?? ""; book.author = row["author"] ?? ""
                book.note = row["note"] ?? ""; book.url = row["url"] ?? ""; return book
            }
        } else {
            books = try DelimitedImporter(headerAliases: ["title": "text", "note": "source", "url": "category"]).parse(text, mode: .automatic).entries.map { entry in
                var book = ResourceBook(); book.title = entry.text; book.author = entry.author
                book.note = entry.source; book.url = entry.section; return book
            }
        }
        guard !books.isEmpty, books.count <= 10_000 else { throw ImportFailure.tooLarge }
        for book in books {
            guard !book.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  book.title.count <= 2_000, book.author.count <= 2_000, book.note.count <= 20_000, book.url.count <= 2_000 else {
                throw ImportFailure.malformed("A resource has a missing title or an oversized field.")
            }
        }
        return books
    }
}
