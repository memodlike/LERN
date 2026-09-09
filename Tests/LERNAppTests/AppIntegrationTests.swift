import XCTest
import SwiftUI
import LERNCore
@testable import LERN

@MainActor private final class FakeNotificationCenter: NotificationCenterClient {
    var snapshot = NotificationSettingsSnapshot(authorization: .authorized, alerts: "enabled", sounds: "enabled", notificationCenter: "enabled", lockScreen: "enabled", scheduledDelivery: "disabled", timeSensitive: "disabled")
    var pending: [String: PendingNotification] = [:]
    var added: [NotificationRequestSpec] = []
    var removed: [[String]] = []
    var failNextAdd = false
    func requestAuthorization() async throws { snapshot.authorization = .authorized }
    func settings() async -> NotificationSettingsSnapshot { snapshot }
    func pendingRequests() async -> [PendingNotification] { Array(pending.values) }
    func add(_ request: NotificationRequestSpec) async throws {
        if failNextAdd { failNextAdd = false; throw NSError(domain: "FakeNotificationCenter", code: 1) }
        added.append(request); pending[request.identifier] = PendingNotification(identifier: request.identifier, signature: request.userInfo["planSignature"])
    }
    func removePendingRequests(withIdentifiers identifiers: [String]) { removed.append(identifiers); for id in identifiers { pending.removeValue(forKey: id) } }
}

@MainActor final class AppIntegrationTests: XCTestCase {
    func library() throws -> LibraryStore { LibraryStore(modelContainer: try StorageFactory.container(inMemory: true)) }

    func testColdNotificationResponseOpensExactEntryAfterLoad() async throws {
        let store = try library()
        let first = try await store.addOwn(EntryDraft(text: "First ordinary thought"))
        let target = try await store.addOwn(EntryDraft(text: "Exact notification target"))
        let state = AppState(store: store)
        let delegate = AppDelegate(); delegate.state = state
        await delegate.receive(entryID: target.id, planID: "lern.test.plan")
        XCTAssertNil(state.current)
        await state.open(first.id)
        XCTAssertEqual(state.preferences.streak.current, 1)
        let initialHistory = try await store.history()
        XCTAssertTrue(initialHistory.contains { $0.entryID == first.id && $0.kind == "viewed" })
        await state.load()
        await state.open(first.id)
        await delegate.deliverPendingResponses()
        XCTAssertEqual(state.current?.id, target.id)
        let history = try await store.history()
        XCTAssertTrue(history.contains { $0.entryID == target.id && $0.kind == "opened" })
    }

    func testProfileSourceChangeAndMuteRemoveOldFeedHistory() async throws {
        let store = try library()
        let a = try ImportService().preview(data: Data("Alpha first\nAlpha second".utf8), filename: "alpha.txt")
        let b = try ImportService().preview(data: Data("Beta first\nBeta second".utf8), filename: "beta.txt")
        let topicA = try await store.importEntries(a).topic
        let topicB = try await store.importEntries(b).topic
        let state = AppState(store: store); await state.load()
        await state.changeFeedSource(ContentSource(topicIDs: [topicA.id]))
        await state.next(); state.previous()
        state.preferences.feedSource = ContentSource(topicIDs: [topicB.id]); await state.savePreferences()
        XCTAssertTrue(state.current?.draft.text.hasPrefix("Beta") == true)
        XCTAssertTrue(state.feedPast.allSatisfy { $0.draft.text.hasPrefix("Beta") })
        state.preferences.mutedWords = ["Beta"]; await state.savePreferences(); await state.contentChanged()
        XCTAssertNil(state.current); XCTAssertTrue(state.feedPast.isEmpty)
        XCTAssertEqual(state.preferences.watchSource, ContentSource())
        XCTAssertEqual(state.preferences.wallpaperSource, ContentSource())
    }

    func testRemovingOnlyFavoriteEmptiesFavoritesFeed() async throws {
        let store = try library(); let item = try await store.addOwn(EntryDraft(text: "Favorite thought"))
        try await store.setFlag(item.id, flag: "favorite", value: true)
        let state = AppState(store: store); await state.load()
        await state.changeFeedSource(ContentSource(favoritesOnly: true))
        XCTAssertEqual(state.current?.id, item.id)
        await state.flag(item, "favorite", false)
        XCTAssertNil(state.current)
    }

