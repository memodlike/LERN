import Foundation
import UserNotifications
import LERNCore
import Observation

struct NotificationSettingsSnapshot: Equatable, Sendable {
    var authorization: UNAuthorizationStatus = .notDetermined
    var alerts = "unknown"
    var sounds = "unknown"
    var notificationCenter = "unknown"
    var lockScreen = "unknown"
    var scheduledDelivery = "unknown"
    var timeSensitive = "unknown"
    var permitsScheduling: Bool { authorization == .authorized || authorization == .provisional || authorization == .ephemeral }
    var visiblyDeliverable: Bool { permitsScheduling && alerts == "enabled" }
}

struct PendingNotification: Equatable, Sendable { var identifier: String; var signature: String? }
struct NotificationRequestSpec: Equatable, Sendable {
    var identifier: String; var date: Date; var title: String; var body: String
    var userInfo: [String: String]; var sound: String; var isAlarm: Bool
}

@MainActor protocol NotificationCenterClient: AnyObject {
    func requestAuthorization() async throws
    func settings() async -> NotificationSettingsSnapshot
    func pendingRequests() async -> [PendingNotification]
    func add(_ request: NotificationRequestSpec) async throws
    func removePendingRequests(withIdentifiers identifiers: [String])
}

@MainActor final class SystemNotificationCenter: NotificationCenterClient {
    private let center: UNUserNotificationCenter
    init(center: UNUserNotificationCenter = .current()) { self.center = center }
    func requestAuthorization() async throws { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
    func settings() async -> NotificationSettingsSnapshot {
        let value = await center.notificationSettings()
        return NotificationSettingsSnapshot(authorization: value.authorizationStatus, alerts: Self.name(value.alertSetting), sounds: Self.name(value.soundSetting), notificationCenter: Self.name(value.notificationCenterSetting), lockScreen: Self.name(value.lockScreenSetting), scheduledDelivery: Self.name(value.scheduledDeliverySetting), timeSensitive: Self.name(value.timeSensitiveSetting))
    }
    func pendingRequests() async -> [PendingNotification] {
        await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("lern.") }.map { PendingNotification(identifier: $0.identifier, signature: $0.content.userInfo["planSignature"] as? String) }
    }
    func add(_ request: NotificationRequestSpec) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title; content.body = request.body; content.userInfo = request.userInfo
        content.threadIdentifier = request.userInfo["ruleID"] ?? "lern"
        content.categoryIdentifier = request.isAlarm ? "lern.alarm" : "lern.learning"
        if request.sound == "default" { content.sound = .default }
        else if ["chime1", "chime2", "chime3"].contains(request.sound) { content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: request.sound + ".caf")) }
        let parts = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day, .hour, .minute, .second], from: request.date)
        try await center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
    }
    func removePendingRequests(withIdentifiers identifiers: [String]) { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
    private static func name(_ value: UNNotificationSetting) -> String {
        switch value { case .enabled: return "enabled"; case .disabled: return "disabled"; case .notSupported: return "notSupported"; @unknown default: return "unknown" }
    }
}

@MainActor @Observable final class NotificationScheduler {
    private(set) var store: LibraryStore
    private let center: any NotificationCenterClient
    var pendingCount = 0
    var scheduledThrough: Date?
    var authorization: UNAuthorizationStatus = .notDetermined
    var settings = NotificationSettingsSnapshot()
    var lastError: String?
    private var running = false
    private var rerun = false

    init(store: LibraryStore, center: (any NotificationCenterClient)? = nil) { self.store = store; self.center = center ?? SystemNotificationCenter() }
    func useStore(_ store: LibraryStore) { self.store = store; if running { rerun = true } }
    func requestPermission() async { do { try await center.requestAuthorization(); _ = await replenish() } catch { lastError = error.localizedDescription } }
    @discardableResult func replenish(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) async -> Bool {
        if running { rerun = true; return false }
        running = true; var succeeded = true
        repeat { rerun = false; succeeded = await reconcile(now: now, calendar: calendar) && succeeded } while rerun
        running = false; return succeeded
    }

