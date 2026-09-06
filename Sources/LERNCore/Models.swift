import Foundation
import CryptoKit

public enum Product {
    public static let name = "LERN"
    public static let appGroup = "group.app.lern.local"
    public static let scheme = "lern"
}

public struct EntryDraft: Codable, Hashable, Sendable {
    public var text: String
    public var author: String
    public var source: String
    public var tags: [String]
    public var section: String
    public init(text: String, author: String = "", source: String = "", tags: [String] = [], section: String = "") {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tags = tags; self.section = section
    }
    public static func normalized(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
    public var id: String {
        let pieces = [text, author, source].map(Self.normalized)
        let data = (try? JSONEncoder().encode(pieces)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    public var searchText: String {
        Self.normalized(([text, author, source, section] + tags).joined(separator: " "))
    }
}

public struct EntryValue: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var draft: EntryDraft
    public var favorite: Bool = false
    public var disliked: Bool = false
    public var muted: Bool = false
    public var createdAt: Date = Date()
    public init(draft: EntryDraft) { self.id = draft.id; self.draft = draft }
}

public struct TopicValue: Codable, Identifiable, Hashable, Sendable {
    public var id: String = UUID().uuidString
    public var name: String
    public var kind: String = "import"
    public var count: Int = 0
    public init(name: String, kind: String = "import") { self.name = name; self.kind = kind }
}

public struct ContentSource: Codable, Equatable, Hashable, Sendable {
    public var topicIDs: [String] = []
    public var favoritesOnly = false
    public var myContentOnly = false
    public var tag: String = ""
    public init(topicIDs: [String] = [], favoritesOnly: Bool = false, myContentOnly: Bool = false, tag: String = "") {
        self.topicIDs = topicIDs; self.favoritesOnly = favoritesOnly; self.myContentOnly = myContentOnly; self.tag = tag
    }
}

public enum SelectionMode: String, Codable, CaseIterable, Sendable { case sequential, shuffle, random }
public struct SelectionCursor: Codable, Sendable {
    public var position: Int = 0
    public var cycle: UInt64 = 0
    public var seed: UInt64 = UInt64.random(in: 1...UInt64.max)
    public var lastID: String?
    public var fingerprint: String = ""
    public init() {}
}

public struct ReminderRule: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID().uuidString
    public var name = "Daily reminder"
    public var enabled = true
    public var source = ContentSource()
    public var mode: SelectionMode = .shuffle
    public var weekdays: [Int] = Array(1...7)
    public var explicitMinutes: [Int] = [540]
    public var usesRange = false
    public var startMinute = 540
    public var endMinute = 1260
    public var frequency = 3
    public var sound = "default"
    public var isAlarm = false
    public var revision = UUID().uuidString
    public init() {}
    public var minutes: [Int] {
        if !usesRange { return Array(Set(explicitMinutes.filter { (0..<1440).contains($0) })).sorted() }
        let n = min(60, max(1, frequency))
        let start = min(1439, max(0, startMinute)), end = min(1439, max(start, endMinute))
        if n == 1 { return [start] }
        return Array(Set((0..<n).map { start + (end - start) * $0 / (n - 1) })).sorted()
    }
}

public struct DeliveryPlan: Codable, Identifiable, Sendable {
    public var id: String
    public var ruleID: String
    public var revision: String
    public var date: Date
    public var entryID: String
    public var topicID: String
    public var state = "planned"
    public var openedAt: Date?
    public init(id: String, ruleID: String, revision: String, date: Date, entryID: String, topicID: String) { self.id = id; self.ruleID = ruleID; self.revision = revision; self.date = date; self.entryID = entryID; self.topicID = topicID }
}
public struct HistoryValue: Codable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var entryID: String
    public var date = Date()
    public var kind: String
    public init(entryID: String, kind: String) { self.entryID = entryID; self.kind = kind }
}

public struct ThemeValue: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID().uuidString
    public var name: String
    public var background = "142C46"
    public var secondary = "517B98"
    public var foreground = "FFFFFF"
    public var font = "rounded"
    public var weight = "regular"
    public var alignment = "center"
    public var overlay = 0.3
    public var photoName: String?
    public var gradient = true
    public init(name: String) { self.name = name }
    public static var starters: [ThemeValue] {
        [("Horizon", "142C46", "517B98", "FFFFFF", "rounded"),
         ("Daylight", "EEF3F8", "C9DDEB", "142C46", "serif"),
         ("Midnight", "10151E", "28344E", "FFFFFF", "serif"),
         ("Forest", "123B37", "376457", "FFFFFF", "rounded"),
         ("Plum", "38263F", "785870", "FFFFFF", "serif"),
         ("Paper", "FFFFFF", "FFFFFF", "16263B", "default")].enumerated().map { index, item in
            var t = ThemeValue(name: item.0); t.id = "starter-\(index)"; t.background = item.1; t.secondary = item.2
            t.foreground = item.3; t.font = item.4; t.overlay = 0; return t
        }
    }
}
public struct WidgetPreset: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID().uuidString
    public var name = "Daily thought"
    public var source = ContentSource()
    public var themeID = "starter-0"
    public var border = false
    public var refreshMinutes = 60
    public var showButtons = true
    public var mode: SelectionMode = .shuffle
    public var kind = "daily"
    public init() {}
}
public struct ResourceBook: Codable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var title = ""
    public var author = ""
    public var note = ""
    public var url = ""
    public var coverName: String?
    public var favorite = false
    public init() {}
}
public struct StreakState: Codable, Equatable, Sendable {
    public var current = 0
    public var longest = 0
    public var freezes = 3
    public var lastDay: Date?
    public var readingDaysSinceFreeze = 0
    public var enabled = true
    public init() {}
    public mutating func read(on date: Date, calendar: Calendar = .autoupdatingCurrent) {
        guard enabled else { return }
        let day = calendar.startOfDay(for: date)
        if let last = lastDay {
            let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: day).day ?? 0
            guard gap > 0 else { return }
            let missed = gap - 1
            if missed <= freezes { freezes -= missed; current += 1 } else { current = 1 }
        } else { current = 1 }
        readingDaysSinceFreeze += 1
        if readingDaysSinceFreeze >= 7 { freezes = min(3, freezes + 1); readingDaysSinceFreeze = 0 }
        longest = max(longest, current); lastDay = day
    }
}
public struct Preferences: Codable, Sendable {
    public var name = ""
    public var gender = ""
    public var language = "system"
    public var feedSource = ContentSource()
    public var feedMode: SelectionMode = .shuffle
    public var watchSource = ContentSource()
    public var wallpaperSource = ContentSource()
    public var lockSource = ContentSource()
    public var fortuneSource = ContentSource()
    public var themeID = "starter-0"
    public var themeMixIDs: [String] = []
    public var themeRotation = "fixed"
    public var watermark = false
    public var haptics = true
    public var streakReminder = false
    public var onboardingComplete = false
    public var mutedWords: [String] = []
    public var streak = StreakState()
    public init() {}
}
