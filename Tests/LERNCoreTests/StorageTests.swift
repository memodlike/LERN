import Testing
import Foundation
@testable import LERNCore

@Suite(.serialized) struct StorageTests {
    func store() throws -> LibraryStore { LibraryStore(modelContainer: try StorageFactory.container(inMemory: true)) }
    func preview(_ texts: [String]) -> ImportPreview { ImportPreview(name: "Test", format: "TXT", entries: texts.map { EntryDraft(text: $0) }, duplicates: 0, malformed: 0, issues: []) }
    @Test func persistenceAndIsolation() async throws {
        let store = try store(); let imported = try await store.importEntries(preview(["one", "two", "three"]))
        let source = ContentSource(topicIDs: [imported.topic.id])
        #expect(try await store.next(source: source, surface: "feed", mode: .sequential)?.draft.text == "one")
        #expect(try await store.next(source: source, surface: "feed", mode: .sequential)?.draft.text == "two")
        #expect(try await store.next(source: source, surface: "reminder", mode: .sequential)?.draft.text == "one")
        try await store.setFlag(EntryDraft(text: "one").id, flag: "favorite", value: true)
        let reimport = try await store.importEntries(preview(["one", "four"]), action: .replace, topicID: imported.topic.id)
        #expect(reimport.duplicates == 1)
        #expect(try await store.entry(EntryDraft(text: "one").id)?.favorite == true)
        #expect(try await store.eligibleIDs(source: source).count == 2)
    }
    @Test func exclusionSearchCollectionsAndBackup() async throws {
        let store = try store(); _ = try await store.importEntries(preview(["keep me", "mute this word", "dislike me"]))
        try await store.setFlag(EntryDraft(text: "dislike me").id, flag: "disliked", value: true)
        var prefs = Preferences(); prefs.mutedWords = ["this word"]; try await store.put("preferences", prefs)
        #expect(try await store.eligibleIDs(source: ContentSource()).count == 1)
        #expect(try await store.page(search: "keep").count == 1)
        let topic = try await store.createTopic(name: "Favorites to read")
        try await store.addToCollection(entryID: EntryDraft(text: "keep me").id, topicID: topic.id)
        #expect(try await store.page(source: ContentSource(topicIDs: [topic.id])).count == 1)
        let own = try await store.addOwn(EntryDraft(text: "my own"))
        #expect(try await store.page(source: ContentSource(myContentOnly: true)).first?.id == own.id)
        let backup = try await store.backup(); let restored = try self.store()
        try await restored.restore(backup, merge: false)
        #expect(try await restored.totalCount() == 4)
        #expect(try await restored.get("preferences", default: Preferences()).mutedWords == ["this word"])
        try await restored.restore(backup, merge: true); #expect(try await restored.totalCount() == 4)
        var invalid = backup; invalid.version = 500
        #expect(throws: (any Error).self) { try invalid.validated() }
        invalid = backup; invalid.photos = ["../../escape": Data()]
        #expect(throws: (any Error).self) { try invalid.validated() }
    }
    @Test func partialCollectionReorderPreservesOtherPositions() async throws {
        let store = try store()
        let imported = try await store.importEntries(preview(["zero", "one", "two", "three"]))
        let topic = imported.topic.id
        let ids = ["zero", "one", "two", "three"].map { EntryDraft(text: $0).id }
        try await store.reorder(topicID: topic, ids: [ids[3], ids[1]])
        #expect(try await store.eligibleIDs(source: ContentSource(topicIDs: [topic])) == [ids[0], ids[3], ids[2], ids[1]])
        try await store.removeFromCollection(entryID: ids[2], topicID: topic)
        let extra = try await store.addOwn(EntryDraft(text: "extra"))
        try await store.addToCollection(entryID: extra.id, topicID: topic)
        #expect(try await store.eligibleIDs(source: ContentSource(topicIDs: [topic])).last == extra.id)
    }
    @Test func largeLibraryBenchmark() async throws {
        guard ProcessInfo.processInfo.environment["LERN_LARGE_TEST"] == "1" else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try StorageFactory.container(url: directory.appendingPathComponent("benchmark.store"))
        let library = LibraryStore(modelContainer: container)
        let start = Date()
        for part in 0..<2 {
            let text = (0..<50_000).map { "Entry \(part * 50_000 + $0) with local searchable words" }.joined(separator: "\n")
            let preview = try ImportService().preview(data: Data(text.utf8), filename: "batch\(part).txt", mode: .lines)
            _ = try await library.importEntries(preview)
        }
        #expect(try await library.totalCount() == 100_000)
        let searchStart = Date(); let result = try await library.page(search: "Entry 99999")
        #expect(result.count == 1)
        print("BENCHMARK storage_100k_seconds=\(Date().timeIntervalSince(start)) search_seconds=\(Date().timeIntervalSince(searchStart))")
    }
}

struct BackupSafetyTests {
    @Test func rejectsDangerousState() async throws {
        let store = LibraryStore(modelContainer: try StorageFactory.container(inMemory: true))
        _ = try await store.addOwn(EntryDraft(text: "valid"))
        let backup = try await store.backup()
        var bad = backup; bad.preferences.streak.readingDaysSinceFreeze = Int.max
        #expect(throws: (any Error).self) { try bad.validated() }
        bad = backup; var cursor = SelectionCursor(); cursor.position = -1; bad.cursors["cursor.feed"] = cursor
        #expect(throws: (any Error).self) { try bad.validated() }
        bad = backup; bad.themes = []
        #expect(throws: (any Error).self) { try bad.validated() }
        bad = backup; bad.memberships[0].ordinal = Int.max
        #expect(throws: (any Error).self) { try bad.validated() }
    }
    @Test func useSitesRecoverInvalidCounters() {
        var streak = StreakState(); streak.readingDaysSinceFreeze = Int.max; streak.current = Int.max; streak.freezes = Int.max
        streak.read(on: Date()); #expect(streak.readingDaysSinceFreeze == 0); #expect(streak.freezes == 3)
        var cursor = SelectionCursor(); cursor.position = -1
        #expect(SelectionEngine.next(ids: ["one"], mode: .sequential, cursor: &cursor) == "one")
    }
    @Test func parsersRejectOverLimit() {
        let lines = String(repeating: "x\n", count: 100_001)
        #expect(throws: (any Error).self) { try PlainTextImporter().parse(lines, mode: .lines) }
        #expect(throws: (any Error).self) { try DelimitedImporter().parse(lines, mode: .lines) }
        let nested = String(repeating: "[", count: 40) + "0" + String(repeating: "]", count: 40)
        #expect(throws: (any Error).self) { try JSONImporter().parse(nested, mode: .automatic) }
    }
}
