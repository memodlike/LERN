import Foundation
import SwiftData

@Model public final class StoredEntry {
    @Attribute(.unique) public var id: String
    public var text: String
    public var author: String
    public var source: String
    public var tags: [String]
    public var section: String
    public var searchText: String
    public var favorite: Bool
    public var disliked: Bool
    public var muted: Bool
    public var createdAt: Date
    public init(_ value: EntryValue) {
        id = value.id; text = value.draft.text; author = value.draft.author; source = value.draft.source
        tags = value.draft.tags; section = value.draft.section; searchText = value.draft.searchText
        favorite = value.favorite; disliked = value.disliked; muted = value.muted; createdAt = value.createdAt
    }
    public var value: EntryValue {
        var result = EntryValue(draft: EntryDraft(text: text, author: author, source: source, tags: tags, section: section))
        result.id = id; result.favorite = favorite; result.disliked = disliked; result.muted = muted; result.createdAt = createdAt; return result
    }
}
@Model public final class StoredTopic {
    @Attribute(.unique) public var id: String
    public var name: String
    public var kind: String
    public var createdAt: Date
    public init(_ topic: TopicValue) { id = topic.id; name = topic.name; kind = topic.kind; createdAt = Date() }
}
@Model public final class StoredLink {
    @Attribute(.unique) public var id: String
    public var entryID: String
    public var topicID: String
    public var ordinal: Int
    public init(_ value: MembershipValue) { id = value.topicID + ":" + value.entryID; entryID = value.entryID; topicID = value.topicID; ordinal = value.ordinal }
    public var value: MembershipValue { MembershipValue(entryID: entryID, topicID: topicID, ordinal: ordinal) }
}
@Model public final class StoredSetting {
    @Attribute(.unique) public var key: String
    public var data: Data
    public init(key: String, data: Data) { self.key = key; self.data = data }
}
@Model public final class StoredHistory {
    @Attribute(.unique) public var id: String
    public var entryID: String
    public var date: Date
    public var kind: String
    public init(_ value: HistoryValue) { id = value.id; entryID = value.entryID; date = value.date; kind = value.kind }
    public var value: HistoryValue { var v = HistoryValue(entryID: entryID, kind: kind); v.id = id; v.date = date; return v }
}

public enum StorageFactory {
    public static func container(url: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([StoredEntry.self, StoredTopic.self, StoredLink.self, StoredSetting.self, StoredHistory.self])
        let config: ModelConfiguration
        if let url { config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none) }
        else { config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none) }
        return try ModelContainer(for: schema, configurations: [config])
    }
}

public enum ImportAction: String, CaseIterable, Sendable { case new, merge, replace }
public struct ImportResult: Sendable { public var topic: TopicValue; public var inserted: Int; public var duplicates: Int }

