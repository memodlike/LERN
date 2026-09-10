import Foundation

public struct ResourceImportPreview: Sendable {
    public var filename: String
    public var format: String
    public var valid: [ResourceBook]
    public var duplicates: Int
    public var malformed: Int
    public var issues: [String]
    public init(filename: String, format: String, valid: [ResourceBook], duplicates: Int, malformed: Int, issues: [String]) {
        self.filename = filename; self.format = format; self.valid = valid; self.duplicates = duplicates; self.malformed = malformed; self.issues = issues
    }
    public var firstFive: [ResourceBook] { Array(valid.prefix(5)) }
}

public enum ResourceImporter {
    public static func parse(data: Data, filename: String) throws -> [ResourceBook] {
        try preview(data: data, filename: filename).valid
    }

    public static func preview(data: Data, filename: String, existing: [ResourceBook] = []) throws -> ResourceImportPreview {
        guard data.count <= DataLimits.resourceImportBytes else { throw ImportFailure.resourceTooLarge }
        guard var text = String(data: data, encoding: .utf8) else { throw ImportFailure.encoding }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let ext = (filename as NSString).pathExtension.lowercased()
        var candidates: [ResourceBook] = [], issues: [String] = []
        if ext == "json" {
            var budget = JSONResourceBudget(maxTokens: 150_000, maxContainerItems: DataLimits.resources, maxNestedContainerItems: 16, maxStringBytes: 120_000)
            try budget.validate(text)
            let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
            guard let rows = object as? [Any] else { throw ImportFailure.malformed("Expected a JSON array of resources.") }
            guard rows.count <= DataLimits.resources else { throw ImportFailure.resourceCountExceeded }
            for (index, row) in rows.enumerated() {
                guard let fields = row as? [String: Any] else { issues.append("Resource \(index + 1): expected an object."); continue }
                var values: [String: String] = [:]
                var invalid = false
                for (key, value) in fields {
                    let canonical = key.lowercased()
                    guard ["title", "author", "note", "url"].contains(canonical) else { continue }
                    guard values[canonical] == nil, let text = value as? String else {
                        issues.append("Resource \(index + 1): invalid or duplicate \(canonical)."); invalid = true; break
                    }
                    values[canonical] = text
                }
                guard !invalid else { continue }
                var book = ResourceBook(); book.title = values["title"] ?? ""; book.author = values["author"] ?? ""
                book.note = values["note"] ?? ""; book.url = values["url"] ?? ""
                if let issue = validationIssue(for: book) { issues.append("Resource \(index + 1): \(issue)"); continue }
                candidates.append(book)
            }
        } else if ext == "csv" {
            let parsed = try DelimitedImporter(headerAliases: ["title": "text", "note": "source", "url": "category"]).parse(text, mode: .automatic, headerMode: .present)
            issues.append(contentsOf: parsed.issues)
            guard parsed.entries.count <= DataLimits.resources else { throw ImportFailure.resourceCountExceeded }
            for (index, entry) in parsed.entries.enumerated() {
                var book = ResourceBook(); book.title = entry.text; book.author = entry.author; book.note = entry.source; book.url = entry.section
                if let issue = validationIssue(for: book) { issues.append("Resource \(index + 1): \(issue)"); continue }
                candidates.append(book)
            }
        } else {
            throw ImportFailure.malformed("Choose a CSV or JSON resource file.")
        }
        guard !candidates.isEmpty else { throw ImportFailure.empty }
        let existingSignatures = Set(existing.map(signature))
        var seen = existingSignatures, valid: [ResourceBook] = [], duplicates = 0
        for book in candidates {
            if !seen.insert(signature(book)).inserted { duplicates += 1 } else { valid.append(book) }
        }
        return ResourceImportPreview(filename: filename, format: ext.uppercased(), valid: valid, duplicates: duplicates, malformed: issues.count, issues: Array(issues.prefix(20)))
    }

    public static func signature(_ book: ResourceBook) -> String {
        [book.title, book.author, book.url].map(EntryDraft.normalized).joined(separator: "\u{1F}")
    }

    private static func validationIssue(for book: ResourceBook) -> String? {
        if book.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "missing title." }
        if book.title.count > DataLimits.metadataCharacters || book.author.count > DataLimits.metadataCharacters || book.url.count > DataLimits.metadataCharacters || book.note.count > DataLimits.entryCharacters { return "a field exceeds the supported limit." }
        return nil
    }
}
