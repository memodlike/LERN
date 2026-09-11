import Foundation
import CryptoKit

public enum SelectionEngine {
    public static func next(ids: [String], mode: SelectionMode, cursor: inout SelectionCursor, preventImmediateRepeat: Bool = true) -> String? {
        guard !ids.isEmpty else { return nil }
        let fingerprint = SHA256.hash(data: Data(ids.joined(separator: ",").utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        if cursor.fingerprint != fingerprint { cursor.fingerprint = fingerprint; cursor.position = 0; cursor.cycle = 0 }
        let count = ids.count
        if cursor.position < 0 { cursor.position = 0 }
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
        let maximum = max(0, min(capacity, limit))
        guard maximum > 0 else { return [] }
        var candidates: [String: [ReminderSlot]] = [:]
        let activeRuleIDs = Set(rules.filter(\.enabled).map(\.id))
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
                    let slot = ReminderSlot(id: id, ruleID: rule.id, revision: rule.revision, date: date)
                    if !(candidates[rule.id] ?? []).contains(where: { $0.id == id }) { candidates[rule.id, default: []].append(slot) }
                }
            }
            if candidates.count == activeRuleIDs.count && candidates.values.allSatisfy({ $0.count >= maximum }) { break }
        }
        for id in candidates.keys { candidates[id]?.sort { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date } }

