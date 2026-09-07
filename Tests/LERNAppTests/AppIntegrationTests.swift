import XCTest
import SwiftUI
import LERNCore
@testable import LERN

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

    private func XCTUnwrapAsync<T>(_ value: () async throws -> T?) async throws -> T { let result = try await value(); return try XCTUnwrap(result) }
}
