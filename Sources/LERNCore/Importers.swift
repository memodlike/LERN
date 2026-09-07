import Foundation

public enum ImportFailure: LocalizedError {
    case tooLarge, encoding, malformed(String), empty, unsupported
    public var errorDescription: String? {
        switch self {
        case .tooLarge: return "The file exceeds the 100 MB limit. Split it into smaller files."
        case .encoding: return "Save the file as UTF-8 text and try again."
        case .malformed(let detail): return "The file could not be read: \(detail)"
        case .empty: return "No valid entries were found."
        case .unsupported: return "Choose a Markdown, TXT, CSV, TSV, JSON or JSONL file."
        }
    }
}
public enum TextImportMode: String, CaseIterable, Sendable { case automatic, lines, paragraphs }
public struct ImportPreview: Sendable {
    public var name: String
    public var format: String
    public var entries: [EntryDraft]
    public var duplicates: Int
    public var malformed: Int
    public var issues: [String]
    public init(name: String, format: String, entries: [EntryDraft], duplicates: Int, malformed: Int, issues: [String]) { self.name = name; self.format = format; self.entries = entries; self.duplicates = duplicates; self.malformed = malformed; self.issues = issues }
    public var firstFive: [EntryDraft] { Array(entries.prefix(5)) }
}
public protocol ContentImporter: Sendable {
    var extensions: [String] { get }
    func parse(_ text: String, mode: TextImportMode) throws -> (entries: [EntryDraft], issues: [String])
}
public struct ImportService: Sendable {
    public static let byteLimit = 100 * 1024 * 1024
    public static let entryLimit = 100_000
    public static let textLimit = 20_000
    private let importers: [any ContentImporter] = [MarkdownImporter(), PlainTextImporter(), DelimitedImporter(), JSONImporter()]
    public init() {}
    public func preview(data: Data, filename: String, mode: TextImportMode = .automatic) throws -> ImportPreview {
        guard data.count <= Self.byteLimit else { throw ImportFailure.tooLarge }
        guard var text = String(data: data, encoding: .utf8) else { throw ImportFailure.encoding }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let ext = (filename as NSString).pathExtension.lowercased()
        guard let parser = importers.first(where: { $0.extensions.contains(ext) }) else { throw ImportFailure.unsupported }
        let output: (entries: [EntryDraft], issues: [String])
        if ext == "tsv" { output = try DelimitedImporter(separator: "\t").parse(text, mode: mode) }
        else if ext == "jsonl" { output = try JSONImporter(lines: true).parse(text, mode: mode) }
        else { output = try parser.parse(text, mode: mode) }
        guard output.entries.count <= Self.entryLimit else { throw ImportFailure.tooLarge }
        var seen = Set<String>(), unique: [EntryDraft] = [], duplicates = 0, issues = output.issues
        for (index, entry) in output.entries.enumerated() {
            if index % 256 == 0 { try Task.checkCancellation() }
            if entry.text.isEmpty || entry.text.count > Self.textLimit {
                issues.append("Entry \(index + 1): empty or longer than 20,000 characters."); continue
            }
            if seen.insert(entry.id).inserted { unique.append(entry) } else { duplicates += 1 }
        }
        guard !unique.isEmpty else { throw ImportFailure.empty }
        return ImportPreview(name: (filename as NSString).deletingPathExtension, format: ext.uppercased(), entries: unique, duplicates: duplicates, malformed: issues.count, issues: Array(issues.prefix(20)))
    }
}

