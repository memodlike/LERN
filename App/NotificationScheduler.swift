import Foundation
import UserNotifications
import LERNCore
import Observation

@MainActor @Observable final class NotificationScheduler {
    let store: LibraryStore
    var pendingCount = 0
    var scheduledThrough: Date?
    var authorization: UNAuthorizationStatus = .notDetermined
    var lastError: String?
    private var running = false
    private var rerun = false
    init(store: LibraryStore) { self.store = store }
    func requestPermission() async {
        do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]); await replenish() }
        catch { lastError = error.localizedDescription }
    }
    func replenish() async {
        if running { rerun = true; return }
        running = true
        repeat { rerun = false; await reconcile() } while rerun
        running = false
    }
    private func reconcile() async {
        let center = UNUserNotificationCenter.current()
        authorization = await center.notificationSettings().authorizationStatus
        guard authorization == .authorized || authorization == .provisional || authorization == .ephemeral else {
            pendingCount = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("lern.") }.count
            return
        }
        do {
            var rules = try await store.get("reminders", default: [ReminderRule]())
            let preferences = try await store.get("preferences", default: Preferences())
            if preferences.streakReminder {
                var streak = ReminderRule(); streak.id = "streak"; streak.revision = "streak-v1"; streak.name = "A moment to read"; streak.explicitMinutes = [1200]; streak.source = preferences.feedSource
                rules.append(streak)
            }
            var pools: [String: [String]] = [:]
            for rule in rules where rule.enabled { pools[rule.id] = try await store.eligibleIDs(source: rule.source) }
            let active = rules.filter { !((pools[$0.id] ?? []).isEmpty) }
            let slots = ScheduleEngine.slots(rules: active, after: Date())
            let old: [DeliveryPlan] = try await store.get("plans", default: [])
            let previous = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let requests = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("lern.") }
            let pendingIDs = Set(requests.map(\.identifier))
            var plans: [DeliveryPlan] = [], cursors: [String: SelectionCursor] = [:]
            for slot in slots {
                guard let rule = active.first(where: { $0.id == slot.ruleID }), let pool = pools[rule.id], !pool.isEmpty else { continue }
                if let plan = previous[slot.id], plan.revision == slot.revision, pool.contains(plan.entryID), plan.state != "cancelled" {
                    plans.append(plan); continue
                }
                let key = "cursor.reminder." + rule.id
                var cursor: SelectionCursor
                if let cached = cursors[key] { cursor = cached } else { cursor = try await store.get(key, default: SelectionCursor()) }
                guard let id = SelectionEngine.next(ids: pool, mode: rule.mode, cursor: &cursor) else { continue }
                cursors[key] = cursor
                plans.append(DeliveryPlan(id: slot.id, ruleID: rule.id, revision: rule.revision, date: slot.date, entryID: id, topicID: rule.source.topicIDs.first ?? ""))
            }
            let validIDs = Set(plans.filter { previous[$0.id]?.entryID == $0.entryID && previous[$0.id]?.revision == $0.revision }.map(\.id))
            center.removePendingNotificationRequests(withIdentifiers: requests.filter { !validIDs.contains($0.identifier) }.map(\.identifier))
            // Persist plans before submitting requests so a relaunch can recover interrupted scheduling.
            try await store.put("plans", plans)
            for (key, cursor) in cursors { try await store.put(key, cursor) }
            for index in plans.indices {
                if validIDs.contains(plans[index].id) && pendingIDs.contains(plans[index].id) { plans[index].state = "scheduled"; continue }
                guard let entry = try await store.entry(plans[index].entryID), let rule = rules.first(where: { $0.id == plans[index].ruleID }) else { continue }
                let content = UNMutableNotificationContent()
                content.title = rule.name.isEmpty ? Product.name : String(rule.name.prefix(80))
                content.body = String(entry.draft.text.prefix(500)) + (entry.draft.text.count > 500 ? "…" : "")
                content.userInfo = ["entryID": entry.id, "topicID": plans[index].topicID, "ruleID": rule.id, "planID": plans[index].id]
                content.threadIdentifier = rule.id
                if rule.sound == "default" { content.sound = .default }
                else if ["chime1", "chime2", "chime3"].contains(rule.sound) { content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: rule.sound + ".caf")) }
                let parts = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day, .hour, .minute, .second], from: plans[index].date)
                let request = UNNotificationRequest(identifier: plans[index].id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
                try await center.add(request)
                plans[index].state = "scheduled"
                if previous[plans[index].id] == nil { try await store.record(entry.id, kind: "scheduled") }
            }
            try await store.put("plans", plans)
            let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("lern.") }
            pendingCount = pending.count; scheduledThrough = plans.filter { $0.state == "scheduled" }.map(\.date).max(); lastError = nil
        } catch { lastError = error.localizedDescription }
    }
    func opened(_ planID: String) async {
        do {
            var plans: [DeliveryPlan] = try await store.get("plans", default: [])
            if let index = plans.firstIndex(where: { $0.id == planID }) { plans[index].state = "opened"; plans[index].openedAt = Date(); try await store.put("plans", plans) }
        } catch { lastError = error.localizedDescription }
    }
}
