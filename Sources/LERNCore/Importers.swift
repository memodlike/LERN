import Foundation
import CryptoKit

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
public enum CSVDelimiter: String, CaseIterable, Sendable { case automatic, comma, semicolon, tab
    public var character: Character? { switch self { case .automatic: return nil; case .comma: return ","; case .semicolon: return ";"; case .tab: return "\t" } }
    public var label: String { switch self { case .automatic: return "Automatic"; case .comma: return "Comma"; case .semicolon: return "Semicolon"; case .tab: return "Tab" } }
}
public struct ImportPreview: Sendable {
    public var name: String
    public var filename: String
    public var format: String
    public var checksum: String
    public var entries: [EntryDraft]
    public var duplicates: Int
    public var malformed: Int
    public var issues: [String]
    public var detectedLayout: TextImportMode?
    public var detectedDelimiter: CSVDelimiter?
    public init(name: String, filename: String = "", format: String, checksum: String = "", entries: [EntryDraft], duplicates: Int, malformed: Int, issues: [String], detectedLayout: TextImportMode? = nil, detectedDelimiter: CSVDelimiter? = nil) {
        self.name = name; self.filename = filename; self.format = format; self.checksum = checksum; self.entries = entries; self.duplicates = duplicates; self.malformed = malformed; self.issues = issues; self.detectedLayout = detectedLayout; self.detectedDelimiter = detectedDelimiter
    }
    public var firstFive: [EntryDraft] { Array(entries.prefix(5)) }
    public var sectionCount: Int { Set(entries.map { EntryDraft.normalized($0.section) }.filter { !$0.isEmpty }).count }
    public var shortenedInNotifications: Int { entries.filter { $0.text.count > NotificationBodyLimit.characters }.count }
}
public enum NotificationBodyLimit { public static let characters = 500 }
public protocol ContentImporter: Sendable {
    var extensions: [String] { get }
    func parse(_ text: String, mode: TextImportMode) throws -> (entries: [EntryDraft], issues: [String])
}
public struct ImportService: Sendable {
    public static let byteLimit = DataLimits.importBytes
    public static let entryLimit = DataLimits.entriesPerImport
    public static let textLimit = DataLimits.entryCharacters
    private let importers: [any ContentImporter] = [MarkdownImporter(), PlainTextImporter(), DelimitedImporter(), JSONImporter()]
    public init() {}
    public func preview(data: Data, filename: String, mode: TextImportMode = .automatic, delimiter: CSVDelimiter = .automatic) throws -> ImportPreview {
        guard data.count <= Self.byteLimit else { throw ImportFailure.tooLarge }
        guard var text = String(data: data, encoding: .utf8) else { throw ImportFailure.encoding }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let ext = (filename as NSString).pathExtension.lowercased()
        guard let parser = importers.first(where: { $0.extensions.contains(ext) }) else { throw ImportFailure.unsupported }
        let output: (entries: [EntryDraft], issues: [String])
        var detectedDelimiter: CSVDelimiter? = nil
        if ext == "tsv" { output = try DelimitedImporter(separator: "\t").parse(text, mode: mode); detectedDelimiter = .tab }
        else if ext == "csv" {
            let choice = delimiter == .automatic ? DelimitedImporter.detectDelimiter(in: text) : delimiter
            output = try DelimitedImporter(separator: choice.character ?? ",").parse(text, mode: mode); detectedDelimiter = choice
        }
        else if ext == "jsonl" { output = try JSONImporter(lines: true).parse(text, mode: mode) }
        else { output = try parser.parse(text, mode: mode); detectedDelimiter = nil }
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
        let layout: TextImportMode? = ext == "txt" ? PlainTextImporter.detectedLayout(text, requested: mode) : nil
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return ImportPreview(name: (filename as NSString).deletingPathExtension, filename: filename, format: ext.uppercased(), checksum: checksum, entries: unique, duplicates: duplicates, malformed: issues.count, issues: Array(issues.prefix(20)), detectedLayout: layout, detectedDelimiter: detectedDelimiter)
    }
}

private struct DraftBudget {
    private var bytes = 0
    mutating func make(text: String, author: String = "", source: String = "", tags: [String] = [], section: String = "") throws -> EntryDraft {
        guard text.count <= ImportService.textLimit else { throw ImportFailure.malformed("An entry exceeds 20,000 characters.") }
        try validateMetadata(author: author, source: source, tags: tags, section: section)
        let normalizedTags = EntryDraft.normalizedTags(tags)
        try validateMetadata(author: author, source: source, tags: normalizedTags, section: section)
        bytes += text.utf8.count + author.utf8.count + source.utf8.count + section.utf8.count + normalizedTags.reduce(0) { $0 + $1.utf8.count }
        guard bytes <= ImportService.byteLimit else { throw ImportFailure.tooLarge }
        return EntryDraft(text: text, author: author, source: source, tags: normalizedTags, section: section)
    }
}

