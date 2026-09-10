import Foundation
import Testing
@testable import LERNCore

struct ResourceImporterTests {
    @Test func formatsPreserveFields() throws {
        let csv = "\u{FEFF}title,author,note,url\r\n\"A, book\",Ada,\"Read \"\"slowly\"\"\",https://example.com\r\n"
        let book = try ResourceImporter.parse(data: Data(csv.utf8), filename: "books.csv")[0]
        #expect(book.title == "A, book"); #expect(book.author == "Ada")
        #expect(book.note == "Read \"slowly\""); #expect(book.url == "https://example.com")
        let json = #"[{"title":"Книга","author":"Автор","note":"Заметка","url":"https://example.com"}]"#
        let value = try ResourceImporter.parse(data: Data(json.utf8), filename: "books.json")[0]
        #expect(value.title == "Книга"); #expect(value.note == "Заметка")
    }
    @Test func rejectsMalformedAndExcessiveMetadata() {
        #expect(throws: (any Error).self) { try ResourceImporter.parse(data: Data(#"[{"note":"missing title"}]"#.utf8), filename: "books.json") }
        let text = "[{\"title\":\"" + String(repeating: "x", count: 2_001) + "\"}]"
        #expect(throws: (any Error).self) { try ResourceImporter.parse(data: Data(text.utf8), filename: "books.json") }
    }
    @Test func previewDeduplicatesResourcesAndPreservesExistingFavorites() throws {
        var favorite = ResourceBook(); favorite.title = "A Book"; favorite.author = "Ada"; favorite.url = "https://example.com"; favorite.favorite = true
        let json = #"[{"title":"a  book","author":"ADA","url":"https://example.com","note":"new"},{"title":"Another","author":"Lin"}]"#
        let preview = try ResourceImporter.preview(data: Data(json.utf8), filename: "books.json", existing: [favorite])
        #expect(preview.duplicates == 1)
        #expect(preview.valid.map(\.title) == ["Another"])
        #expect(favorite.favorite)
    }
    @Test func invalidResourceRowsDoNotReachPreview() throws {
        let json = #"[{"title":"Valid"},{"title":"Bad","Title":"Conflict"}]"#
        let preview = try ResourceImporter.preview(data: Data(json.utf8), filename: "books.json")
        #expect(preview.valid.map(\.title) == ["Valid"])
        #expect(preview.malformed == 1)
    }
    @Test func resourceTooLargeReports10MB() {
        #expect(throws: ImportFailure.self) {
            try ResourceImporter.preview(data: Data(repeating: 0, count: DataLimits.resourceImportBytes + 1), filename: "books.json")
        }
    }
}
