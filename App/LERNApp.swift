import SwiftUI
import LERNCore
import UserNotifications
import BackgroundTasks

@main struct LERNApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var state: AppState?
    @State private var startupError: String?
    @Environment(\.scenePhase) private var phase

    init() {
        do {
            let appState = AppState(store: try SharedStore.open())
            _state = State(initialValue: appState)
        } catch {
            _startupError = State(initialValue: error.localizedDescription)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let state {
                    FeedView().environment(state)
                        .environment(\.locale, state.preferences.language == "system" ? .current : Locale(identifier: state.preferences.language))
                        .task {
                            delegate.state = state
                            await state.load(skipInitialNext: delegate.hasPendingRoutes)
                            await delegate.deliverPendingResponses()
                        }
                        .onOpenURL { url in Task { await delegate.receive(url: url) } }
                        .onChange(of: phase) { _, next in
                            if next == .active {
                                Task {
                                    await state.refreshOnForeground()
                                    await delegate.deliverPendingResponses()
                                }
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in Task { await state.scheduler.replenish() } }
                        .alert("Something needs attention", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) { Button("OK") { state.error = nil } } message: { Text(state.error ?? "") }
                } else if let startupError {
                    ContentUnavailableView { Label("Library could not open", systemImage: "externaldrive.badge.exclamationmark") } description: { Text(startupError) } actions: { Button("Try again") { initialize() } }
                } else { ProgressView("Opening your library").task { initialize() } }
            }
        }
    }
    private func initialize() {
        do {
            let appState = AppState(store: try SharedStore.open())
            delegate.state = appState
            state = appState
            startupError = nil
        }
        catch { startupError = error.localizedDescription }
    }

}

@MainActor final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let backgroundRefreshIdentifier = "app.lern.local.notification-refresh"
    weak var state: AppState?
    private let pendingRoutes = PendingRouteQueue()
    private var deliveringRoutes = false

    var hasPendingRoutes: Bool { pendingRoutes.hasPending }

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

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
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        let request = response.notification.request
        guard let route = AppRoute.notification(userInfo: request.content.userInfo, requestID: request.identifier, category: request.content.categoryIdentifier, actionIdentifier: response.actionIdentifier) else { return }
        pendingRoutes.enqueue(route)
        Task { @MainActor [weak self] in
            await self?.deliverPendingResponses()
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(notification.request.content.categoryIdentifier == "lern.alarm" ? [.banner, .sound, .list] : [.banner, .sound, .list])
    }
    func receive(url: URL) async {
        guard let route = AppRoute.url(url) else { return }
        await receive(route)
    }
    func receive(entryID: String, planID: String) async {
        guard FavoriteMutation.isEntryID(entryID), planID.hasPrefix("lern.") else { return }
        await receive(.entry(id: entryID, planID: planID, share: false))
    }
    func receive(_ route: AppRoute) async {
        pendingRoutes.enqueue(route)
        await deliverPendingResponses()
    }
    func deliverPendingResponses() async {
        guard let state, state.loaded, !deliveringRoutes else { return }
        deliveringRoutes = true; defer { deliveringRoutes = false }
        while let route = pendingRoutes.dequeue() {
            switch route {
            case let .entry(id, planID, share):
                switch await state.openRoute(id, kind: "opened") {
                case .opened:
                    pendingRoutes.complete(route)
                    if let planID { await state.scheduler.opened(planID) }
                    if share { state.sheet = .share }
                case .missing:
                    // A deleted entry is terminal; fall back to the normal feed.
                    pendingRoutes.complete(route)
                    if state.current == nil { await state.next() }
                case .failed:
                    // Preserve the route for a later foreground/ready attempt.
                    pendingRoutes.retry(route)
                    if state.current == nil { await state.next() }
                    return
                }
            case .library:
                pendingRoutes.complete(route)
                state.sheet = .library
            }
        }
    }
}
