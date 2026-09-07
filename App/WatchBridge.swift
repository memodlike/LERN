import Foundation
import WatchConnectivity
import LERNCore
import WidgetKit

@MainActor final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()
    private var store: LibraryStore?
    private var source: ContentSource?
    private var revision = 0
    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self; WCSession.default.activate()
    }
    func update(store: LibraryStore, source: ContentSource) async {
        self.store = store
        self.source = source
        revision += 1
        let requestedRevision = revision
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
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
            try WCSession.default.updateApplicationContext(["entries": data])
        } catch { /* Retried on the next foreground/content event; no background polling. */ }
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
        } catch { /* Retried after activation or the next content event. */ }
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
        guard let id = userInfo["favoriteID"] as? String, id.utf8.count == 64,
              id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              let favorite = userInfo["favorite"] as? Bool else { return }
        Task { @MainActor in
            do {
                let library: LibraryStore
                if let store = self.store { library = store } else { library = try SharedStore.open() }
                try await library.setFlag(id, flag: "favorite", value: favorite)
                WidgetCenter.shared.reloadAllTimelines()
                await retry()
            } catch {}
        }
    }
}
