import Foundation
import Testing
@testable import LERNCore

struct ResourceBudgetTests {
    @Test func nestedCollectionsRejectedBeforeDecode() {
        let nested = "[{\"text\":\"safe\",\"ignored\":[" + Array(repeating: "0", count: 1_025).joined(separator: ",") + "]}]"
        #expect(throws: (any Error).self) { try JSONImporter().parse(nested, mode: .automatic) }
        #expect(throws: (any Error).self) { try JSONImporter(lines: true).parse(String(nested.dropFirst().dropLast()), mode: .automatic) }
    }

    @Test func tokenBudgetIsCumulativeAcrossDocuments() throws {
        var budget = JSONResourceBudget(maxTokens: 8)
        try budget.validate("{\"text\":\"one\"}")
        try budget.validate("{\"text\":\"two\"}")
        #expect(throws: (any Error).self) { try budget.validate("{\"text\":\"three\"}") }
    }

    @Test func nestedTokensCountTowardTotal() {
        var budget = JSONResourceBudget(maxTokens: 5)
        #expect(throws: (any Error).self) { try budget.validate("[[0,1],[2,3]]") }
    }

    @Test func quotedPunctuationIsNotStructure() throws {
        var budget = JSONResourceBudget(maxTokens: 3, maxContainerItems: 2)
        try budget.validate(#"["[{,:}]", "\"escaped\" and \\ slash"]"#)
    }

    @Test func stringBytesAreBoundedBeforeDecode() {
        var budget = JSONResourceBudget(maxStringBytes: 3)
        #expect(throws: (any Error).self) { try budget.validate("[\"four\"]") }
    }

    @Test func hundredThousandOrdinaryJSONEntriesRemainSupported() throws {
        let text = "[" + Array(repeating: #"{"text":"A thought","author":"Ada","tags":["focus"]}"#, count: 100_000).joined(separator: ",") + "]"
        #expect(try JSONImporter().parse(text, mode: .automatic).entries.count == 100_000)
    }

    @Test func jsonlMetadataFailureIsNotSilentlySkipped() {
        let text = "{\"text\":\"first\"}\n{\"text\":\"second\",\"author\":\"" + String(repeating: "a", count: 2_001) + "\"}"
        #expect(throws: (any Error).self) { try JSONImporter(lines: true).parse(text, mode: .automatic) }
    }

    @Test(arguments: ["author", "source", "category"])
    func metadataLimitsApplyToJSONAndCSV(field: String) throws {
        let long = String(repeating: "a", count: 2_001)
        let json = String(decoding: try JSONSerialization.data(withJSONObject: [["text": "quote", field: long]]), as: UTF8.self)
        #expect(throws: (any Error).self) { try JSONImporter().parse(json, mode: .automatic) }
        #expect(throws: (any Error).self) { try DelimitedImporter().parse("text,\(field)\nquote,\(long)", mode: .automatic) }
    }

    @Test func tagLimitsApplyAcrossFormats() throws {
        for tags in [Array(repeating: "a", count: 65), [String(repeating: "a", count: 257)]] {
            let json = String(decoding: try JSONSerialization.data(withJSONObject: [["text": "quote", "tags": tags]]), as: UTF8.self)
            #expect(throws: (any Error).self) { try JSONImporter().parse(json, mode: .automatic) }
            #expect(throws: (any Error).self) { try DelimitedImporter().parse("text,tags\nquote," + tags.joined(separator: ";"), mode: .automatic) }
            #expect(throws: (any Error).self) { try MarkdownImporter().parse("---\ntags: [" + tags.joined(separator: ",") + "]\n---\nquote", mode: .automatic) }
        }
    }

    @Test func markdownFrontmatterAndSectionLimits() {
        let long = String(repeating: "a", count: 2_001)
        for field in ["author", "source"] {
            #expect(throws: (any Error).self) { try MarkdownImporter().parse("---\n\(field): \(long)\n---\n- one\n- two", mode: .automatic) }
        }
        #expect(throws: (any Error).self) { try MarkdownImporter().parse("# " + long + "\nquote", mode: .automatic) }
    }

    @Test func markdownParagraphLimitAppliesBeforeJoining() {
        let text = Array(repeating: "a", count: 10_001).joined(separator: "\n")
        #expect(throws: (any Error).self) { try MarkdownImporter().parse(text, mode: .automatic) }
    }

    @Test func inheritedMarkdownMetadataHasAggregateBudget() {
        let text = "---\nauthor: " + String(repeating: "a", count: 2_000) + "\n---\n" + String(repeating: "- quote\n", count: 53_000)
        #expect(throws: (any Error).self) { try MarkdownImporter().parse(text, mode: .automatic) }
    }

    @Test func metadataBoundaryAndResourceAliases() throws {
        let author = String(repeating: "a", count: 2_000)
        let tags = Array(repeating: String(repeating: "t", count: 256), count: 64)
        let json = String(decoding: try JSONSerialization.data(withJSONObject: [["text": "quote", "author": author, "tags": tags]]), as: UTF8.self)
        #expect(try JSONImporter().parse(json, mode: .automatic).entries.first?.tags.count == 64)
        let csv = "\u{FEFF} Title , Author , Note , URL\n\"A, book\",Ada,\"A \"\"note\"\"\",https://example.com"
        let entry = try DelimitedImporter(headerAliases: ["title": "text", "note": "source", "url": "category"]).parse(csv, mode: .automatic).entries.first
        #expect(entry?.text == "A, book")
        #expect(entry?.source == "A \"note\"")
        #expect(entry?.section == "https://example.com")
    }
}
