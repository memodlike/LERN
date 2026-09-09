import Foundation
import CryptoKit

public enum Product {
    public static let name = "LERN"
    public static let appGroup = "group.com.memodlike.lern"
    public static let scheme = "lern"
}

/// Product limits shared by import, persistence, backup validation, and UI guards.
public enum DataLimits {
    public static let importBytes = 100 * 1024 * 1024
    public static let entriesPerImport = 100_000
    public static let entriesInLibrary = 200_000
    public static let entryCharacters = 20_000
    public static let metadataCharacters = 2_000
    public static let tagsPerEntry = 64
    public static let tagCharacters = 256
    public static let topics = 10_000
    public static let memberships = 1_000_000
    public static let history = 1_000_000
    public static let reminders = 100
    public static let themes = 200
    public static let presets = 100
    public static let resources = 10_000
    public static let cursors = 10_000
    public static let mutedWords = 1_000
    public static let photos = 200
    public static let photoBytes = 20_000_000
    public static let totalPhotoBytes = 250_000_000
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
        self.tags = Self.normalizedTags(tags); self.section = section.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func normalized(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
    public static func normalizedTags(_ values: [String]) -> [String] {
        var result: [String] = []
        for value in values {
            for tag in value.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "|" }) {
                let clean = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { continue }
                result.append(clean)
            }
        }
        return result
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

public enum WatchPayload {
    public static let schemaVersion = 1
    public static let maximumEntries = 100
    public static let maximumBytes = 60_000

    public static func decodeEntries(_ data: Data, version: Int?) -> [EntryValue]? {
        guard data.count < maximumBytes,
              version == nil || version == schemaVersion,
              let entries = try? JSONDecoder().decode([EntryValue].self, from: data),
              entries.count <= maximumEntries,
              Set(entries.map(\.id)).count == entries.count
        else { return nil }
        return entries
    }
}

public struct TopicValue: Codable, Identifiable, Hashable, Sendable {
    public var id: String = UUID().uuidString
    public var name: String
    public var kind: String = "import"
    public var count: Int = 0
    public var status = "active"
    public var parentTopicID: String?
    public var originalFilename: String?
    public var format: String?
    public var checksum: String?
    public var createdAt = Date()
    public var updatedAt = Date()
    public var warningCount = 0
    public init(name: String, kind: String = "import") { self.name = name; self.kind = kind }
    public var isPaused: Bool { status == "paused" }
    private enum CodingKeys: String, CodingKey { case id, name, kind, count, status, parentTopicID, originalFilename, format, checksum, createdAt, updatedAt, warningCount }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try values.decode(String.self, forKey: .name), kind: try values.decodeIfPresent(String.self, forKey: .kind) ?? "import")
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? id
        count = try values.decodeIfPresent(Int.self, forKey: .count) ?? count
        status = try values.decodeIfPresent(String.self, forKey: .status) ?? status
        parentTopicID = try values.decodeIfPresent(String.self, forKey: .parentTopicID)
        originalFilename = try values.decodeIfPresent(String.self, forKey: .originalFilename)
        format = try values.decodeIfPresent(String.self, forKey: .format)
        checksum = try values.decodeIfPresent(String.self, forKey: .checksum)
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? createdAt
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? updatedAt
        warningCount = try values.decodeIfPresent(Int.self, forKey: .warningCount) ?? warningCount
    }
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
public enum NotificationTitleMode: String, Codable, CaseIterable, Sendable {
    case topic
    case section
    case none

