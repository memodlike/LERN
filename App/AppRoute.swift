import Foundation
import LERNCore

/// The only app-level destination accepted from notification and URL input.
/// It contains identifiers only, never notification text or external URLs.
enum AppRoute: Hashable, Sendable {
    case entry(id: String, planID: String?, share: Bool)
    case library

    static func notification(userInfo: [AnyHashable: Any], requestID: String, category: String, actionIdentifier: String) -> AppRoute? {
        guard requestID.hasPrefix("lern."),
              actionIdentifier == "com.apple.UNNotificationDefaultActionIdentifier",
              ["lern.alarm", "lern.learning"].contains(category),
              let entryID = userInfo["entryID"] as? String,
              FavoriteMutation.isEntryID(entryID),
              let planID = userInfo["planID"] as? String,
              planID == requestID else { return nil }
        return .entry(id: entryID, planID: planID, share: false)
    }

    static func url(_ url: URL) -> AppRoute? {
        guard url.scheme == Product.scheme else { return nil }
        if url.host == "entry", let id = url.pathComponents.last, FavoriteMutation.isEntryID(id) {
            let share = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { $0.name == "share" && $0.value != "0" }) ?? false
            return .entry(id: id, planID: nil, share: share)
        }
        if url.host == "library", url.path == "/" || url.path.isEmpty { return .library }
        return nil
    }

    var stableID: String {
        switch self {
        case let .entry(id, planID, share): "entry:\(id):\(planID ?? "url"):\(share)"
        case .library: "library"
        }
    }
}

/// Keeps only unconsumed routes. A repeated delegate callback cannot cause a
/// second navigation or a duplicate "opened" history event.
struct PendingAppRoutes: Sendable {
    private var queued: [AppRoute] = []
    private var consumed = Set<String>()

    var isEmpty: Bool { queued.isEmpty }
    var count: Int { queued.count }
    func peek() -> AppRoute? { queued.first }

    mutating func enqueue(_ route: AppRoute) {
        guard !consumed.contains(route.stableID), !queued.contains(where: { $0.stableID == route.stableID }) else { return }
        queued.append(route)
    }

    mutating func dequeue() -> AppRoute? {
        guard !queued.isEmpty else { return nil }
        return queued.removeFirst()
    }
    mutating func complete(_ route: AppRoute) { consumed.insert(route.stableID) }
    mutating func retry(_ route: AppRoute) {
        guard !consumed.contains(route.stableID), !queued.contains(where: { $0.stableID == route.stableID }) else { return }
        queued.insert(route, at: 0)
    }
}

/// Thread-safe wrapper around `PendingAppRoutes` protected by an `NSLock`.
/// Enables nonisolated delegate methods (such as `UNUserNotificationCenterDelegate`)
/// to enqueue incoming routes instantaneously without blocking or hopping to the main actor.
final class PendingRouteQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = PendingAppRoutes()

    var isEmpty: Bool {
        lock.lock(); defer { lock.unlock() }
        return storage.isEmpty
    }

    var hasPending: Bool {
        lock.lock(); defer { lock.unlock() }
        return !storage.isEmpty
    }

    func enqueue(_ route: AppRoute) {
        lock.lock(); defer { lock.unlock() }
        storage.enqueue(route)
    }

    func dequeue() -> AppRoute? {
        lock.lock(); defer { lock.unlock() }
        return storage.dequeue()
    }

    func complete(_ route: AppRoute) {
        lock.lock(); defer { lock.unlock() }
        storage.complete(route)
    }

    func retry(_ route: AppRoute) {
        lock.lock(); defer { lock.unlock() }
        storage.retry(route)
    }

    func peek() -> AppRoute? {
        lock.lock(); defer { lock.unlock() }
        return storage.peek()
    }
}