@ModelActor public actor LibraryStore {
    private var eligibilityCache: [ContentSource: [String]] = [:]
    private func invalidateSelection() { eligibilityCache.removeAll(keepingCapacity: true) }
    public func get<T: Decodable>(_ key: String, default fallback: T) throws -> T {
        let descriptor = FetchDescriptor<StoredSetting>(predicate: #Predicate { $0.key == key })
        guard let item = try modelContext.fetch(descriptor).first else { return fallback }
        return try JSONDecoder().decode(T.self, from: item.data)
    }
    public func put<T: Encodable>(_ key: String, _ value: T) throws {
        if key == "preferences", let prefs = value as? Preferences {
            let old = try get(key, default: Preferences())
            if prefs.mutedWords != old.mutedWords { invalidateSelection() }
        }
        let data = try JSONEncoder().encode(value)
        let descriptor = FetchDescriptor<StoredSetting>(predicate: #Predicate { $0.key == key })
        if let existing = try modelContext.fetch(descriptor).first { existing.data = data }
        else { modelContext.insert(StoredSetting(key: key, data: data)) }
        try modelContext.save()
    }
    public func entry(_ id: String) throws -> EntryValue? {
        try modelContext.fetch(FetchDescriptor<StoredEntry>(predicate: #Predicate { $0.id == id })).first?.value
    }
    private func storedEntry(_ id: String) throws -> StoredEntry? {
        try modelContext.fetch(FetchDescriptor<StoredEntry>(predicate: #Predicate { $0.id == id })).first
    }
    public func totalCount() throws -> Int { try modelContext.fetchCount(FetchDescriptor<StoredEntry>()) }
    public func topics() throws -> [TopicValue] {
        try modelContext.fetch(FetchDescriptor<StoredTopic>(sortBy: [SortDescriptor(\.createdAt)])).map { topic in
            let id = topic.id
            var value = TopicValue(name: topic.name, kind: topic.kind); value.id = id
            value.count = try modelContext.fetchCount(FetchDescriptor<StoredLink>(predicate: #Predicate { $0.topicID == id }))
            return value
        }
    }
    public func createTopic(name: String, kind: String = "collection") throws -> TopicValue {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportFailure.empty }
        let topic = TopicValue(name: String(trimmed.prefix(120)), kind: kind)
        modelContext.insert(StoredTopic(topic)); try modelContext.save(); return topic
    }
    public func renameTopic(id: String, name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try modelContext.fetch(FetchDescriptor<StoredTopic>(predicate: #Predicate { $0.id == id })).first?.name = String(name.prefix(120))
        try modelContext.save()
    }
    public func deleteTopic(_ id: String) throws {
        invalidateSelection()
        try modelContext.delete(model: StoredLink.self, where: #Predicate { $0.topicID == id })
        try modelContext.delete(model: StoredTopic.self, where: #Predicate { $0.id == id })
        try modelContext.save()
    }
    public func importEntries(_ preview: ImportPreview, action: ImportAction = .new, topicID: String? = nil, splitSections: Bool = false) throws -> ImportResult {
        invalidateSelection()
        modelContext.autosaveEnabled = false
        do {
            var topic: TopicValue
            if action != .new, let topicID, let existing = try topics().first(where: { $0.id == topicID }) { topic = existing }
            else { topic = TopicValue(name: preview.name); modelContext.insert(StoredTopic(topic)) }
            let id = topic.id
            if action == .replace { try modelContext.delete(model: StoredLink.self, where: #Predicate { $0.topicID == id }) }
            let existingLinks = try modelContext.fetch(FetchDescriptor<StoredLink>(predicate: #Predicate { $0.topicID == id }))
            var linked = Set(existingLinks.map(\.entryID))
            var ordinal = (existingLinks.map(\.ordinal).max() ?? -1) + 1, inserted = 0, duplicates = preview.duplicates
            var sectionTopics: [String: String] = [:]
            // Transactions keep cancellation atomic; batches bound query/temporary-object sizes.
            for start in stride(from: 0, to: preview.entries.count, by: 500) {
                try Task.checkCancellation()
                let batch = Array(preview.entries[start..<min(start + 500, preview.entries.count)])
                let ids = batch.map(\.id)
                let found = try modelContext.fetch(FetchDescriptor<StoredEntry>(predicate: #Predicate { ids.contains($0.id) }))
                var known = Set(found.map(\.id))
                for draft in batch {
                    let entryID = draft.id
                    if known.insert(entryID).inserted { modelContext.insert(StoredEntry(EntryValue(draft: draft))); inserted += 1 }
                    else { duplicates += 1 }
                    if linked.insert(entryID).inserted {
                        modelContext.insert(StoredLink(MembershipValue(entryID: entryID, topicID: id, ordinal: ordinal))); ordinal += 1
                    }
                    if splitSections && !draft.section.isEmpty {
                        let sectionID: String
                        if let existing = sectionTopics[draft.section] { sectionID = existing }
                        else { let section = TopicValue(name: "\(topic.name) · \(draft.section)", kind: "section"); sectionID = section.id; sectionTopics[draft.section] = sectionID; modelContext.insert(StoredTopic(section)) }
                        modelContext.insert(StoredLink(MembershipValue(entryID: entryID, topicID: sectionID, ordinal: ordinal)))
                    }
                }
            }
            try Task.checkCancellation(); try modelContext.save(); topic.count = linked.count
            return ImportResult(topic: topic, inserted: inserted, duplicates: duplicates)
        } catch { modelContext.rollback(); throw error }
    }
    public func addOwn(_ draft: EntryDraft, replacing oldID: String? = nil) throws -> EntryValue {
        invalidateSelection()
        guard !draft.text.isEmpty, draft.text.count <= ImportService.textLimit else { throw ImportFailure.empty }
        let own = try topics().first(where: { $0.kind == "own" }) ?? createTopic(name: "My Content", kind: "own")
        if let oldID, oldID != draft.id, let old = try storedEntry(oldID) {
            var value = EntryValue(draft: draft); value.favorite = old.favorite; value.disliked = old.disliked; value.muted = old.muted
            if try storedEntry(value.id) == nil { modelContext.insert(StoredEntry(value)) }
            let links = try modelContext.fetch(FetchDescriptor<StoredLink>(predicate: #Predicate { $0.entryID == oldID }))
            for link in links {
                let v = MembershipValue(entryID: value.id, topicID: link.topicID, ordinal: link.ordinal)
                modelContext.delete(link); modelContext.insert(StoredLink(v))
            }
            let history = try modelContext.fetch(FetchDescriptor<StoredHistory>(predicate: #Predicate { $0.entryID == oldID }))
            for item in history { item.entryID = value.id }
            modelContext.delete(old); try modelContext.save(); return value
        }
        let preview = ImportPreview(name: own.name, format: "manual", entries: [draft], duplicates: 0, malformed: 0, issues: [])
        _ = try importEntries(preview, action: .merge, topicID: own.id)
        return try entry(draft.id) ?? EntryValue(draft: draft)
    }
    public func setFlag(_ id: String, flag: String, value: Bool) throws {
        invalidateSelection()
        guard let item = try storedEntry(id) else { return }
        switch flag { case "favorite": item.favorite = value; case "disliked": item.disliked = value; case "muted": item.muted = value; default: return }
        try modelContext.save()
    }
    public func deleteEntry(_ id: String) throws {
        invalidateSelection()
        try modelContext.delete(model: StoredLink.self, where: #Predicate { $0.entryID == id })
        try modelContext.delete(model: StoredHistory.self, where: #Predicate { $0.entryID == id })
        try modelContext.delete(model: StoredEntry.self, where: #Predicate { $0.id == id }); try modelContext.save()
    }
    public func addToCollection(entryID: String, topicID: String) throws {
        invalidateSelection()
        let key = topicID + ":" + entryID
        guard try modelContext.fetch(FetchDescriptor<StoredLink>(predicate: #Predicate { $0.id == key })).isEmpty else { return }
        let ordinal = try modelContext.fetchCount(FetchDescriptor<StoredLink>(predicate: #Predicate { $0.topicID == topicID }))
        modelContext.insert(StoredLink(MembershipValue(entryID: entryID, topicID: topicID, ordinal: ordinal))); try modelContext.save()
    }
    public func removeFromCollection(entryID: String, topicID: String) throws {
        invalidateSelection()
        let id = topicID + ":" + entryID
        try modelContext.delete(model: StoredLink.self, where: #Predicate { $0.id == id }); try modelContext.save()
    }
    public func reorder(topicID: String, ids: [String]) throws {
        invalidateSelection()
        let links = try modelContext.fetch(FetchDescriptor<StoredLink>(predicate: #Predicate { $0.topicID == topicID }))
        let selected = Set(ids)
        guard selected.count == ids.count else { throw ImportFailure.malformed("Duplicate entries in collection order.") }
        let positions = links.filter { selected.contains($0.entryID) }.map(\.ordinal).sorted()
        guard positions.count == ids.count else { throw ImportFailure.malformed("An entry no longer belongs to this collection.") }
        let order = Dictionary(uniqueKeysWithValues: zip(ids, positions))
        for link in links { if let index = order[link.entryID] { link.ordinal = index } }
        try modelContext.save()
    }
    private func sourceIDs(_ source: ContentSource) throws -> [String]? {
        var topics = source.topicIDs
        if source.myContentOnly { topics += try self.topics().filter { $0.kind == "own" }.map(\.id); if topics.isEmpty { return [] } }
        guard !topics.isEmpty else { return nil }
        let selected = topics
        return try modelContext.fetch(FetchDescriptor<StoredLink>(predicate: #Predicate { selected.contains($0.topicID) }, sortBy: [SortDescriptor(\.ordinal), SortDescriptor(\.id)])).map(\.entryID)
    }
    public func page(source: ContentSource = ContentSource(), search: String = "", offset: Int = 0, limit: Int = 50, review: String = "") throws -> [EntryValue] {
        let ids = try sourceIDs(source).map(Set.init)
        let preferences = try get("preferences", default: Preferences())
        let term = EntryDraft.normalized(search)
        var descriptor = FetchDescriptor<StoredEntry>(sortBy: [SortDescriptor(\.createdAt), SortDescriptor(\.id)])
        if !term.isEmpty { descriptor.predicate = #Predicate { $0.searchText.contains(term) } }
        descriptor.fetchLimit = 500
        var matched = 0, result: [EntryValue] = [], fetchOffset = 0
        while true {
            try Task.checkCancellation(); descriptor.fetchOffset = fetchOffset
            let rows = try modelContext.fetch(descriptor)
            for row in rows {
                if let ids, !ids.contains(row.id) { continue }
                if source.favoritesOnly && !row.favorite { continue }
                if !source.tag.isEmpty && !row.tags.contains(source.tag) && row.section != source.tag { continue }
                if review == "disliked" { if !row.disliked { continue } }
                else if review == "muted" { if !row.muted { continue } }
                else if row.disliked || row.muted || preferences.mutedWords.contains(where: { !$0.isEmpty && row.searchText.contains(EntryDraft.normalized($0)) }) { continue }
                if matched >= offset { result.append(row.value); if result.count >= min(200, max(1, limit)) { return result } }
                matched += 1
            }
            if rows.count < 500 { break }; fetchOffset += 500
        }
        return result
    }
    public func eligibleIDs(source: ContentSource) throws -> [String] {
        if let cached = eligibilityCache[source] { return cached }
        let orderedIDs = try sourceIDs(source), membership = orderedIDs.map(Set.init)
        let prefs = try get("preferences", default: Preferences())
        var descriptor = FetchDescriptor<StoredEntry>(predicate: #Predicate { !$0.disliked && !$0.muted }, sortBy: [SortDescriptor(\.createdAt), SortDescriptor(\.id)])
        descriptor.fetchLimit = 1000
        var result: [String] = [], offset = 0
        while true {
            try Task.checkCancellation(); descriptor.fetchOffset = offset
            let rows = try modelContext.fetch(descriptor)
            for row in rows {
                if let membership, !membership.contains(row.id) { continue }
                if source.favoritesOnly && !row.favorite { continue }
                if !source.tag.isEmpty && !row.tags.contains(source.tag) && row.section != source.tag { continue }
                if prefs.mutedWords.contains(where: { !$0.isEmpty && row.searchText.contains(EntryDraft.normalized($0)) }) { continue }
                result.append(row.id)
            }
            if rows.count < 1000 { break }; offset += 1000
        }
        if let orderedIDs { let eligible = Set(result); var seen = Set<String>(); result = orderedIDs.filter { eligible.contains($0) && seen.insert($0).inserted } }
        if eligibilityCache.count >= 8 { eligibilityCache.removeAll() }
        eligibilityCache[source] = result
        return result
    }
    public func next(source: ContentSource, surface: String, mode: SelectionMode) throws -> EntryValue? {
        let ids = try eligibleIDs(source: source)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(source)
        let key = "cursor." + surface + "." + encoded.base64EncodedString()
        var cursor = try get(key, default: SelectionCursor())
        guard let id = SelectionEngine.next(ids: ids, mode: mode, cursor: &cursor) else { return nil }
        try put(key, cursor); return try entry(id)
    }
    public func record(_ id: String, kind: String) throws {
        modelContext.insert(StoredHistory(HistoryValue(entryID: id, kind: kind))); try modelContext.save()
    }
    public func history(offset: Int = 0) throws -> [HistoryValue] {
        var descriptor = FetchDescriptor<StoredHistory>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 100; descriptor.fetchOffset = offset; return try modelContext.fetch(descriptor).map(\.value)
    }
    public func clearHistory() throws { try modelContext.delete(model: StoredHistory.self); try modelContext.save() }
    public func backup(photos: [String: Data] = [:]) throws -> LibraryBackup {
        let entries = try modelContext.fetch(FetchDescriptor<StoredEntry>()).map(\.value)
        let memberships = try modelContext.fetch(FetchDescriptor<StoredLink>()).map(\.value)
        let history = try modelContext.fetch(FetchDescriptor<StoredHistory>()).map(\.value)
        var cursors: [String: SelectionCursor] = [:]
        for setting in try modelContext.fetch(FetchDescriptor<StoredSetting>()) where setting.key.hasPrefix("cursor.") { cursors[setting.key] = try JSONDecoder().decode(SelectionCursor.self, from: setting.data) }
        return try LibraryBackup(entries: entries, topics: topics(), memberships: memberships, preferences: get("preferences", default: Preferences()), reminders: get("reminders", default: []), themes: get("themes", default: ThemeValue.starters), presets: get("presets", default: []), history: history, resources: get("resources", default: []), cursors: cursors, photos: photos)
    }
    public func restore(_ backup: LibraryBackup, merge: Bool) throws {
        invalidateSelection()
        let data = try backup.validated()
        do {
            if !merge {
                try modelContext.delete(model: StoredLink.self); try modelContext.delete(model: StoredEntry.self)
                try modelContext.delete(model: StoredTopic.self); try modelContext.delete(model: StoredHistory.self); try modelContext.delete(model: StoredSetting.self)
            }
            let existing = merge ? Set(try modelContext.fetch(FetchDescriptor<StoredEntry>()).map(\.id)) : []
            for entry in data.entries where !existing.contains(entry.id) { modelContext.insert(StoredEntry(entry)) }
            let topics = merge ? Set(try self.topics().map(\.id)) : []
            for topic in data.topics where !topics.contains(topic.id) { modelContext.insert(StoredTopic(topic)) }
            let links = merge ? Set(try modelContext.fetch(FetchDescriptor<StoredLink>()).map(\.id)) : []
            for link in data.memberships where !links.contains(link.topicID + ":" + link.entryID) { modelContext.insert(StoredLink(link)) }
            let historyIDs = merge ? Set(try modelContext.fetch(FetchDescriptor<StoredHistory>()).map(\.id)) : []
            for item in data.history where !historyIDs.contains(item.id) { modelContext.insert(StoredHistory(item)) }
            // Merge keeps existing preferences and rules; replacement restores every configuration.
            if !merge {
                let settings: [(String, Data)] = try [("preferences", JSONEncoder().encode(data.preferences)), ("reminders", JSONEncoder().encode(data.reminders)), ("themes", JSONEncoder().encode(data.themes)), ("presets", JSONEncoder().encode(data.presets)), ("resources", JSONEncoder().encode(data.resources))]
                for (key, bytes) in settings { modelContext.insert(StoredSetting(key: key, data: bytes)) }
                for (key, cursor) in data.cursors { modelContext.insert(StoredSetting(key: key, data: try JSONEncoder().encode(cursor))) }
            }
            try Task.checkCancellation(); try modelContext.save()
        } catch { modelContext.rollback(); throw error }
    }
}