    public static func normalized(_ persistedValue: String?) -> Self {
        switch persistedValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "section": .section
        case "none": .none
        case "topic", "custom", "appname", "app_name", "", nil: .topic
        default: .topic
        }
    }
}
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
    public var notificationTitleMode: NotificationTitleMode = .topic
    public var notificationTopic: String?
    public var notificationSymbol: String?
    public var notificationTint: String?
    public var revision = UUID().uuidString
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case id, name, enabled, source, mode, weekdays, explicitMinutes, usesRange, startMinute, endMinute, frequency, sound, isAlarm, notificationTitleMode, notificationTopic, notificationSymbol, notificationTint, revision
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? id
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? name
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        source = try values.decodeIfPresent(ContentSource.self, forKey: .source) ?? source
        mode = try values.decodeIfPresent(SelectionMode.self, forKey: .mode) ?? mode
        weekdays = try values.decodeIfPresent([Int].self, forKey: .weekdays) ?? weekdays
        explicitMinutes = try values.decodeIfPresent([Int].self, forKey: .explicitMinutes) ?? explicitMinutes
        usesRange = try values.decodeIfPresent(Bool.self, forKey: .usesRange) ?? usesRange
        startMinute = try values.decodeIfPresent(Int.self, forKey: .startMinute) ?? startMinute
        endMinute = try values.decodeIfPresent(Int.self, forKey: .endMinute) ?? endMinute
        frequency = try values.decodeIfPresent(Int.self, forKey: .frequency) ?? frequency
        sound = try values.decodeIfPresent(String.self, forKey: .sound) ?? sound
        isAlarm = try values.decodeIfPresent(Bool.self, forKey: .isAlarm) ?? isAlarm
        notificationTitleMode = .normalized(try? values.decodeIfPresent(String.self, forKey: .notificationTitleMode))
        notificationTopic = try values.decodeIfPresent(String.self, forKey: .notificationTopic)
        notificationSymbol = try values.decodeIfPresent(String.self, forKey: .notificationSymbol)
        notificationTint = try values.decodeIfPresent(String.self, forKey: .notificationTint)
        revision = try values.decodeIfPresent(String.self, forKey: .revision) ?? revision
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encode(name, forKey: .name); try values.encode(enabled, forKey: .enabled)
        try values.encode(source, forKey: .source); try values.encode(mode, forKey: .mode); try values.encode(weekdays, forKey: .weekdays)
        try values.encode(explicitMinutes, forKey: .explicitMinutes); try values.encode(usesRange, forKey: .usesRange)
        try values.encode(startMinute, forKey: .startMinute); try values.encode(endMinute, forKey: .endMinute)
        try values.encode(frequency, forKey: .frequency); try values.encode(sound, forKey: .sound); try values.encode(isAlarm, forKey: .isAlarm)
        try values.encode(notificationTitleMode.rawValue, forKey: .notificationTitleMode)
        try values.encodeIfPresent(notificationTopic, forKey: .notificationTopic); try values.encodeIfPresent(notificationSymbol, forKey: .notificationSymbol)
        try values.encodeIfPresent(notificationTint, forKey: .notificationTint); try values.encode(revision, forKey: .revision)
    }
    public static func isReservedID(_ value: String) -> Bool { value.hasPrefix("system.") }
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
    public var state = "planned"
    public var openedAt: Date?
    public init(id: String, ruleID: String, revision: String, date: Date, entryID: String) { self.id = id; self.ruleID = ruleID; self.revision = revision; self.date = date; self.entryID = entryID }
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
        current = min(1_000_000, max(0, current)); longest = min(1_000_000, max(current, longest))
        freezes = min(3, max(0, freezes)); readingDaysSinceFreeze = min(6, max(0, readingDaysSinceFreeze))
        let day = calendar.startOfDay(for: date)
        if let last = lastDay {
            let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: day).day ?? 0
            guard gap > 0 else { return }
            let missed = gap - 1
            if missed <= freezes { freezes -= missed; current = min(1_000_000, current + 1) } else { current = 1 }
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
    public var showNotificationPreview = true
    public var onboardingComplete = false
    public var mutedWords: [String] = []
    public var streak = StreakState()
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case name, gender, language, feedSource, feedMode, watchSource, wallpaperSource, lockSource, fortuneSource
        case themeID, themeMixIDs, themeRotation, watermark, haptics, streakReminder, showNotificationPreview
        case onboardingComplete, mutedWords, streak
    }
    public init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? name
        gender = try values.decodeIfPresent(String.self, forKey: .gender) ?? gender
        language = try values.decodeIfPresent(String.self, forKey: .language) ?? language
        feedSource = try values.decodeIfPresent(ContentSource.self, forKey: .feedSource) ?? feedSource
        feedMode = try values.decodeIfPresent(SelectionMode.self, forKey: .feedMode) ?? feedMode
        watchSource = try values.decodeIfPresent(ContentSource.self, forKey: .watchSource) ?? watchSource
        wallpaperSource = try values.decodeIfPresent(ContentSource.self, forKey: .wallpaperSource) ?? wallpaperSource
        lockSource = try values.decodeIfPresent(ContentSource.self, forKey: .lockSource) ?? lockSource
        fortuneSource = try values.decodeIfPresent(ContentSource.self, forKey: .fortuneSource) ?? fortuneSource
        themeID = try values.decodeIfPresent(String.self, forKey: .themeID) ?? themeID
        themeMixIDs = try values.decodeIfPresent([String].self, forKey: .themeMixIDs) ?? themeMixIDs
        themeRotation = try values.decodeIfPresent(String.self, forKey: .themeRotation) ?? themeRotation
        watermark = try values.decodeIfPresent(Bool.self, forKey: .watermark) ?? watermark
        haptics = try values.decodeIfPresent(Bool.self, forKey: .haptics) ?? haptics
        streakReminder = try values.decodeIfPresent(Bool.self, forKey: .streakReminder) ?? streakReminder
        showNotificationPreview = try values.decodeIfPresent(Bool.self, forKey: .showNotificationPreview) ?? showNotificationPreview
        onboardingComplete = try values.decodeIfPresent(Bool.self, forKey: .onboardingComplete) ?? onboardingComplete
        mutedWords = try values.decodeIfPresent([String].self, forKey: .mutedWords) ?? mutedWords
        streak = try values.decodeIfPresent(StreakState.self, forKey: .streak) ?? streak
    }
}
