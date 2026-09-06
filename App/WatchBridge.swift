import Foundation
import WatchConnectivity
import LERNCore

@MainActor final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()
    private var store: LibraryStore?
    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self; WCSession.default.activate()
    }
    func update(store: LibraryStore, source: ContentSource) async {
        self.store = store
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        do {
            let entries = try await store.page(source: source, limit: 100)
            let data = try JSONEncoder().encode(entries)
            try WCSession.default.updateApplicationContext(["entries": data])
        } catch { /* Retried on the next foreground/content event; no background polling. */ }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let id = userInfo["favoriteID"] as? String, let favorite = userInfo["favorite"] as? Bool else { return }
        Task { @MainActor in
            do { let library: LibraryStore; if let store = self.store { library = store } else { library = try SharedStore.open() }; try await library.setFlag(id, flag: "favorite", value: favorite) } catch {}
        }
    }
}