private func validateMetadata(author: String = "", source: String = "", tags: [String] = [], section: String = "") throws {
    guard author.count <= DataLimits.metadataCharacters, source.count <= DataLimits.metadataCharacters, section.count <= DataLimits.metadataCharacters,
          tags.count <= DataLimits.tagsPerEntry, tags.allSatisfy({ $0.count <= DataLimits.tagCharacters }) else {
        throw ImportFailure.malformed("Metadata exceeds the supported character or tag limit.")
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
    public static func detectedLayout(_ text: String, requested: TextImportMode) -> TextImportMode {
        guard requested == .automatic else { return requested }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let blankRuns = lines.reduce(into: 0) { count, line in if line.trimmingCharacters(in: .whitespaces).isEmpty { count += 1 } }
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        // Blank-line grouping is useful only when there is content on both sides; otherwise preserve one-line units.
        return blankRuns > 0 && nonEmpty.count > 1 ? .paragraphs : .lines
    }
    public func parse(_ text: String, mode: TextImportMode) throws -> (entries: [EntryDraft], issues: [String]) {
        let paragraphs = Self.detectedLayout(text, requested: mode) == .paragraphs
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
                guard line.count <= ImportService.textLimit else { throw ImportFailure.tooLarge }
                let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                switch parts[0].lowercased() {
                case "author": author = value
                case "source": source = value
                case "tags": tags = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).split(separator: ",", maxSplits: 64).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                default: break
                }
                try validateMetadata(author: author, source: source, tags: tags)
            }
            lines.removeFirst(end + 1)
        }
        var entries: [EntryDraft] = [], paragraph: [String] = [], section = "", inCode = false
        var paragraphLength = 0, budget = DraftBudget()
        func append(_ value: String) throws {
            guard !value.isEmpty else { return }
            guard entries.count < ImportService.entryLimit else { throw ImportFailure.tooLarge }
            entries.append(try budget.make(text: value, author: author, source: source, tags: tags, section: section))
        }
        func flush() throws {
            let value = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            try append(value)
            paragraph = []; paragraphLength = 0
        }
        for (index, raw) in lines.enumerated() {
            if index % 256 == 0 { try Task.checkCancellation() }
            guard entries.count <= ImportService.entryLimit, raw.count <= ImportService.textLimit else { throw ImportFailure.tooLarge }
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { paragraph.append(raw); paragraphLength += raw.count; inCode.toggle(); continue }
            if inCode { paragraph.append(raw); paragraphLength += raw.count + 1; guard paragraphLength <= ImportService.textLimit else { throw ImportFailure.malformed("A code block exceeds 20,000 characters.") }; continue }
            if line.isEmpty || line == "---" { try flush(); continue }
            if let heading = line.range(of: "^#{1,6}[ \\t]+", options: .regularExpression) { try flush(); section = line[heading.upperBound...].trimmingCharacters(in: .whitespaces); try validateMetadata(section: section); continue }
            let range = line.range(of: "^(?:[-*+] |[0-9]+[.)] |> ?)", options: .regularExpression)
            if let range {
                try flush(); let content = String(line[range.upperBound...])
                try append(content)
            } else {
                paragraphLength += line.count + (paragraph.isEmpty ? 0 : 1)
                guard paragraphLength <= ImportService.textLimit else { throw ImportFailure.malformed("A paragraph exceeds 20,000 characters.") }
                paragraph.append(line)
            }
        }
        try flush()
        return (entries, [])
    }
}

