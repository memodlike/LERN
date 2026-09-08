import SwiftUI
import LERNCore
import UserNotifications
import BackgroundTasks

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
                        .task { delegate.state = state; await state.load(); await delegate.deliverPendingResponses() }
                        .onOpenURL { url in Task { await route(url, state: state) } }
                        .onChange(of: phase) { _, next in if next == .active { Task { await state.refreshOnForeground(); await delegate.deliverPendingResponses() } } }
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
        if url.host == "entry", let id = url.pathComponents.last, id.count == 64 { await state.open(id, kind: "opened"); if URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "share" }) == true { state.sheet = .share } }
        else if url.host == "library" { state.sheet = .library }
        await state.scheduler.replenish()
    }
}

@MainActor final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let backgroundRefreshIdentifier = "app.lern.local.notification-refresh"
    weak var state: AppState?
    private var pendingResponses: [(entryID: String, planID: String)] = []
    private var deliveringResponse = false
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundRefreshIdentifier, using: nil) { [weak self] task in
            guard let refresh = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            self?.runBackgroundRefresh(refresh)
        }
        WatchBridge.shared.activate()
        return true
    }
    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
    private nonisolated func runBackgroundRefresh(_ task: BGAppRefreshTask) {
        let work = Task { @MainActor [weak self] in
            // Submit first: a transient failure must not permanently stop future refresh attempts.
            Self.scheduleBackgroundRefresh()
            let scheduler: NotificationScheduler
            if let state = self?.state { scheduler = state.scheduler }
            else if let store = try? SharedStore.open() { scheduler = NotificationScheduler(store: store) }
            else { task.setTaskCompleted(success: false); return }
            let success = await scheduler.replenish()
            if success { SharedStore.clearNotificationScheduleDirty() }
            task.setTaskCompleted(success: success && !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo["entryID"] as? String,
              id.utf8.count == 64, id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              response.notification.request.identifier.hasPrefix("lern.") else { return }
        let planID = response.notification.request.identifier
        await receive(entryID: id, planID: planID)
    }
    func receive(entryID: String, planID: String) async {
        pendingResponses.append((entryID, planID))
        await deliverPendingResponses()
    }
    func deliverPendingResponses() async {
        guard let state, state.loaded, !deliveringResponse else { return }
        deliveringResponse = true; defer { deliveringResponse = false }
        while !pendingResponses.isEmpty {
            let response = pendingResponses.removeFirst()
            await state.scheduler.opened(response.planID)
            await state.open(response.entryID, kind: "opened")
        }
        await state.scheduler.replenish()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        notification.request.content.categoryIdentifier == "lern.alarm" ? [.banner, .sound, .list] : [.list]
    }
}
