import SwiftUI
import WatchConnectivity
import WidgetKit
import LERNCore

@MainActor @Observable final class WatchLibrary: NSObject, WCSessionDelegate {
    var entries: [EntryValue] = []
    var index = 0
    var current: EntryValue? { entries.indices.contains(index) ? entries[index] : nil }
    private let defaults = UserDefaults(suiteName: Product.appGroup) ?? .standard
    private var pendingFavorites: [String: Bool] = [:]
    override init() {
        super.init()
        if let data = defaults.data(forKey: "watch.entries"), data.count < 60_000,
           let saved = try? JSONDecoder().decode([EntryValue].self, from: data), saved.count <= 100 { entries = saved }
        index = entries.indices.contains(defaults.integer(forKey: "watch.index")) ? defaults.integer(forKey: "watch.index") : 0
        pendingFavorites = defaults.dictionary(forKey: "watch.pendingFavorites") as? [String: Bool] ?? [:]
        for position in entries.indices { if let favorite = pendingFavorites[entries[position].id] { entries[position].favorite = favorite } }
        persist()
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }
    func next() { if !entries.isEmpty { index = (index + 1) % entries.count; persist() } }
    func favorite() {
        guard let entry = current else { return }
        entries[index].favorite.toggle()
        pendingFavorites[entry.id] = entries[index].favorite
        defaults.set(pendingFavorites, forKey: "watch.pendingFavorites")
        persist(); flushFavorites()
    }
    private func persist() {
        guard let data = try? JSONEncoder().encode(entries), data.count < 60_000 else { return }
        defaults.set(data, forKey: "watch.entries")
        defaults.set(index, forKey: "watch.index")
        WidgetCenter.shared.reloadAllTimelines()
    }
    private func flushFavorites() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        for (id, favorite) in pendingFavorites { WCSession.default.transferUserInfo(["favoriteID": id, "favorite": favorite]) }
        pendingFavorites = [:]; defaults.removeObject(forKey: "watch.pendingFavorites")
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        receive(session.receivedApplicationContext)
        Task { @MainActor in flushFavorites() }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { receive(applicationContext) }
    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        guard error != nil, let id = userInfoTransfer.userInfo["favoriteID"] as? String,
              let favorite = userInfoTransfer.userInfo["favorite"] as? Bool else { return }
        Task { @MainActor in
            guard pendingFavorites[id] == nil,
                  entries.first(where: { $0.id == id })?.favorite == favorite else { return }
            pendingFavorites[id] = favorite
            defaults.set(pendingFavorites, forKey: "watch.pendingFavorites")
        }
    }
    nonisolated private func receive(_ context: [String: Any]) {
        guard let data = context["entries"] as? Data, data.count < 60_000 else { return }
        Task { @MainActor in
            guard var entries = try? JSONDecoder().decode([EntryValue].self, from: data), entries.count <= 100,
                  Set(entries.map(\.id)).count == entries.count else { return }
            let previousID = current?.id
            for position in entries.indices { if let favorite = pendingFavorites[entries[position].id] { entries[position].favorite = favorite } }
            self.entries = entries
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
