import Foundation
import CryptoKit

public enum SelectionEngine {
    public static func next(ids: [String], mode: SelectionMode, cursor: inout SelectionCursor, preventImmediateRepeat: Bool = true) -> String? {
        guard !ids.isEmpty else { return nil }
        let fingerprint = SHA256.hash(data: Data(ids.joined(separator: ",").utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        if cursor.fingerprint != fingerprint { cursor.fingerprint = fingerprint; cursor.position = 0; cursor.cycle = 0 }
        let count = ids.count
        if cursor.position >= count { cursor.position = 0; cursor.cycle &+= 1 }
        let index: Int
        switch mode {
        case .sequential: index = cursor.position
        case .shuffle:
            // An affine permutation is a bijection for every library size, persisted in O(1) space.
            let seed = mix(cursor.seed &+ cursor.cycle)
            var step = Int(seed % UInt64(count)) + 1
            while gcd(step, count) != 1 { step = step % count + 1 }
            let offset = Int(mix(seed) % UInt64(count))
            index = (step * cursor.position + offset) % count
        case .random:
            var selected = Int.random(in: 0..<count)
            if preventImmediateRepeat && count > 1 && ids[selected] == cursor.lastID { selected = (selected + Int.random(in: 1..<count)) % count }
            index = selected
        }
        cursor.position += 1; cursor.lastID = ids[index]
        return ids[index]
    }
    private static func gcd(_ a: Int, _ b: Int) -> Int { var x = a, y = b; while y != 0 { (x, y) = (y, x % y) }; return x }
    private static func mix(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

public struct ReminderSlot: Sendable, Equatable {
    public let id: String
    public let ruleID: String
    public let revision: String
    public let date: Date
}
public enum ScheduleEngine {
    public static let capacity = 60
    public static func slots(rules: [ReminderRule], after now: Date, calendar: Calendar = .autoupdatingCurrent, limit: Int = capacity) -> [ReminderSlot] {
        var result: [ReminderSlot] = []
        let day = calendar.startOfDay(for: now)
        for offset in 0..<370 {
            guard let currentDay = calendar.date(byAdding: .day, value: offset, to: day) else { continue }
            let weekday = calendar.component(.weekday, from: currentDay)
            for rule in rules where rule.enabled && rule.weekdays.contains(weekday) {
                for minute in rule.minutes {
                    // nextDate with nextTime shifts a spring DST gap forward, first chooses one autumn occurrence.
                    var match = DateComponents(); match.hour = minute / 60; match.minute = minute % 60; match.second = 0
                    guard let date = calendar.nextDate(after: currentDay.addingTimeInterval(-1), matching: match, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward), calendar.isDate(date, inSameDayAs: currentDay), date > now else { continue }
                    let id = "lern.\(rule.id).\(Int(date.timeIntervalSince1970))"
                    if !result.contains(where: { $0.id == id }) { result.append(ReminderSlot(id: id, ruleID: rule.id, revision: rule.revision, date: date)) }
                }
            }
            if result.count >= limit { break }
        }
        return Array(result.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }.prefix(max(0, min(capacity, limit))))
    }
    public static func collisions(_ rules: [ReminderRule], now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Int {
        let slots = slots(rules: rules, after: now, calendar: calendar)
        return Dictionary(grouping: slots, by: \.date).values.reduce(0) { $0 + max(0, $1.count - 1) }
    }
}

public struct LibraryBackup: Codable, Sendable {
    public var version = 1
    public var createdAt = Date()
    public var entries: [EntryValue]
    public var topics: [TopicValue]
    public var memberships: [MembershipValue]
    public var preferences: Preferences
    public var reminders: [ReminderRule]
    public var themes: [ThemeValue]
    public var presets: [WidgetPreset]
    public var history: [HistoryValue]
    public var resources: [ResourceBook]
    public var cursors: [String: SelectionCursor]
    public var photos: [String: Data]
    public func validated() throws -> Self {
        guard version == 1 else { throw ImportFailure.malformed("Unsupported backup version \(version).") }
        guard entries.count <= 200_000, topics.count <= 10_000, memberships.count <= 1_000_000, reminders.count <= 100, photos.count <= 200 else { throw ImportFailure.tooLarge }
        guard Set(entries.map(\.id)).count == entries.count, Set(topics.map(\.id)).count == topics.count else { throw ImportFailure.malformed("Duplicate identifiers in backup.") }
        let ids = Set(entries.map(\.id)), topicIDs = Set(topics.map(\.id))
        guard entries.allSatisfy({ $0.id == $0.draft.id && !$0.draft.text.isEmpty && $0.draft.text.count <= ImportService.textLimit }), memberships.allSatisfy({ ids.contains($0.entryID) && topicIDs.contains($0.topicID) }), photos.allSatisfy({ Self.safeAssetName($0.key) && $0.value.count <= 20_000_000 }) else { throw ImportFailure.malformed("Invalid entries, links or photo names.") }
        return self
    }
    public static func safeAssetName(_ value: String) -> Bool {
        !value.isEmpty && value.count < 120 && value != "." && value != ".." && value.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.")).contains($0) }
    }
}
public struct MembershipValue: Codable, Sendable {
    public var entryID: String
    public var topicID: String
    public var ordinal: Int
    public init(entryID: String, topicID: String, ordinal: Int) { self.entryID = entryID; self.topicID = topicID; self.ordinal = ordinal }
}
