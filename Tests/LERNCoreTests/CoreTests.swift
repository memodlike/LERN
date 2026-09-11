import Testing
import Foundation
@testable import LERNCore

struct ImporterTests {
    func parse(_ text: String, _ ext: String, mode: TextImportMode = .automatic) throws -> ImportPreview { try ImportService().preview(data: Data(text.utf8), filename: "test." + ext, mode: mode) }
    @Test func markdownStructures() throws {
        let result = try parse("---\nauthor: Ada\ntags: [focus, calm]\n---\n# Focus\n- One\n* Two\n1. Three\n> Four\n> Five\n\nA paragraph\ncontinued.\n\nNext paragraph.", "md")
        #expect(result.entries.count == 7)
        #expect(result.entries[0].section == "Focus")
        #expect(result.entries[0].author == "Ada")
        #expect(result.entries[0].tags == ["focus", "calm"])
        #expect(result.entries[5].text == "A paragraph\ncontinued.")
    }
    @Test func textLayouts() throws {
        #expect(try parse("one\ntwo\n\nthree", "txt").entries.count == 2)
        #expect(try parse("one\ntwo\n\nthree", "txt", mode: .lines).entries.count == 3)
        #expect(try parse("one\ntwo", "txt", mode: .paragraphs).entries.count == 1)
    }
    @Test func csvQuoting() throws {
        let result = try parse("\u{FEFF}quote,author,tags\n\"Hello, world\",Ada,focus\n\"Say \"\"yes\"\"\",Lin,calm\n\"A\nB\",Sam,", "csv")
        #expect(result.entries.count == 3)
        #expect(result.entries[0].text == "Hello, world")
        #expect(result.entries[1].text == "Say \"yes\"")
        #expect(result.entries[2].text == "A\nB")
    }
    @Test func csvWithoutHeaderAndTSV() throws {
        #expect(try parse("one\ntwo", "csv").entries.count == 2)
        #expect(try parse("text\tauthor\none\tAda", "tsv").entries.first?.author == "Ada")
    }
    @Test func jsonFormats() throws {
        #expect(try parse("[\"one\",\"two\"]", "json").entries.count == 2)
        let result = try parse("[{\"body\":\"Привет\",\"author\":\"Ада\",\"tags\":[\"фокус\"]},{\"wrong\":1}]", "json")
        #expect(result.entries.first?.text == "Привет")
        #expect(result.malformed == 1)
        #expect(try parse("\"one\"\n{\"content\":\"two\"}\nbroken", "jsonl").malformed == 1)
    }
    @Test func csvHeaderlessAliasFirstRow() throws {
        let automatic = try ImportService().preview(data: Data("text\nnext".utf8), filename: "thoughts.csv")
        #expect(automatic.entries.map(\.text) == ["text", "next"])
        #expect(automatic.detectedHeader == .ambiguous)
        let present = try ImportService().preview(data: Data("text\na".utf8), filename: "thoughts.csv", headerMode: .present)
        #expect(present.entries.map(\.text) == ["a"])
        let absent = try ImportService().preview(data: Data("text\na".utf8), filename: "thoughts.csv", headerMode: .absent)
        #expect(absent.entries.map(\.text) == ["text", "a"])
    }
    @Test func csvDelimiterAmbiguityAndRaggedRowsWarn() throws {
        let semicolon = try ImportService().preview(data: Data("text;author\nPrice 3,14;Ada".utf8), filename: "thoughts.csv")
        #expect(semicolon.detectedDelimiter == .semicolon)
        #expect(semicolon.entries.first?.author == "Ada")
        let ambiguous = try ImportService().preview(data: Data("one\ntwo".utf8), filename: "thoughts.csv")
        #expect(ambiguous.issues.contains { $0.localizedCaseInsensitiveContains("delimiter detection is ambiguous") })
        let ragged = try ImportService().preview(data: Data("text,author,source\nOne,Ada\nTwo,Ada,Site,extra".utf8), filename: "thoughts.csv")
        #expect(ragged.entries.count == 2)
        #expect(ragged.issues.contains { $0.contains("too few columns") })
        #expect(ragged.issues.contains { $0.contains("too many columns") })
    }
    @Test func csvDuplicateHeadersAreRejected() {
        #expect(throws: (any Error).self) {
            try ImportService().preview(data: Data("text,TEXT\none,two".utf8), filename: "thoughts.csv", headerMode: .present)
        }
    }
    @Test func jsonKeyCaseContractAndBlankJSONLLines() throws {
        let mixed = try ImportService().preview(data: Data(#"[{"Text":"One","AUTHOR":"Ada"}]"#.utf8), filename: "thoughts.json")
        #expect(mixed.entries.first?.author == "Ada")
        let collision = try ImportService().preview(data: Data(#"[{"text":"One","Text":"Two"},{"text":"Safe"}]"#.utf8), filename: "thoughts.json")
        #expect(collision.issues.contains { $0.localizedCaseInsensitiveContains("duplicate keys") })
        let lines = try ImportService().preview(data: Data("\n{\"text\":\"One\"}\n\nbroken".utf8), filename: "thoughts.jsonl")
        #expect(lines.entries.map(\.text) == ["One"])
        #expect(lines.issues == ["Line 4: invalid JSON."])
    }
    @Test func markdownTildeFenceRemainsLiteral() throws {
        let preview = try ImportService().preview(data: Data("~~~swift\n# not a heading\n~~~\n# Heading\nThought".utf8), filename: "thoughts.md")
        #expect(preview.entries.contains { $0.text.contains("# not a heading") && $0.section.isEmpty })
        #expect(preview.entries.contains { $0.text == "Thought" && $0.section == "Heading" })
    }
    @Test func malformedAndEmpty() {
        #expect(throws: (any Error).self) { try parse("", "txt") }
        #expect(throws: (any Error).self) { try parse("{", "json") }
        #expect(throws: (any Error).self) { try parse("\"unclosed", "csv") }
        #expect(throws: (any Error).self) { try parse("abc", "exe") }
        #expect(throws: (any Error).self) { try ImportService().preview(data: Data([0xFF, 0xFE]), filename: "bad.txt") }
    }
    @Test func identityAndDuplicates() throws {
        let result = try parse("Hello   world\nhello world\nHELLO WORLD", "txt")
        #expect(result.entries.count == 1); #expect(result.duplicates == 2)
        #expect(EntryDraft(text: "a", author: "b|c").id != EntryDraft(text: "a|b", author: "c").id)
        #expect(EntryDraft(text: "é").id == EntryDraft(text: "e\u{301}").id)
    }
    @Test func embeddedCodeIsInert() throws {
        let result = try parse("<script>alert('x')</script>\n\n```js\nmalicious()\n```", "md")
        #expect(result.entries.count == 2)
        #expect(result.entries[0].text.contains("<script>"))
        #expect(result.entries[1].text.contains("malicious()"))
    }
    @Test func markdownHeadingsAndCSVMetadata() throws {
        let markdown = try parse("# Valid section\n- First\n#hashtag\n```swift\n# not a heading\n```", "md")
        #expect(markdown.entries[0].section == "Valid section")
        #expect(markdown.entries[1].text.contains("#hashtag"))
        #expect(markdown.entries[1].text.contains("# not a heading"))
        let csv = try ImportService().preview(data: Data("quote;tags;category\nHello;a | b, b;Ideas".utf8), filename: "notes.csv")
        #expect(csv.detectedDelimiter == .semicolon)
        #expect(csv.entries[0].tags == ["a", "b", "b"])
        #expect(csv.entries[0].section == "Ideas")
    }
    @Test func jsonSectionTakesPriorityOverCategory() throws {
        let json = try parse("[{\"text\":\"One\",\"section\":\"Strategy\",\"category\":\"Legacy\"}]", "json")
        let jsonl = try parse("{\"text\":\"Two\",\"section\":\"Focus\"}", "jsonl")
        #expect(json.entries[0].section == "Strategy")
        #expect(jsonl.entries[0].section == "Focus")
    }
    @Test func fiftyThousandParse() throws {
        let text = (0..<50_000).map { "Thought number \($0) — привет" }.joined(separator: "\n")
        let start = Date(); let preview = try parse(text, "txt", mode: .lines)
        #expect(preview.entries.count == 50_000)
        print("BENCHMARK parser_50k_seconds=\(Date().timeIntervalSince(start))")
    }
}
struct SelectionTests {
    @Test func sequentialWrapAndPersistence() throws {
        var cursor = SelectionCursor(); let ids = ["a", "b", "c"]
        #expect(SelectionEngine.next(ids: ids, mode: .sequential, cursor: &cursor) == "a")
        cursor = try JSONDecoder().decode(SelectionCursor.self, from: JSONEncoder().encode(cursor))
        #expect(SelectionEngine.next(ids: ids, mode: .sequential, cursor: &cursor) == "b")
        _ = SelectionEngine.next(ids: ids, mode: .sequential, cursor: &cursor)
        #expect(SelectionEngine.next(ids: ids, mode: .sequential, cursor: &cursor) == "a")
    }
    @Test(arguments: [1, 2, 7, 16, 97, 1000]) func shuffleNoRepeat(count: Int) {
        let ids = (0..<count).map(String.init); var cursor = SelectionCursor()
        for _ in 0..<2 { let cycle = (0..<count).compactMap { _ in SelectionEngine.next(ids: ids, mode: .shuffle, cursor: &cursor) }; #expect(Set(cycle).count == count) }
    }
    @Test func randomAndDeletion() {
        var cursor = SelectionCursor()
        for _ in 0..<100 { #expect(["a", "b"].contains(SelectionEngine.next(ids: ["a", "b"], mode: .random, cursor: &cursor)!)) }
        #expect(SelectionEngine.next(ids: ["b"], mode: .shuffle, cursor: &cursor) == "b")
        #expect(SelectionEngine.next(ids: [], mode: .shuffle, cursor: &cursor) == nil)
    }
}
struct WatchPayloadTests {
    @Test func acceptsLegacyAndCurrentPayloadsButRejectsUnknownVersions() throws {
        let entry = EntryValue(draft: EntryDraft(text: "A watch thought"))
        let data = try JSONEncoder().encode([entry])
        #expect(WatchPayload.decodeEntries(data, version: nil) == [entry])
        #expect(WatchPayload.decodeEntries(data, version: WatchPayload.schemaVersion) == [entry])
        #expect(WatchPayload.decodeEntries(data, version: WatchPayload.schemaVersion + 1) == nil)
    }
    @Test func rejectsDuplicateAndOversizedPayloads() throws {
        let entry = EntryValue(draft: EntryDraft(text: "Duplicate"))
        let duplicateData = try JSONEncoder().encode([entry, entry])
        #expect(WatchPayload.decodeEntries(duplicateData, version: WatchPayload.schemaVersion) == nil)
        #expect(WatchPayload.decodeEntries(Data("not a payload".utf8), version: WatchPayload.schemaVersion) == nil)
        let entries = (0...WatchPayload.maximumEntries).map { EntryValue(draft: EntryDraft(text: "Thought \($0)")) }
        let oversizedData = try JSONEncoder().encode(entries)
        #expect(WatchPayload.decodeEntries(oversizedData, version: WatchPayload.schemaVersion) == nil)
    }
}
struct ScheduleTests {
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    @Test func boundedAndStable() {
        var a = ReminderRule(); a.explicitMinutes = [540, 600, 700]; var b = ReminderRule(); b.explicitMinutes = [540]
        let now = date("2026-09-06T00:00:00Z")
        let slots = ScheduleEngine.slots(rules: [a, b], after: now, calendar: utc)
        #expect(slots.count == 60)
        #expect(slots == ScheduleEngine.slots(rules: [a, b], after: now, calendar: utc))
        #expect(zip(slots, slots.dropFirst()).allSatisfy { $0.date <= $1.date })
        #expect(ScheduleEngine.collisions([a, b], now: now, calendar: utc) > 0)
    }
    @Test func rangeAndWeekday() {
        var rule = ReminderRule(); rule.usesRange = true; rule.frequency = 3; rule.startMinute = 420; rule.endMinute = 1320; rule.weekdays = [2, 3, 4, 5, 6]
        #expect(rule.minutes == [420, 870, 1320])
        let slots = ScheduleEngine.slots(rules: [rule], after: date("2026-09-05T23:59:00Z"), calendar: utc)
        #expect(slots.allSatisfy { (2...6).contains(utc.component(.weekday, from: $0.date)) })
    }
    @Test func dstAndTimezone() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        var rule = ReminderRule(); rule.explicitMinutes = [150]
        let slots = ScheduleEngine.slots(rules: [rule], after: date("2026-03-08T05:00:00Z"), calendar: calendar)
        #expect(calendar.component(.hour, from: slots[0].date) == 3)
        rule.explicitMinutes = [90]
        let fall = ScheduleEngine.slots(rules: [rule], after: date("2026-11-01T04:00:00Z"), calendar: calendar)
        #expect(fall.filter { calendar.isDate($0.date, inSameDayAs: date("2026-11-01T12:00:00Z")) }.count == 1)
        #expect(fall[0].date != ScheduleEngine.slots(rules: [rule], after: date("2026-11-01T04:00:00Z"), calendar: utc)[0].date)
    }
    @Test func editsAndDisabled() {
        var rule = ReminderRule(); let now = date("2026-09-06T00:00:00Z")
        let original = ScheduleEngine.slots(rules: [rule], after: now, calendar: utc)
        rule.explicitMinutes = [700]; rule.revision = "changed"
        #expect(ScheduleEngine.slots(rules: [rule], after: now, calendar: utc) != original)
        rule.enabled = false; #expect(ScheduleEngine.slots(rules: [rule], after: now).isEmpty)
    }
    @Test func fairAllocationProtectsEveryGroupAndSystemSlots() {
        let now = date("2026-09-06T00:00:00Z")
        var busy = ReminderRule(); busy.id = "busy"; busy.explicitMinutes = Array(stride(from: 0, to: 1440, by: 15)); busy.revision = "busy"
        var quiet = ReminderRule(); quiet.id = "quiet"; quiet.explicitMinutes = [600]; quiet.revision = "quiet"
        var streak = ReminderRule(); streak.id = "system.streak"; streak.explicitMinutes = [1200]; streak.revision = "streak"
        let rules = [busy, quiet, streak]
        let first = ScheduleEngine.slots(rules: rules, after: now, calendar: utc)
        #expect(first.count == ScheduleEngine.capacity)
        #expect(first.contains(where: { $0.ruleID == "quiet" }))
        #expect(first.contains(where: { $0.ruleID == "system.streak" }))
        #expect(first == ScheduleEngine.slots(rules: rules, after: now, calendar: utc))
        let grouped = Dictionary(grouping: first.filter { $0.ruleID == "busy" }, by: \.ruleID)
        #expect(grouped["busy"]?.map(\.date) == grouped["busy"]?.map(\.date).sorted())
    }
    @Test func backupRejectsSystemReminderIdentifiers() throws {
        var rule = ReminderRule(); rule.id = "system.streak"
        let backup = LibraryBackup(entries: [], topics: [], memberships: [], preferences: Preferences(), reminders: [rule], themes: ThemeValue.starters, presets: [], history: [], resources: [], cursors: [:], photos: [:])
        #expect(throws: (any Error).self) { try backup.validated() }
    }
    @Test func olderPreferencesDefaultToVisibleNotificationPreviews() throws {
        let decoded = try JSONDecoder().decode(Preferences.self, from: Data("{\"name\":\"Ada\"}".utf8))
        #expect(decoded.name == "Ada")
        #expect(decoded.showNotificationPreview)
    }
    @Test func olderPreferencesKeepWallpaperLinkedToAppTheme() throws {
        let legacy = try JSONDecoder().decode(Preferences.self, from: Data("{\"themeID\":\"starter-2\"}".utf8))
        #expect(legacy.wallpaperUsesAppTheme)
        #expect(legacy.wallpaperThemeID.isEmpty)
        #expect(legacy.wallpaperOverlay == nil)
        #expect(legacy.wallpaperBlur == 0)
        var configured = Preferences(); configured.wallpaperUsesAppTheme = false; configured.wallpaperThemeID = "starter-3"; configured.wallpaperPhotoName = "wallpaper.jpg"; configured.wallpaperOverlay = 0.45; configured.wallpaperBlur = 8; configured.wallpaperFocalX = 0.2; configured.wallpaperFocalY = 0.8
        let roundTrip = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(configured))
        #expect(roundTrip.wallpaperUsesAppTheme == false)
        #expect(roundTrip.wallpaperThemeID == "starter-3")
        #expect(roundTrip.wallpaperPhotoName == "wallpaper.jpg")
        #expect(roundTrip.wallpaperOverlay == 0.45)
        #expect(roundTrip.wallpaperBlur == 8)
        #expect(roundTrip.wallpaperFocalX == 0.2)
        #expect(roundTrip.wallpaperFocalY == 0.8)
    }
    @Test func notificationTitleModeNormalizesPersistedValues() throws {
        func decode(_ value: String?) throws -> ReminderRule {
            let data = value.map { Data("{\"notificationTitleMode\":\"\($0)\"}".utf8) } ?? Data("{}".utf8)
            return try JSONDecoder().decode(ReminderRule.self, from: data)
        }
        #expect(try decode("topic").notificationTitleMode == .topic)
        #expect(try decode("SECTION").notificationTitleMode == .section)
        #expect(try decode("none").notificationTitleMode == .none)
        #expect(try decode("").notificationTitleMode == .topic)
        #expect(try decode("custom").notificationTitleMode == .topic)
        #expect(try decode("future-mode").notificationTitleMode == .topic)
        #expect(try decode(nil).notificationTitleMode == .topic)
        var rule = ReminderRule(); rule.notificationTitleMode = .section
        #expect(String(decoding: try JSONEncoder().encode(rule), as: UTF8.self).contains("\"notificationTitleMode\":\"section\""))
    }
    @Test func legacyNotificationTintStillDecodes() throws {
        let rule = try JSONDecoder().decode(ReminderRule.self, from: Data("{\"notificationTint\":\"#BADA55\"}".utf8))
        #expect(rule.notificationTint == "#BADA55")
    }
}
struct StreakTests {
    @Test func streakFreezeAndRegeneration() {
        var s = StreakState(); let c = Calendar(identifier: .gregorian); let start = c.startOfDay(for: Date())
        s.read(on: start, calendar: c); s.read(on: start, calendar: c); #expect(s.current == 1)
        s.read(on: c.date(byAdding: .day, value: 1, to: start)!, calendar: c); #expect(s.current == 2)
        s.read(on: c.date(byAdding: .day, value: 3, to: start)!, calendar: c); #expect(s.current == 3); #expect(s.freezes == 2)
        for day in 4...8 { s.read(on: c.date(byAdding: .day, value: day, to: start)!, calendar: c) }
        #expect(s.freezes == 3)
        s.read(on: c.date(byAdding: .day, value: 20, to: start)!, calendar: c); #expect(s.current == 1)
        s.enabled = false; s.read(on: c.date(byAdding: .day, value: 21, to: start)!, calendar: c); #expect(s.current == 1)
    }
    @Test func widgetSerialization() throws {
        var a = WidgetPreset(); a.source = ContentSource(topicIDs: ["a"], favoritesOnly: true); a.border = true; a.themeID = "starter-2"
        #expect(try JSONDecoder().decode(WidgetPreset.self, from: JSONEncoder().encode(a)) == a)
    }
}
