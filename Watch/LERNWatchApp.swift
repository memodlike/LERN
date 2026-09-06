import SwiftUI
import WatchConnectivity
import WidgetKit
import LERNCore

@MainActor @Observable final class WatchLibrary: NSObject, WCSessionDelegate {
    var entries: [EntryValue] = []
    var index = 0
    var current: EntryValue? { entries.indices.contains(index) ? entries[index] : nil }
    private let defaults = UserDefaults(suiteName: Product.appGroup) ?? .standard
    override init() {
        super.init()
        if let data = defaults.data(forKey: "watch.entries") { entries = (try? JSONDecoder().decode([EntryValue].self, from: data)) ?? [] }
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }
    func next() { if !entries.isEmpty { index = (index + 1) % entries.count; defaults.set(index, forKey: "watch.index"); WidgetCenter.shared.reloadAllTimelines() } }
    func favorite() {
        guard let entry = current else { return }
        entries[index].favorite.toggle(); defaults.set(try? JSONEncoder().encode(entries), forKey: "watch.entries")
        WCSession.default.transferUserInfo(["favoriteID": entry.id, "favorite": entries[index].favorite])
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        receive(context)
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { receive(applicationContext) }
    nonisolated private func receive(_ context: [String: Any]) {
        guard let data = context["entries"] as? Data, data.count < 10_000_000 else { return }
        Task { @MainActor in
            if let entries = try? JSONDecoder().decode([EntryValue].self, from: data) { self.entries = entries; self.index = 0; self.defaults.set(data, forKey: "watch.entries"); WidgetCenter.shared.reloadAllTimelines() }
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