private struct TextLines: Sequence {
    let text: String
    func makeIterator() -> AnyIterator<Substring> {
        var position = text.startIndex
        return AnyIterator {
            guard position < text.endIndex else { return nil }
            let end = text[position...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[position..<end]
            position = end == text.endIndex ? end : text.index(after: end)
            return line
        }
    }
}
public struct PlainTextImporter: ContentImporter {
    public let extensions = ["txt"]
    public init() {}
    public func parse(_ text: String, mode: TextImportMode) throws -> (entries: [EntryDraft], issues: [String]) {
        let paragraphs = mode == .paragraphs || (mode == .automatic && text.contains("\n\n"))
        var entries: [EntryDraft] = [], buffer = "", lineNumber = 0
        func append(_ value: String) throws {
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return }
            guard entries.count < ImportService.entryLimit else { throw ImportFailure.tooLarge }
            guard clean.count <= ImportService.textLimit else { throw ImportFailure.malformed("An entry exceeds 20,000 characters.") }
            entries.append(EntryDraft(text: clean))
        }
        for line in TextLines(text: text) {
            lineNumber += 1; if lineNumber % 256 == 0 { try Task.checkCancellation() }
            if paragraphs {
                if line.trimmingCharacters(in: .whitespaces).isEmpty { try append(buffer); buffer = "" }
                else { guard buffer.utf8.count + line.utf8.count < 100_000 else { throw ImportFailure.tooLarge }; buffer += (buffer.isEmpty ? "" : "\n") + line }
            } else { try append(String(line)) }
        }
        if paragraphs { try append(buffer) }
        return (entries, [])
    }
}

public struct MarkdownImporter: ContentImporter {
    public let extensions = ["md", "markdown"]
    public init() {}
    public func parse(_ text: String, mode: TextImportMode) throws -> (entries: [EntryDraft], issues: [String]) {
        guard text.utf8.reduce(0, { $0 + ($1 == 10 ? 1 : 0) }) <= 500_000 else { throw ImportFailure.tooLarge }
        var lines = text.components(separatedBy: "\n"), author = "", tags: [String] = [], source = ""
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---", let end = lines.dropFirst().firstIndex(of: "---") {
            for line in lines[1..<end] {
                let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                switch parts[0].lowercased() {
                case "author": author = value
                case "source": source = value
                case "tags": tags = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                default: break
                }
            }
            lines.removeFirst(end + 1)
        }
        var entries: [EntryDraft] = [], paragraph: [String] = [], section = "", inCode = false
        func flush() {
            let value = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { entries.append(EntryDraft(text: value, author: author, source: source, tags: tags, section: section)) }
            paragraph = []
        }
        for (index, raw) in lines.enumerated() {
            if index % 256 == 0 { try Task.checkCancellation() }
            guard entries.count <= ImportService.entryLimit, raw.count <= ImportService.textLimit else { throw ImportFailure.tooLarge }
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { flush(); inCode.toggle(); continue }
            if inCode { continue }
            if line.isEmpty || line == "---" { flush(); continue }
            if line.hasPrefix("#") { flush(); section = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces); continue }
            let range = line.range(of: "^(?:[-*+] |[0-9]+[.)] |> ?)", options: .regularExpression)
            if let range {
                flush(); let content = String(line[range.upperBound...])
                if !content.isEmpty { entries.append(EntryDraft(text: content, author: author, source: source, tags: tags, section: section)) }
            } else { paragraph.append(line) }
        }
        flush()
        return (entries, [])
    }
}

