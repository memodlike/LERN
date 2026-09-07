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
}
