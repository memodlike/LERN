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
    public var status: String?
    public var parentTopicID: String?
    public var originalFilename: String?
    public var format: String?
    public var checksum: String?
    public var updatedAt: Date?
    public var warningCount: Int?
    public init(_ topic: TopicValue) {
        id = topic.id; name = topic.name; kind = topic.kind; createdAt = topic.createdAt
        status = topic.status; parentTopicID = topic.parentTopicID; originalFilename = topic.originalFilename
        format = topic.format; checksum = topic.checksum; updatedAt = topic.updatedAt; warningCount = topic.warningCount
    }
}
@Model public final class StoredLink {
    @Attribute(.unique) public var id: String
    public var entryID: String
    public var topicID: String
    public var ordinal: Int
    public var section: String?
    public var tags: [String]?
    public init(_ value: MembershipValue) { id = value.topicID + ":" + value.entryID; entryID = value.entryID; topicID = value.topicID; ordinal = value.ordinal; section = value.section; tags = value.tags }
    public var value: MembershipValue { MembershipValue(entryID: entryID, topicID: topicID, ordinal: ordinal, section: section ?? "", tags: tags ?? []) }
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
    public func entries(ids: [String]) throws -> [String: EntryValue] {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return [:] }
        let values = try modelContext.fetch(FetchDescriptor<StoredEntry>(predicate: #Predicate { unique.contains($0.id) })).map(\.value)
        return Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
    }
    private func storedEntry(_ id: String) throws -> StoredEntry? {
        try modelContext.fetch(FetchDescriptor<StoredEntry>(predicate: #Predicate { $0.id == id })).first
    }
    public func totalCount() throws -> Int { try modelContext.fetchCount(FetchDescriptor<StoredEntry>()) }
    public func topics() throws -> [TopicValue] {
        let topics = try modelContext.fetch(FetchDescriptor<StoredTopic>(sortBy: [SortDescriptor(\.createdAt)]))
        let counts = Dictionary(grouping: try modelContext.fetch(FetchDescriptor<StoredLink>()), by: \.topicID).mapValues(\.count)
        return topics.map { topic in
            let id = topic.id
            var value = TopicValue(name: topic.name, kind: topic.kind); value.id = id
            value.status = topic.status ?? "active"; value.parentTopicID = topic.parentTopicID
            value.originalFilename = topic.originalFilename; value.format = topic.format; value.checksum = topic.checksum
            value.createdAt = topic.createdAt; value.updatedAt = topic.updatedAt ?? topic.createdAt; value.warningCount = topic.warningCount ?? 0
            value.count = counts[id, default: 0]
            return value
        }
    }
    public func createTopic(name: String, kind: String = "collection") throws -> TopicValue {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportFailure.empty }
        let topic = TopicValue(name: String(trimmed.prefix(120)), kind: kind)
        modelContext.insert(StoredTopic(topic)); try modelContext.save(); return topic
    }
    private func makeOwnTopicIfNeeded(_ own: inout TopicValue?) throws -> TopicValue {
        if let own { return own }
        let created = TopicValue(name: "My Content", kind: "own")
        modelContext.insert(StoredTopic(created))
        own = created
        return created
    }
    /// Removes only entries with no surviving membership. Favorites are retained as user-owned content.
    private func removeOrphans(_ candidateIDs: Set<String>) throws {
        guard !candidateIDs.isEmpty else { return }
        let referenced = Set(try modelContext.fetch(FetchDescriptor<StoredLink>()).map(\.entryID))
        let orphaned = try modelContext.fetch(FetchDescriptor<StoredEntry>()).filter { candidateIDs.contains($0.id) && !referenced.contains($0.id) }
        var own = try topics().first(where: { $0.kind == "own" })
        var ordinal = try own.map { ownTopic in
            try modelContext.fetch(FetchDescriptor<StoredLink>(predicate: #Predicate { $0.topicID == ownTopic.id })).map(\.ordinal).max() ?? -1
        } ?? -1
        for entry in orphaned {
            if entry.favorite {
                let ownTopic = try makeOwnTopicIfNeeded(&own)
                ordinal += 1
                modelContext.insert(StoredLink(MembershipValue(entryID: entry.id, topicID: ownTopic.id, ordinal: ordinal)))
            } else {
                let entryID = entry.id
                try modelContext.delete(model: StoredHistory.self, where: #Predicate { $0.entryID == entryID })
                modelContext.delete(entry)
            }
        }
    }
    public func renameTopic(id: String, name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let topic = try modelContext.fetch(FetchDescriptor<StoredTopic>(predicate: #Predicate { $0.id == id })).first {
            topic.name = String(name.prefix(120)); topic.updatedAt = Date()
        }
        try modelContext.save()
    }
    public func setTopicPaused(_ id: String, paused: Bool) throws {
        guard let topic = try modelContext.fetch(FetchDescriptor<StoredTopic>(predicate: #Predicate { $0.id == id })).first else { return }
        topic.status = paused ? "paused" : "active"; topic.updatedAt = Date(); invalidateSelection(); try modelContext.save()
    }
    public func deleteTopic(_ id: String) throws {
        invalidateSelection()
        try modelContext.delete(model: StoredLink.self, where: #Predicate { $0.topicID == id })
        try modelContext.delete(model: StoredTopic.self, where: #Predicate { $0.id == id })
        try modelContext.save()
    }
    /// Imported libraries own their generated section topics. Favorites without any remaining membership are retained in My Content.
    public func deleteImportedLibrary(_ id: String) throws {
        guard let parent = try modelContext.fetch(FetchDescriptor<StoredTopic>(predicate: #Predicate { $0.id == id })).first else { return }
        let children = try modelContext.fetch(FetchDescriptor<StoredTopic>()).filter { $0.parentTopicID == id }
        let topicIDs = Set(children.map(\.id) + [parent.id])
        let affected = try modelContext.fetch(FetchDescriptor<StoredLink>()).filter { topicIDs.contains($0.topicID) }
        let entryIDs = Set(affected.map(\.entryID))
        for link in affected { modelContext.delete(link) }
        for child in children { modelContext.delete(child) }
        modelContext.delete(parent)
        try removeOrphans(entryIDs)
        invalidateSelection(); try modelContext.save()
    }
    public func importEntries(_ preview: ImportPreview, action: ImportAction = .new, topicID: String? = nil, splitSections: Bool = false) throws -> ImportResult {
        invalidateSelection()
        modelContext.autosaveEnabled = false
        do {
            var topic: TopicValue
            if action != .new, let topicID, let existing = try topics().first(where: { $0.id == topicID }) { topic = existing }
            else { topic = TopicValue(name: preview.name); modelContext.insert(StoredTopic(topic)) }
            let id = topic.id
            if let stored = try modelContext.fetch(FetchDescriptor<StoredTopic>(predicate: #Predicate { $0.id == id })).first {
                stored.updatedAt = Date(); stored.format = preview.format; stored.originalFilename = preview.filename
                stored.checksum = preview.checksum; stored.warningCount = preview.malformed
            }
            var replacedEntryIDs = Set<String>()
            if action == .replace {
                let oldSections = try modelContext.fetch(FetchDescriptor<StoredTopic>()).filter { $0.parentTopicID == id }
                let oldTopicIDs = Set(oldSections.map(\.id) + [id])
                replacedEntryIDs = Set(try modelContext.fetch(FetchDescriptor<StoredLink>()).filter { oldTopicIDs.contains($0.topicID) }.map(\.entryID))
                for section in oldSections {
                    let sectionID = section.id
                    try modelContext.delete(model: StoredLink.self, where: #Predicate { $0.topicID == sectionID })
                    modelContext.delete(section)
                }
                try modelContext.delete(model: StoredLink.self, where: #Predicate { $0.topicID == id })
            }
            let existingLinks = try modelContext.fetch(FetchDescriptor<StoredLink>(predicate: #Predicate { $0.topicID == id }))
            var linked = Set(existingLinks.map(\.entryID))
            let linksByEntry = Dictionary(uniqueKeysWithValues: existingLinks.map { ($0.entryID, $0) })
            var ordinal = (existingLinks.map(\.ordinal).max() ?? -1) + 1, inserted = 0, duplicates = preview.duplicates
            let childTopics = try modelContext.fetch(FetchDescriptor<StoredTopic>()).filter { $0.parentTopicID == id }
            var sectionTopics = Dictionary(uniqueKeysWithValues: childTopics.map { (EntryDraft.normalized($0.name), $0.id) })
            let childIDs = Set(childTopics.map(\.id))
            let childLinks = try modelContext.fetch(FetchDescriptor<StoredLink>()).filter { childIDs.contains($0.topicID) }
            var sectionLinksByEntry = Dictionary(grouping: childLinks, by: \.entryID)
            var sectionOrdinals = Dictionary(uniqueKeysWithValues: childTopics.map { topic in
                (topic.id, childLinks.filter { $0.topicID == topic.id }.map(\.ordinal).max() ?? -1)
            })
            var libraryCount = try modelContext.fetchCount(FetchDescriptor<StoredEntry>())
            // Transactions keep cancellation atomic; batches bound query/temporary-object sizes.
            for start in stride(from: 0, to: preview.entries.count, by: 500) {
                try Task.checkCancellation()
                let batch = Array(preview.entries[start..<min(start + 500, preview.entries.count)])
                let ids = batch.map(\.id)
                let found = try modelContext.fetch(FetchDescriptor<StoredEntry>(predicate: #Predicate { ids.contains($0.id) }))
                var known = Set(found.map(\.id))
                for draft in batch {
                    let entryID = draft.id
                    if known.insert(entryID).inserted {
                        guard action == .replace || libraryCount < DataLimits.entriesInLibrary else { throw ImportFailure.tooLarge }
                        modelContext.insert(StoredEntry(EntryValue(draft: draft))); inserted += 1; libraryCount += 1
                    }
                    else { duplicates += 1 }
                    if linked.insert(entryID).inserted {
                        modelContext.insert(StoredLink(MembershipValue(entryID: entryID, topicID: id, ordinal: ordinal, section: draft.section, tags: draft.tags))); ordinal += 1
                    } else if let link = linksByEntry[entryID] {
                        link.section = draft.section; link.tags = draft.tags
                    }
                    guard splitSections else { continue }
                    let desiredSectionID: String?
                    if draft.section.isEmpty { desiredSectionID = nil }
                    else {
                        let key = EntryDraft.normalized(draft.section)
                        if let existing = sectionTopics[key] { desiredSectionID = existing }
                        else {
                            var section = TopicValue(name: draft.section, kind: "section")
                            section.parentTopicID = id
                            sectionTopics[key] = section.id; sectionOrdinals[section.id] = -1
                            modelContext.insert(StoredTopic(section)); desiredSectionID = section.id
                        }
                    }
                    let currentSectionLinks = sectionLinksByEntry[entryID] ?? []
                    for link in currentSectionLinks where link.topicID != desiredSectionID {
                        modelContext.delete(link)
                    }
                    if let desiredSectionID {
                        if let link = currentSectionLinks.first(where: { $0.topicID == desiredSectionID }) {
                            link.section = draft.section; link.tags = draft.tags
                        } else {
                            let sectionOrdinal = (sectionOrdinals[desiredSectionID] ?? -1) + 1
                            sectionOrdinals[desiredSectionID] = sectionOrdinal
                            let link = StoredLink(MembershipValue(entryID: entryID, topicID: desiredSectionID, ordinal: sectionOrdinal, section: draft.section, tags: draft.tags))
                            modelContext.insert(link)
                            sectionLinksByEntry[entryID, default: []].append(link)
                        }
                    }
                }
            }
            if action == .replace { try removeOrphans(replacedEntryIDs) }
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
            let links = try modelContext.fetch(FetchDescriptor<StoredLink>(predicate: #Predicate { $0.entryID == oldID }))
            let linkedTopicIDs = Set(links.map(\.topicID))
            let sourceManaged = try modelContext.fetch(FetchDescriptor<StoredTopic>()).contains { linkedTopicIDs.contains($0.id) && ($0.kind == "import" || $0.kind == "section") }
            if sourceManaged {
                if try storedEntry(value.id) == nil { modelContext.insert(StoredEntry(value)) }
                let ownID = own.id
                let copyLinkID = ownID + ":" + value.id
                if try modelContext.fetch(FetchDescriptor<StoredLink>(predicate: #Predicate { $0.id == copyLinkID })).isEmpty {
                    let ordinal = (try modelContext.fetch(FetchDescriptor<StoredLink>(predicate: #Predicate { $0.topicID == ownID })).map(\.ordinal).max() ?? -1) + 1
                    modelContext.insert(StoredLink(MembershipValue(entryID: value.id, topicID: ownID, ordinal: ordinal, tags: value.draft.tags)))
                }
                try modelContext.save(); return value
            }
            if try storedEntry(value.id) == nil { modelContext.insert(StoredEntry(value)) }
            for link in links {
                let v = MembershipValue(entryID: value.id, topicID: link.topicID, ordinal: link.ordinal, section: link.section ?? "", tags: link.tags ?? [])
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
        var last = FetchDescriptor<StoredLink>(predicate: #Predicate { $0.topicID == topicID }, sortBy: [SortDescriptor(\.ordinal, order: .reverse)])
        last.fetchLimit = 1
        let ordinal = (try modelContext.fetch(last).first?.ordinal ?? -1) + 1
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
    private func sourceLinks(_ source: ContentSource) throws -> [StoredLink]? {
        var topics = source.topicIDs
        if source.myContentOnly { topics += try self.topics().filter { $0.kind == "own" }.map(\.id); if topics.isEmpty { return [] } }
        guard !topics.isEmpty else { return nil }
        let selected = Set(topics)
        let active = Set(try modelContext.fetch(FetchDescriptor<StoredTopic>()).filter { selected.contains($0.id) && ($0.status ?? "active") != "paused" }.map(\.id))
        // An explicit paused or deleted source stays empty; it never broadens into All Entries.
        guard !active.isEmpty else { return [] }
        return try modelContext.fetch(FetchDescriptor<StoredLink>(predicate: #Predicate { active.contains($0.topicID) }, sortBy: [SortDescriptor(\.ordinal), SortDescriptor(\.id)]))
    }
    private func sourceIDs(_ source: ContentSource) throws -> [String]? {
        try sourceLinks(source)?.map(\.entryID)
    }
    private func matchesSourceMetadata(_ row: StoredEntry, source: ContentSource, links: [String: [StoredLink]]?) -> Bool {
        let tag = EntryDraft.normalized(source.tag)
        guard !tag.isEmpty else { return true }
        guard let links else { return row.tags.contains { EntryDraft.normalized($0) == tag } || EntryDraft.normalized(row.section) == tag }
        return links[row.id, default: []].contains { link in
            EntryDraft.normalized(link.section ?? "") == tag || (link.tags ?? []).contains { EntryDraft.normalized($0) == tag }
        }
    }
    public func page(source: ContentSource = ContentSource(), search: String = "", offset: Int = 0, limit: Int = 50, review: String = "") throws -> [EntryValue] {
        let sourceLinks = try sourceLinks(source)
        let ids = sourceLinks.map { Set($0.map(\.entryID)) }
        let linksByEntry = sourceLinks.map { Dictionary(grouping: $0, by: \.entryID) }
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
                if !matchesSourceMetadata(row, source: source, links: linksByEntry) { continue }
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
        let sourceLinks = try sourceLinks(source)
        let orderedIDs = sourceLinks?.map(\.entryID), membership = orderedIDs.map(Set.init)
        let linksByEntry = sourceLinks.map { Dictionary(grouping: $0, by: \.entryID) }
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
                if !matchesSourceMetadata(row, source: source, links: linksByEntry) { continue }
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