public struct DelimitedImporter: ContentImporter {
    public let extensions = ["csv", "tsv"]
    let separator: Character
    public init(separator: Character = ",") { self.separator = separator }
    public func parse(_ text: String, mode: TextImportMode) throws -> (entries: [EntryDraft], issues: [String]) {
        var entries: [EntryDraft] = [], issues: [String] = [], row: [String] = [], cell = ""
        var quoted = false, afterQuote = false, headers: [String]?, hasHeader = false, rowCount = 0, processed = 0, fieldLength = 0
        let aliases = ["text", "quote", "body", "content"]
        func finishCell() throws {
            guard row.count < 64 else { throw ImportFailure.malformed("A row has more than 64 columns.") }
            row.append(cell); cell = ""; fieldLength = 0; afterQuote = false
        }
        func finishRow() throws {
            try finishCell()
            defer { row = [] }
            guard row.contains(where: { !$0.isEmpty }) else { return }
            rowCount += 1
            guard rowCount <= ImportService.entryLimit + 1 else { throw ImportFailure.tooLarge }
            if headers == nil {
                headers = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                hasHeader = headers!.contains(where: aliases.contains)
                if hasHeader { return }
            }
            let textIndex = hasHeader ? headers!.firstIndex(where: aliases.contains)! : 0
            func value(_ key: String) -> String { guard hasHeader, let i = headers!.firstIndex(of: key), i < row.count else { return "" }; return row[i] }
            guard textIndex < row.count, !row[textIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { issues.append("Row \(rowCount): missing text."); return }
            guard entries.count < ImportService.entryLimit else { throw ImportFailure.tooLarge }
            entries.append(EntryDraft(text: row[textIndex], author: value("author"), source: value("source"), tags: value("tags").split(whereSeparator: { $0 == ";" || $0 == "|" }).map(String.init), section: value("category")))
        }
        for c in text {
            processed += 1; if processed % 8192 == 0 { try Task.checkCancellation() }
            if quoted {
                if c == "\"" { quoted = false; afterQuote = true }
                else { cell.append(c); fieldLength += 1 }
            } else if afterQuote && c == "\"" { cell.append(c); fieldLength += 1; quoted = true; afterQuote = false }
            else if c == separator { try finishCell() }
            else if c == "\n" { try finishRow() }
            else if c == "\"" && cell.isEmpty { quoted = true }
            else if afterQuote { if !c.isWhitespace { throw ImportFailure.malformed("Unexpected character after a quoted field.") } }
            else if c == "\"" { throw ImportFailure.malformed("Unexpected quote in CSV field.") }
            else { cell.append(c); fieldLength += 1 }
            guard fieldLength <= ImportService.textLimit else { throw ImportFailure.malformed("A field exceeds 20,000 characters.") }
        }
        guard !quoted else { throw ImportFailure.malformed("Unclosed CSV quote.") }
        if !row.isEmpty || !cell.isEmpty { try finishRow() }
        return (entries, issues)
    }
}

public struct JSONImporter: ContentImporter {
    public let extensions = ["json", "jsonl"]
    let lines: Bool
    public init(lines: Bool = false) { self.lines = lines }
    public func parse(_ text: String, mode: TextImportMode) throws -> (entries: [EntryDraft], issues: [String]) {
        var values: [Any] = [], issues: [String] = []
        if lines {
            for (index, line) in TextLines(text: text).enumerated() {
                guard index < ImportService.entryLimit else { throw ImportFailure.tooLarge }; try Task.checkCancellation()
                try validateJSONBudget(String(line))
                do { values.append(try JSONSerialization.jsonObject(with: Data(line.utf8), options: [.fragmentsAllowed])) }
                catch { issues.append("Line \(index + 1): invalid JSON.") }
            }
        } else {
            do {
                try validateJSONBudget(text)
                let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
                guard let array = object as? [Any] else { throw ImportFailure.malformed("Expected a JSON array.") }
                values = array
            } catch { throw ImportFailure.malformed("Expected an array of strings or objects.") }
        }
        var entries: [EntryDraft] = []
        for (index, object) in values.enumerated() {
            if index % 256 == 0 { try Task.checkCancellation() }
            if let value = object as? String { entries.append(EntryDraft(text: value)); continue }
            guard let object = object as? [String: Any], let text = ["text", "quote", "body", "content"].compactMap({ object[$0] as? String }).first else { issues.append("Entry \(index + 1): missing text."); continue }
            let tags = object["tags"] as? [String] ?? (object["tags"] as? String)?.split(separator: ",").map(String.init) ?? []
            entries.append(EntryDraft(text: text, author: object["author"] as? String ?? "", source: object["source"] as? String ?? "", tags: tags, section: object["category"] as? String ?? ""))
        }
        return (entries, issues)
    }
}

private func validateJSONBudget(_ text: String) throws {
    var depth = 0, topItems = 0, inString = false, escaped = false, characters = 0
    for byte in text.utf8 {
        characters += 1; if characters % 8192 == 0 { try Task.checkCancellation() }
        if inString {
            if escaped { escaped = false } else if byte == 92 { escaped = true } else if byte == 34 { inString = false }
            continue
        }
        if byte == 34 { inString = true }
        else if byte == 91 || byte == 123 { depth += 1; if depth > 32 { throw ImportFailure.malformed("JSON nesting exceeds 32 levels.") } }
        else if byte == 93 || byte == 125 { depth -= 1 }
        else if byte == 44 && depth == 1 { topItems += 1; if topItems >= ImportService.entryLimit { throw ImportFailure.tooLarge } }
    }
}