        // System slots are conditional product behavior and are never silently starved.
        let systemIDs = candidates.keys.filter(ReminderRule.isReservedID).sorted()
        var selected = systemIDs.compactMap { candidates[$0]?.first }
        if selected.count > maximum { return Array(selected.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }.prefix(maximum)) }

        // Give every active user rule a turn before any rule receives another slot. Each
        // rule stays chronological internally, while the queue stays deterministic.
        var indexes = Dictionary(uniqueKeysWithValues: candidates.keys.map { ($0, ReminderRule.isReservedID($0) ? 1 : 0) })
        while selected.count < maximum {
            let available = indexes.keys.compactMap { id -> (String, ReminderSlot)? in
                guard let index = indexes[id], let slot = candidates[id]?[safe: index] else { return nil }
                return (id, slot)
            }.sorted { lhs, rhs in
                lhs.1.date == rhs.1.date ? lhs.0 < rhs.0 : lhs.1.date < rhs.1.date
            }
            guard !available.isEmpty else { break }
            for (id, slot) in available where selected.count < maximum {
                selected.append(slot)
                indexes[id, default: 0] += 1
            }
        }
        return selected.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
    public static func collisions(_ rules: [ReminderRule], now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Int {
        let slots = slots(rules: rules, after: now, calendar: calendar)
        return Dictionary(grouping: slots, by: \.date).values.reduce(0) { $0 + max(0, $1.count - 1) }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

public struct LibraryBackup: Codable, Sendable {
    /// Keep export and restore on the same compatibility contract.
    public static let maximumSerializedBytes = 500_000_000
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
    public func encodedData() throws -> Data {
        let data = try JSONEncoder().encode(self)
        guard data.count <= Self.maximumSerializedBytes else { throw ImportFailure.tooLarge }
        return data
    }
    public func validated() throws -> Self {
        guard version == 1 else { throw ImportFailure.malformed("Unsupported backup version \(version).") }
        guard entries.count <= DataLimits.entriesInLibrary, topics.count <= DataLimits.topics, memberships.count <= DataLimits.memberships, reminders.count <= DataLimits.reminders, photos.count <= DataLimits.photos else { throw ImportFailure.tooLarge }
        guard Set(entries.map(\.id)).count == entries.count,
              Set(topics.map(\.id)).count == topics.count,
              Set(memberships.map { $0.topicID + ":" + $0.entryID }).count == memberships.count,
              Set(history.map(\.id)).count == history.count
        else { throw ImportFailure.malformed("Duplicate identifiers in backup.") }
        let ids = Set(entries.map(\.id)), topicIDs = Set(topics.map(\.id))
        guard entries.allSatisfy({ !$0.draft.text.isEmpty && $0.draft.text.count <= DataLimits.entryCharacters && $0.draft.author.count <= DataLimits.metadataCharacters && $0.draft.source.count <= DataLimits.metadataCharacters && $0.draft.section.count <= DataLimits.metadataCharacters && $0.draft.tags.count <= DataLimits.tagsPerEntry && $0.draft.tags.allSatisfy({ $0.count <= DataLimits.tagCharacters }) && $0.id == $0.draft.id }),
              topics.allSatisfy({ ["active", "paused"].contains($0.status) && $0.name.count <= DataLimits.topicNameCharacters && ($0.parentTopicID == nil || ($0.parentTopicID != $0.id && topicIDs.contains($0.parentTopicID!))) }),
              memberships.allSatisfy({ ids.contains($0.entryID) && topicIDs.contains($0.topicID) && $0.section.count <= DataLimits.metadataCharacters && $0.tags.count <= DataLimits.tagsPerEntry && $0.tags.allSatisfy({ $0.count <= DataLimits.tagCharacters }) }),
              photos.allSatisfy({ Self.safeAssetName($0.key) && $0.value.count <= DataLimits.photoBytes }) else { throw ImportFailure.malformed("Invalid entries, libraries, links or photo names.") }
        let streak = preferences.streak
        guard (0...1_000_000).contains(streak.current), (0...1_000_000).contains(streak.longest),
              streak.longest >= streak.current, (0...3).contains(streak.freezes), (0...6).contains(streak.readingDaysSinceFreeze),
              themes.count > 0, themes.count <= DataLimits.themes, presets.count <= DataLimits.presets, resources.count <= DataLimits.resources,
              history.count <= DataLimits.history, cursors.count <= DataLimits.cursors,
              preferences.mutedWords.count <= DataLimits.mutedWords, preferences.mutedWords.allSatisfy({ $0.count <= 500 }),
              memberships.allSatisfy({ (0...DataLimits.memberships).contains($0.ordinal) }),
              cursors.allSatisfy({ $0.key.hasPrefix("cursor.") && $0.key.count < DataLimits.entryCharacters && (0...DataLimits.entriesInLibrary).contains($0.value.position) }),
              Set(themes.map(\.id)).count == themes.count, Set(presets.map(\.id)).count == presets.count,
              Set(reminders.map(\.id)).count == reminders.count,
              reminders.allSatisfy({ !ReminderRule.isReservedID($0.id) }),
              themes.allSatisfy({ $0.overlay.isFinite && (0...0.85).contains($0.overlay) && ($0.photoName == nil || Self.safeAssetName($0.photoName!)) }),
              reminders.allSatisfy({ (1...60).contains($0.frequency) && (0..<1440).contains($0.startMinute) && (0..<1440).contains($0.endMinute) && $0.explicitMinutes.count <= 60 && $0.explicitMinutes.allSatisfy({ (0..<1440).contains($0) }) && $0.weekdays.count <= 7 && $0.weekdays.allSatisfy({ (1...7).contains($0) }) && ($0.notificationTopic?.count ?? 0) <= DataLimits.metadataCharacters && ($0.notificationSymbol?.count ?? 0) <= 16 && ($0.notificationTint?.count ?? 0) <= 7 }),
              presets.allSatisfy({ (30...1440).contains($0.refreshMinutes) }),
              photos.values.reduce(Int64(0), { $0 + Int64($1.count) }) <= Int64(DataLimits.totalPhotoBytes)
        else { throw ImportFailure.malformed("Backup settings contain invalid counters, dates or limits.") }
        if let lastDay = streak.lastDay, !lastDay.timeIntervalSince1970.isFinite { throw ImportFailure.malformed("Invalid streak date.") }
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
    public var section = ""
    public var tags: [String] = []
    public init(entryID: String, topicID: String, ordinal: Int, section: String = "", tags: [String] = []) { self.entryID = entryID; self.topicID = topicID; self.ordinal = ordinal; self.section = section; self.tags = EntryDraft.normalizedTags(tags) }
    private enum CodingKeys: String, CodingKey { case entryID, topicID, ordinal, section, tags }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        entryID = try values.decode(String.self, forKey: .entryID); topicID = try values.decode(String.self, forKey: .topicID); ordinal = try values.decode(Int.self, forKey: .ordinal)
        section = try values.decodeIfPresent(String.self, forKey: .section) ?? ""
        tags = EntryDraft.normalizedTags(try values.decodeIfPresent([String].self, forKey: .tags) ?? [])
    }
}
