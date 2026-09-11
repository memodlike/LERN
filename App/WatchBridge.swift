import Foundation
import WatchConnectivity
import LERNCore
import WidgetKit
import os

@MainActor final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()
    private var store: LibraryStore?
    private var source: ContentSource?
    private var revision = 0
    private(set) var lastSuccessfulSync: Date?
    private(set) var syncedCount = 0
    private(set) var lastSyncError: String?
    private let logger = Logger(subsystem: "com.memodlike.lern", category: "watch.favoriteSync")
    var onFavoriteMutation: (@MainActor () async -> Void)?
    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self; WCSession.default.activate()
    }
    func update(store: LibraryStore, source: ContentSource) async {
        self.store = store
        self.source = source
        revision += 1
        let requestedRevision = revision
        guard WCSession.isSupported() else { lastSyncError = "Apple Watch is not supported on this device."; return }
        guard WCSession.default.activationState == .activated else { lastSyncError = "Apple Watch is connecting."; return }
        guard WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { lastSyncError = "Pair and install LERN on Apple Watch to sync."; return }
        do {
            let entries = try await store.page(source: source, limit: 100)
            guard requestedRevision == revision else { return }
            let encoder = JSONEncoder()
            var snapshot: [EntryValue] = []
            var data = try encoder.encode(snapshot)
            for var entry in entries {
                // Keep the original identity for favorite updates; the Watch receives display excerpts.
                entry.draft.text = excerpt(entry.draft.text, bytes: 4_000)
                entry.draft.author = excerpt(entry.draft.author, bytes: 512)
                entry.draft.source = excerpt(entry.draft.source, bytes: 512)
                entry.draft.tags = []; entry.draft.section = ""
                let candidate = try encoder.encode(snapshot + [entry])
                guard candidate.count < 59_000 else { break }
                snapshot.append(entry); data = candidate
            }
            try WCSession.default.updateApplicationContext(["entries": data, "version": WatchPayload.schemaVersion])
            syncedCount = snapshot.count; lastSuccessfulSync = Date(); lastSyncError = nil
        } catch { lastSyncError = error.localizedDescription }
    }
    private func excerpt(_ text: String, bytes: Int) -> String {
        guard text.utf8.count > bytes else { return text }
        return String(decoding: text.utf8.prefix(bytes), as: UTF8.self) + "…"
    }
    private func retry() async {
        do {
            let library: LibraryStore
            if let store { library = store } else { library = try SharedStore.open() }
            let selected: ContentSource
            if let source { selected = source }
            else {
                let preferences = try await library.get("preferences", default: Preferences())
                selected = source ?? preferences.watchSource
            }
            await update(store: library, source: selected)
        } catch { lastSyncError = error.localizedDescription }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in await retry() }
    }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in await retry() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["favoriteMutation"] as? Data,
              let mutation = try? JSONDecoder().decode(FavoriteMutation.self, from: data),
              mutation.isValid() else {
            Logger(subsystem: "com.memodlike.lern", category: "watch.favoriteSync").error("rejected invalid favorite mutation payload")
            return
        }
        Task { @MainActor in
            do {
                let library: LibraryStore
                if let store = self.store { library = store } else { library = try SharedStore.open() }
                let applied = try await library.setFlag(mutation.entryID, flag: "favorite", value: mutation.desiredFavorite)
                let result: FavoriteMutationResult = applied ? .applied : .rejectedMissingEntry
                let ack = FavoriteAck(mutationID: mutation.mutationID, entryID: mutation.entryID, result: result)
                guard let ackData = try? JSONEncoder().encode(ack) else { return }
                session.transferUserInfo(["favoriteAck": ackData])
                if applied {
                    WidgetCenter.shared.reloadTimelines(ofKind: "LERNQuoteWidget")
                    if let onFavoriteMutation { await onFavoriteMutation() }
                    else { SharedStore.markNotificationScheduleDirty() }
                    await retry()
                }
            } catch {
                self.logger.error("favorite mutation persistence failed: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
    }
}