    private func reconcile(now: Date, calendar: Calendar) async -> Bool {
        let store = self.store
        settings = await center.settings(); authorization = settings.authorization
        let pending = await center.pendingRequests(); pendingCount = pending.count
        guard settings.permitsScheduling else {
            if !pending.isEmpty { center.removePendingRequests(withIdentifiers: pending.map(\.identifier).sorted()) }
            pendingCount = 0; scheduledThrough = nil; return true
        }
        do {
            var rules = try await store.get("reminders", default: [ReminderRule]()).filter { !ReminderRule.isReservedID($0.id) }
            let preferences = try await store.get("preferences", default: Preferences())
            if preferences.streakReminder {
                var streak = ReminderRule(); streak.id = "system.streak"; streak.revision = "streak-v2"; streak.name = "A moment to read"
                streak.explicitMinutes = [1200]; streak.source = preferences.feedSource; streak.mode = .sequential; rules.append(streak)
            }
            var pools: [String: [String]] = [:]
            for rule in rules where rule.enabled { pools[rule.id] = try await store.eligibleIDs(source: rule.source) }
            let active = rules.filter { !((pools[$0.id] ?? []).isEmpty) }
            let readToday = preferences.streak.lastDay.map { calendar.isDate($0, inSameDayAs: now) } ?? false
            let slots = ScheduleEngine.slots(rules: active, after: now, calendar: calendar).filter { !($0.ruleID == "system.streak" && readToday && calendar.isDate($0.date, inSameDayAs: now)) }
            let old: [DeliveryPlan] = try await store.get("plans", default: [])
            let previous = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var plans: [DeliveryPlan] = [], cursors: [String: SelectionCursor] = [:]
            for slot in slots {
                guard let rule = active.first(where: { $0.id == slot.ruleID }), let pool = pools[rule.id], !pool.isEmpty else { continue }
                let revision = slot.revision + (preferences.showNotificationPreview ? ".preview" : ".private")
                if let plan = previous[slot.id], plan.revision == revision, pool.contains(plan.entryID), plan.state != "cancelled" { plans.append(plan); continue }
                let key = "cursor.reminder." + rule.id
                var cursor: SelectionCursor
                if let cached = cursors[key] { cursor = cached }
                else { cursor = try await store.get(key, default: SelectionCursor()) }
                guard let id = SelectionEngine.next(ids: pool, mode: rule.mode, cursor: &cursor) else { continue }
                cursors[key] = cursor; plans.append(DeliveryPlan(id: slot.id, ruleID: rule.id, revision: revision, date: slot.date, entryID: id))
            }
            let desiredIDs = Set(plans.map(\.id)), pendingIDs = Set(pending.map(\.identifier))
            let obsoleteIDs = pendingIDs.subtracting(desiredIDs)
            if !obsoleteIDs.isEmpty { center.removePendingRequests(withIdentifiers: obsoleteIDs.sorted()) }
            try await store.put("plans", plans)
            for (key, cursor) in cursors { try await store.put(key, cursor) }
            let pendingByID = Dictionary(uniqueKeysWithValues: pending.map { ($0.identifier, $0) })
            for index in plans.indices {
                guard let entry = try await store.entry(plans[index].entryID), let rule = rules.first(where: { $0.id == plans[index].ruleID }) else { continue }
                let spec = request(plan: plans[index], entry: entry, rule: rule, previewsVisible: preferences.showNotificationPreview)
                if pendingByID[spec.identifier]?.signature == spec.userInfo["planSignature"] { plans[index].state = "scheduled" }
                else { try await center.add(spec); plans[index].state = "scheduled" }
                try await store.put("plans", plans)
            }
            let refreshed = await center.pendingRequests(); pendingCount = refreshed.count
            scheduledThrough = settings.visiblyDeliverable ? plans.filter { $0.state == "scheduled" }.map(\.date).max() : nil
            lastError = nil; return true
        } catch { lastError = error.localizedDescription; scheduledThrough = nil; return false }
    }

    private func request(plan: DeliveryPlan, entry: EntryValue, rule: ReminderRule, previewsVisible: Bool) -> NotificationRequestSpec {
        let text = String(entry.draft.text.prefix(NotificationBodyLimit.characters))
        let body = previewsVisible ? text + (entry.draft.text.count > NotificationBodyLimit.characters ? "…" : "") : "A thought is ready for you."
        let title = notificationTitle(for: entry, rule: rule)
        let signature = [plan.revision, plan.entryID, title, body, rule.sound, rule.isAlarm ? "alarm" : "learning"].joined(separator: "|")
        return NotificationRequestSpec(identifier: plan.id, date: plan.date, title: title, body: body, userInfo: ["entryID": entry.id, "ruleID": rule.id, "planID": plan.id, "kind": rule.isAlarm ? "alarm" : "learning", "planSignature": signature], sound: rule.sound, isAlarm: rule.isAlarm)
    }
    private func notificationTitle(for entry: EntryValue, rule: ReminderRule) -> String {
        let mode = rule.notificationTitleMode ?? "topic"
        guard mode != "none" else { return "" }
        let topic: String
        if mode == "section", !entry.draft.section.isEmpty { topic = entry.draft.section }
        else {
            let custom = rule.notificationTopic?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let fallback = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
            topic = !custom.isEmpty ? custom : (!fallback.isEmpty ? fallback : Product.name)
        }
        let symbol = rule.notificationSymbol?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16) ?? ""
        return (symbol.isEmpty ? topic : "\(symbol) \(topic)").prefix(80).description
    }
    func opened(_ planID: String) async {
        guard planID.hasPrefix("lern.") else { return }
        do { var plans: [DeliveryPlan] = try await store.get("plans", default: []); if let index = plans.firstIndex(where: { $0.id == planID }) { plans[index].state = "opened"; plans[index].openedAt = Date(); try await store.put("plans", plans) } } catch { lastError = error.localizedDescription }
    }
}
