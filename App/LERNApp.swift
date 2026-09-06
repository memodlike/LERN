import SwiftUI
import LERNCore
import UserNotifications

@main struct LERNApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var state: AppState?
    @State private var startupError: String?
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            Group {
                if let state {
                    FeedView().environment(state)
                        .environment(\.locale, state.preferences.language == "system" ? .current : Locale(identifier: state.preferences.language))
                        .task { delegate.state = state; await state.load() }
                        .onOpenURL { url in Task { await route(url, state: state) } }
                        .onChange(of: phase) { _, next in if next == .active { Task { await state.scheduler.replenish() } } }
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in Task { await state.scheduler.replenish() } }
                        .alert("Something needs attention", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) { Button("OK") { state.error = nil } } message: { Text(state.error ?? "") }
                } else if let startupError {
                    ContentUnavailableView { Label("Library could not open", systemImage: "externaldrive.badge.exclamationmark") } description: { Text(startupError) } actions: { Button("Try again") { initialize() } }
                } else { ProgressView("Opening your library").task { initialize() } }
            }
        }
    }
    private func initialize() {
        do { state = AppState(store: try SharedStore.open()) }
        catch { startupError = error.localizedDescription }
    }
    private func route(_ url: URL, state: AppState) async {
        guard url.scheme == Product.scheme else { return }
        if url.host == "entry", let id = url.pathComponents.last, id.count == 64 { await state.open(id); if URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "share" }) == true { state.sheet = .share } }
        else if url.host == "library" { state.sheet = .library }
        await state.scheduler.replenish()
    }
}

@MainActor final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var state: AppState?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        WatchBridge.shared.activate()
        return true
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo["entryID"] as? String else { return }
        let planID = response.notification.request.identifier
        await MainActor.run { if let state = self.state { Task { await state.scheduler.opened(planID); await state.open(id); await state.scheduler.replenish() } } }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound, .list] }
}