public struct DelimitedImporter: ContentImporter {
    public let extensions = ["csv", "tsv"]
    let separator: Character
    let headerAliases: [String: String]
    public init(separator: Character = ",", headerAliases: [String: String] = [:]) { self.separator = separator; self.headerAliases = headerAliases }
    public static func detectDelimiter(in text: String) -> CSVDelimiter {
        let sample = text.prefix(8_192)
        var quoted = false, counts: [Character: Int] = [",": 0, ";": 0, "\t": 0]
        for character in sample {
            if character == "\"" { quoted.toggle() }
            else if !quoted, counts[character] != nil { counts[character, default: 0] += 1 }
        }
        switch counts.max(by: { $0.value < $1.value })?.key {
        case ";": return .semicolon
        case "\t": return .tab
        default: return .comma
        }
    }
    public func parse(_ text: String, mode: TextImportMode) throws -> (entries: [EntryDraft], issues: [String]) {
        var entries: [EntryDraft] = [], issues: [String] = [], row: [String] = [], cell = ""
        var quoted = false, afterQuote = false, headers: [String]?, hasHeader = false, rowCount = 0, processed = 0, fieldLength = 0
            let aliases = ["text", "quote", "body", "content"]
        var budget = DraftBudget()
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
                headers = row.map { field in
                    let key = field.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))).lowercased()
                    return headerAliases[key] ?? key
                }
                hasHeader = headers!.contains(where: aliases.contains)
                if hasHeader { return }
            }
            let textIndex = hasHeader ? headers!.firstIndex(where: aliases.contains)! : 0
            func value(_ key: String) -> String { guard hasHeader, let i = headers!.firstIndex(of: key), i < row.count else { return "" }; return row[i] }
            guard textIndex < row.count, !row[textIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { issues.append("Row \(rowCount): missing text."); return }
            guard entries.count < ImportService.entryLimit else { throw ImportFailure.tooLarge }
            let tags = value("tags").split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "|" }).map(String.init)
            entries.append(try budget.make(text: row[textIndex], author: value("author"), source: value("source"), tags: tags, section: value("section").isEmpty ? value("category") : value("section")))
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
        guard text.utf8.count <= ImportService.byteLimit else { throw ImportFailure.tooLarge }
        var entries: [EntryDraft] = [], issues: [String] = []
        var jsonBudget = JSONResourceBudget(), draftBudget = DraftBudget()
        func append(_ object: Any, index: Int) throws {
            guard entries.count < ImportService.entryLimit else { throw ImportFailure.tooLarge }
            if let value = object as? String { entries.append(try draftBudget.make(text: value)); return }
            guard let object = object as? [String: Any], let text = ["text", "quote", "body", "content"].compactMap({ object[$0] as? String }).first else {
                issues.append("Entry \(index + 1): missing text."); return
            }
            let tags = object["tags"] as? [String] ?? (object["tags"] as? String)?.split(separator: ",", maxSplits: 64).map(String.init) ?? []
            let section = object["section"] as? String ?? object["category"] as? String ?? ""
            entries.append(try draftBudget.make(text: text, author: object["author"] as? String ?? "", source: object["source"] as? String ?? "", tags: tags, section: section))
        }
        if lines {
            for (index, line) in TextLines(text: text).enumerated() {
                guard index < ImportService.entryLimit else { throw ImportFailure.tooLarge }; try Task.checkCancellation()
                try jsonBudget.validate(String(line))
                let object: Any
                do { object = try JSONSerialization.jsonObject(with: Data(line.utf8), options: [.fragmentsAllowed]) }
                catch { issues.append("Line \(index + 1): invalid JSON."); continue }
                try append(object, index: index)
            }
        } else {
            try jsonBudget.validate(text)
            let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
            guard let array = object as? [Any] else { throw ImportFailure.malformed("Expected a JSON array.") }
            for (index, object) in array.enumerated() {
                if index % 256 == 0 { try Task.checkCancellation() }
                try append(object, index: index)
            }
        }
        return (entries, issues)
    }
}

/// Bounds allocation before Foundation decodes JSON; reuse one budget for a JSONL stream.
public struct JSONResourceBudget: Sendable {
    private let maxTokens: Int
    private let maxContainerItems: Int
    private let maxNestedContainerItems: Int
    private let maxStringBytes: Int
    private var tokens = 0
    public init(maxTokens: Int = 2_000_000, maxContainerItems: Int = 100_000, maxNestedContainerItems: Int = 1_024, maxStringBytes: Int = 120_000) {
        self.maxTokens = maxTokens; self.maxContainerItems = maxContainerItems
        self.maxNestedContainerItems = maxNestedContainerItems; self.maxStringBytes = maxStringBytes
    }
    public mutating func validate(_ text: String) throws {
        var containers: [Int] = [], inString = false, escaped = false, inPrimitive = false, stringBytes = 0, processed = 0
        func startToken() throws {
            guard tokens < maxTokens else { throw ImportFailure.tooLarge }
            tokens += 1
            if !containers.isEmpty {
                let index = containers.count - 1
                let limit = containers.count == 1 ? maxContainerItems : maxNestedContainerItems
                guard containers[index] < limit else { throw ImportFailure.tooLarge }
                containers[index] += 1
            }
        }
        for byte in text.utf8 {
            processed += 1; if processed % 8192 == 0 { try Task.checkCancellation() }
            if inString {
                if byte == 34 && !escaped { inString = false; continue }
                stringBytes += 1
                guard stringBytes <= maxStringBytes else { throw ImportFailure.tooLarge }
                if escaped { escaped = false } else if byte == 92 { escaped = true }
                continue
            }
            switch byte {
            case 34:
                try startToken(); inString = true; stringBytes = 0; inPrimitive = false
            case 91, 123:
                try startToken(); containers.append(0); inPrimitive = false
                guard containers.count <= 32 else { throw ImportFailure.malformed("JSON nesting exceeds 32 levels.") }
            case 93, 125:
                if !containers.isEmpty { containers.removeLast() }; inPrimitive = false
            case 9, 10, 13, 32, 44, 58:
                inPrimitive = false
            default:
                if !inPrimitive { try startToken(); inPrimitive = true }
            }
        }
    }
}
