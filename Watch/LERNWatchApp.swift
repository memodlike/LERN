import SwiftUI
import WatchConnectivity
import WidgetKit
import LERNCore
import os

@MainActor @Observable final class WatchLibrary: NSObject, WCSessionDelegate {
    var entries: [EntryValue] = []
    var index = 0
    var current: EntryValue? { entries.indices.contains(index) ? entries[index] : nil }
    private let defaults = UserDefaults(suiteName: Product.appGroup) ?? .standard
    private var pendingFavorites = PendingFavoriteMutations()
    private let logger = Logger(subsystem: "com.memodlike.lern", category: "watch.favoriteSync")
    override init() {
        super.init()
        if let data = defaults.data(forKey: "watch.entries"), data.count < 60_000,
           let saved = WatchPayload.decodeEntries(data, version: defaults.object(forKey: "watch.entries.version") as? Int) { entries = saved }
        index = entries.indices.contains(defaults.integer(forKey: "watch.index")) ? defaults.integer(forKey: "watch.index") : 0
        if let data = defaults.data(forKey: "watch.pendingFavoriteMutations"),
           let pending = try? JSONDecoder().decode(PendingFavoriteMutations.self, from: data) {
            pendingFavorites = pending
        } else if let legacy = defaults.dictionary(forKey: "watch.pendingFavorites") as? [String: Bool] {
            pendingFavorites = PendingFavoriteMutations(legacy.map { FavoriteMutation(entryID: $0.key, desiredFavorite: $0.value) })
            defaults.removeObject(forKey: "watch.pendingFavorites")
        }
        entries = pendingFavorites.applying(to: entries)
        persist()
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }
    func next() { if !entries.isEmpty { index = (index + 1) % entries.count; persist() } }
    func favorite() {
        guard let entry = current else { return }
        entries[index].favorite.toggle()
        _ = pendingFavorites.replace(entryID: entry.id, desiredFavorite: entries[index].favorite)
        savePendingFavorites()
        persist(); flushFavorites()
    }
    private func persist() {
        guard let data = try? JSONEncoder().encode(entries), data.count < 60_000 else { return }
        defaults.set(data, forKey: "watch.entries")
        defaults.set(WatchPayload.schemaVersion, forKey: "watch.entries.version")
        defaults.set(index, forKey: "watch.index")
        WidgetCenter.shared.reloadAllTimelines()
    }
    private func savePendingFavorites() {
        guard !pendingFavorites.isEmpty else {
            defaults.removeObject(forKey: "watch.pendingFavoriteMutations")
            return
        }
        guard let data = try? JSONEncoder().encode(pendingFavorites) else { return }
        defaults.set(data, forKey: "watch.pendingFavoriteMutations")
    }
    private func flushFavorites() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let outstanding = Set(WCSession.default.outstandingUserInfoTransfers.compactMap { $0.userInfo["favoriteMutationID"] as? String })
        for mutation in pendingFavorites.values where !outstanding.contains(mutation.mutationID) {
            guard let data = try? JSONEncoder().encode(mutation) else { continue }
            WCSession.default.transferUserInfo(["favoriteMutationID": mutation.mutationID, "favoriteMutation": data])
        }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        receive(session.receivedApplicationContext)
        Task { @MainActor in flushFavorites() }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { receive(applicationContext) }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in flushFavorites() }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["favoriteAck"] as? Data,
              let ack = try? JSONDecoder().decode(FavoriteAck.self, from: data), ack.isValid() else { return }
        Task { @MainActor in
            if pendingFavorites.acknowledge(ack) { savePendingFavorites() }
        }
    }
    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        // A successful transfer only means WatchConnectivity accepted delivery;
        // durable pending state is cleared exclusively by FavoriteAck.
        if let error { logger.error("favorite transfer failed: \(String(describing: type(of: error)), privacy: .public)") }
    }
    nonisolated private func receive(_ context: [String: Any]) {
        guard let data = context["entries"] as? Data, data.count < 60_000 else { return }
        Task { @MainActor in
            guard var entries = WatchPayload.decodeEntries(data, version: context["version"] as? Int) else { return }
            let previousID = current?.id
            self.entries = pendingFavorites.applying(to: entries)
            index = entries.firstIndex(where: { $0.id == previousID }) ?? 0
            persist()
        }
    }
}
@main struct LERNWatchApp: App {
    @State private var library = WatchLibrary()
    var body: some Scene {
        WindowGroup {
            ScrollView {
                VStack(spacing: 20) {
                    Text(Product.name).font(.caption.bold()).tracking(4).foregroundStyle(.secondary)
                    if let entry = library.current {
                        Text(entry.draft.text).font(.system(.title3, design: .rounded)).multilineTextAlignment(.center)
                        if !entry.draft.author.isEmpty { Text(entry.draft.author).font(.caption) }
                        HStack { Button { library.favorite() } label: { Image(systemName: entry.favorite ? "heart.fill" : "heart") }.accessibilityLabel("Favorite"); Button("Next") { library.next() } }
                    } else { Image(systemName: "iphone.and.arrow.forward").font(.largeTitle); Text("Choose a Watch source in LERN on your iPhone, then tap Sync to Watch.").multilineTextAlignment(.center).font(.footnote) }
                }.padding()
            }
        }
    }
}