    func testWallpaperSourceAndRenderedDimensions() async throws {
        let store = try library()
        let preview = try ImportService().preview(data: Data("Wallpaper only thought".utf8), filename: "wallpaper.txt")
        let topic = try await store.importEntries(preview).topic
        let entry = try await XCTUnwrapAsync { try await store.next(source: ContentSource(topicIDs: [topic.id]), surface: "wallpaper", mode: .sequential) }
        let renderer = ImageRenderer(content: QuoteArtwork(entry: entry, theme: ThemeValue.starters[0]).frame(width: 430, height: 932))
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage?.cgImage)
        XCTAssertEqual(image.width, 1290); XCTAssertEqual(image.height, 2796)
        XCTAssertEqual(entry.draft.text, "Wallpaper only thought")
    }

    func testNotificationReconciliationIsIdempotentAndReplacesSameIdentifier() async throws {
        let store = try library(); _ = try await store.addOwn(EntryDraft(text: "Private reminder thought"))
        var rule = ReminderRule(); rule.id = "daily"; rule.explicitMinutes = [600]; rule.revision = "one"
        try await store.put("reminders", [rule])
        let center = FakeNotificationCenter(); let scheduler = NotificationScheduler(store: store, center: center)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-09-06T00:00:00Z")!
        let initial = await scheduler.replenish(now: now, calendar: calendar); XCTAssertTrue(initial)
        XCTAssertFalse(center.added.isEmpty)
        let firstIDs = Set(center.added.map(\.identifier)); center.added = []; center.removed = []
        let identical = await scheduler.replenish(now: now, calendar: calendar); XCTAssertTrue(identical)
        XCTAssertTrue(center.added.isEmpty); XCTAssertTrue(center.removed.isEmpty)
        var preferences = try await store.get("preferences", default: Preferences()); preferences.showNotificationPreview = false; try await store.put("preferences", preferences)
        let privatePreview = await scheduler.replenish(now: now, calendar: calendar); XCTAssertTrue(privatePreview)
        XCTAssertEqual(Set(center.added.map(\.identifier)), firstIDs)
        XCTAssertTrue(center.removed.isEmpty)
        XCTAssertTrue(center.added.allSatisfy { $0.body == "A thought is ready for you." })
    }

    func testNotificationUsesTopicSymbolAndCanOmitHeading() async throws {
        let store = try library(); _ = try await store.addOwn(EntryDraft(text: "Choose the next useful step", section: "Focus"))
        var rule = ReminderRule(); rule.id = "focus"; rule.explicitMinutes = [600]; rule.revision = "topic"; rule.notificationTopic = "Leadership"; rule.notificationSymbol = "🧭"; rule.notificationTitleMode = .topic
        try await store.put("reminders", [rule])
        let center = FakeNotificationCenter(); let scheduler = NotificationScheduler(store: store, center: center)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-09-06T00:00:00Z")!
        let scheduledTopic = await scheduler.replenish(now: now, calendar: calendar)
        XCTAssertTrue(scheduledTopic)
        XCTAssertTrue(center.added.allSatisfy { $0.title == "🧭 Leadership" })

        rule.revision = "no-heading"; rule.notificationTitleMode = .none; try await store.put("reminders", [rule]); center.added = []
        let scheduledWithoutHeading = await scheduler.replenish(now: now, calendar: calendar)
        XCTAssertTrue(scheduledWithoutHeading)
        XCTAssertTrue(center.added.allSatisfy { $0.title.isEmpty })
    }

    func testNotificationFailureLeavesRetryablePlansAndStreakRemovesToday() async throws {
        let store = try library(); _ = try await store.addOwn(EntryDraft(text: "Streak thought"))
        var preferences = Preferences(); preferences.streakReminder = true; try await store.put("preferences", preferences)
        let center = FakeNotificationCenter(); center.failNextAdd = true
        let scheduler = NotificationScheduler(store: store, center: center)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let evening = ISO8601DateFormatter().date(from: "2026-09-06T18:00:00Z")!
        let failedReconcile = await scheduler.replenish(now: evening, calendar: calendar); XCTAssertFalse(failedReconcile)
        let failed: [DeliveryPlan] = try await store.get("plans", default: [])
        XCTAssertTrue(failed.contains { $0.state == "planned" })
        let recovered = await scheduler.replenish(now: evening, calendar: calendar); XCTAssertTrue(recovered)
        XCTAssertTrue(center.pending.keys.contains { $0.contains("system.streak") })
        let todayStreakIDs = center.pending.keys.filter { id in
            guard id.contains("system.streak"), let timestamp = Int(id.split(separator: ".").last ?? "") else { return false }
            return calendar.isDate(Date(timeIntervalSince1970: TimeInterval(timestamp)), inSameDayAs: evening)
        }
        XCTAssertFalse(todayStreakIDs.isEmpty)
        preferences.streak.read(on: evening, calendar: calendar); try await store.put("preferences", preferences)
        let readToday = await scheduler.replenish(now: evening, calendar: calendar); XCTAssertTrue(readToday)
        XCTAssertTrue(todayStreakIDs.allSatisfy { center.pending[$0] == nil })
        XCTAssertTrue(center.pending.keys.contains { $0.contains("system.streak") })
    }

    func testDeniedNotificationsDoNotAdvertiseCoverage() async throws {
        let store = try library(); _ = try await store.addOwn(EntryDraft(text: "No delivery"))
        var rule = ReminderRule(); rule.id = "denied"; try await store.put("reminders", [rule])
        let center = FakeNotificationCenter(); center.snapshot.authorization = .denied
        let scheduler = NotificationScheduler(store: store, center: center)
        let denied = await scheduler.replenish(); XCTAssertTrue(denied)
        XCTAssertEqual(scheduler.pendingCount, 0); XCTAssertNil(scheduler.scheduledThrough)
    }

    private func XCTUnwrapAsync<T>(_ value: () async throws -> T?) async throws -> T { let result = try await value(); return try XCTUnwrap(result) }
}
