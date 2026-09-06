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

public struct PlainTextImporter: ContentImporter {
    public let extensions = ["txt"]
    public init() {}
    public func parse(_ text: String, mode: TextImportMode) throws -> (entries: [EntryDraft], issues: [String]) {
        let paragraphs = mode == .paragraphs || (mode == .automatic && text.contains("\n\n"))
        let parts = paragraphs ? text.components(separatedBy: "\n\n") : text.components(separatedBy: "\n")
        return (parts.map { EntryDraft(text: $0) }.filter { !$0.text.isEmpty }, [])
    }
}

public struct MarkdownImporter: ContentImporter {
    public let extensions = ["md", "markdown"]
    public init() {}
    public func parse(_ text: String, mode: TextImportMode) throws -> (entries: [EntryDraft], issues: [String]) {
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
        let chars = Array(text); var rows: [[String]] = [], row: [String] = [], cell = "", quoted = false, i = 0
        while i < chars.count {
            if i % 8192 == 0 { try Task.checkCancellation() }
            let c = chars[i]
            if c == "\"" {
                if quoted && i + 1 < chars.count && chars[i + 1] == "\"" { cell.append("\""); i += 1 }
                else if quoted { quoted = false }
                else if cell.isEmpty { quoted = true }
                else { throw ImportFailure.malformed("Unexpected quote in CSV field.") }
            } else if c == separator && !quoted { row.append(cell); cell = "" }
            else if c == "\n" && !quoted { row.append(cell); if row.contains(where: { !$0.isEmpty }) { rows.append(row) }; row = []; cell = "" }
            else { cell.append(c) }
            i += 1
        }
        guard !quoted else { throw ImportFailure.malformed("Unclosed CSV quote.") }
        row.append(cell); if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        guard let first = rows.first else { return ([], []) }
        let headers = first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let aliases = ["text", "quote", "body", "content"]
        let textIndex = headers.firstIndex(where: aliases.contains)
        let hasHeader = textIndex != nil
        func value(_ row: [String], _ key: String) -> String {
            guard hasHeader, let index = headers.firstIndex(of: key), index < row.count else { return "" }
            return row[index]
        }
        var result: [EntryDraft] = [], issues: [String] = []
        for (index, row) in rows.dropFirst(hasHeader ? 1 : 0).enumerated() {
            let position = textIndex ?? 0
            guard position < row.count, !row[position].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { issues.append("Row \(index + 1): missing text."); continue }
            result.append(EntryDraft(text: row[position], author: value(row, "author"), source: value(row, "source"), tags: value(row, "tags").split(whereSeparator: { $0 == ";" || $0 == "|" }).map(String.init), section: value(row, "category")))
        }
        return (result, issues)
    }
}

public struct JSONImporter: ContentImporter {
    public let extensions = ["json", "jsonl"]
    let lines: Bool
    public init(lines: Bool = false) { self.lines = lines }
    public func parse(_ text: String, mode: TextImportMode) throws -> (entries: [EntryDraft], issues: [String]) {
        var values: [Any] = [], issues: [String] = []
        if lines {
            for (index, line) in text.split(separator: "\n").enumerated() {
                do { values.append(try JSONSerialization.jsonObject(with: Data(line.utf8), options: [.fragmentsAllowed])) }
                catch { issues.append("Line \(index + 1): invalid JSON.") }
            }
        } else {
            do {
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
