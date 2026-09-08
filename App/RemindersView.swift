import SwiftUI
import UserNotifications
import LERNCore

struct RemindersView: View {
    @Environment(AppState.self) private var state
    @State private var edit: ReminderRule?
    var body: some View {
        List {
            Section {
                if state.scheduler.authorization == .notDetermined { Text("Let your own words meet you during the day."); Button("Enable notifications") { Task { await state.scheduler.requestPermission() } } }
                else if state.scheduler.authorization == .denied { Text("Notifications are turned off in iOS Settings."); Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } }
                else if state.scheduler.settings.alerts != "enabled" { Text("LERN may schedule reminders, but alerts are disabled in iOS Settings.") }
                else if state.scheduler.settings.sounds != "enabled" { Text("Alerts are enabled, but notification sounds are disabled in iOS Settings.") }
                else if state.scheduler.settings.scheduledDelivery == "enabled" { Text("Scheduled Summary may delay normal reminders.") }
                else { Text("Notifications are enabled. Focus and silent mode can still affect delivery.") }
                LabeledContent("Pending reminders", value: "\(state.scheduler.pendingCount) / 60")
                if let through = state.scheduler.scheduledThrough { LabeledContent("Scheduled through") { Text(through, format: .dateTime.month(.abbreviated).day().hour().minute()) } }
                if let through = state.scheduler.scheduledThrough {
                    let coverage = through.timeIntervalSinceNow
                    Text("Coverage: about \(max(0, Int(coverage / 3600))) hours.").font(.caption).foregroundStyle(.secondary)
                    if coverage < 3 * 24 * 60 * 60 { Label("This queue covers less than three days. Open LERN periodically so iOS can replenish personalized reminders.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                }
                Text("iOS accepts up to 60 local pending requests. Acceptance does not guarantee visible delivery: Focus, Silent Mode and Scheduled Summary still apply.").font(.caption).foregroundStyle(.secondary)
                if let error = state.scheduler.lastError { Text(error).foregroundStyle(.red) }
            }
            Section("iOS delivery diagnostics") {
                LabeledContent("Alerts", value: state.scheduler.settings.alerts)
                LabeledContent("Sound", value: state.scheduler.settings.sounds)
                LabeledContent("Notification Center", value: state.scheduler.settings.notificationCenter)
                LabeledContent("Lock Screen", value: state.scheduler.settings.lockScreen)
                LabeledContent("Scheduled Summary", value: state.scheduler.settings.scheduledDelivery)
                LabeledContent("Time Sensitive", value: state.scheduler.settings.timeSensitive)
            }
            Section("Reminder groups") {
                ForEach(state.reminders) { rule in
                    Button { edit = rule } label: {
                        HStack { Image(systemName: rule.isAlarm ? "alarm" : "bell"); VStack(alignment: .leading, spacing: 5) { Text(rule.name); Text(summary(rule)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(rule.enabled ? "On" : "Off").font(.caption) }.padding(.vertical, 4)
                    }.foregroundStyle(.primary)
                }.onDelete { indexes in state.reminders.remove(atOffsets: indexes); Task { await state.saveReminders() } }
                Button("Add reminder group", systemImage: "plus") { edit = ReminderRule() }.accessibilityIdentifier("reminders.add")
                Button("Add morning alarm", systemImage: "alarm") { var rule = ReminderRule(); rule.name = String(localized: "Morning thought"); rule.isAlarm = true; rule.explicitMinutes = [420]; edit = rule }
            }
            if ScheduleEngine.collisions(state.reminders) > 0 { Section { Label("Some reminder groups overlap. Both will be scheduled. Edit the times if you prefer more space between them.", systemImage: "exclamationmark.bubble") } }
        }.navigationTitle("Reminders")
            .sheet(item: $edit) { rule in NavigationStack { ReminderEditor(rule: rule) }.environment(state) }
            .task { _ = await state.scheduler.replenish() }
    }
    private func summary(_ rule: ReminderRule) -> String {
        let times = rule.minutes.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) }.joined(separator: ", ")
        return "\(rule.minutes.count)× · \(rule.weekdays.count)/7 · \(times)"
    }
}
struct ReminderEditor: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State var rule: ReminderRule
    @State private var extraTime = Date()
    var body: some View {
        Form {
            Section { TextField("Name", text: $rule.name); Toggle("Enabled", isOn: $rule.enabled); NavigationLink { SourcePicker(source: $rule.source) } label: { Label("Type of Content", systemImage: "square.stack") }; Picker("Order", selection: $rule.mode) { Text("Sequential").tag(SelectionMode.sequential); Text("Shuffle without repeats").tag(SelectionMode.shuffle); Text("Random").tag(SelectionMode.random) } }
            Section("Schedule") {
                Toggle("Spread across a time range", isOn: $rule.usesRange)
                if rule.usesRange {
                    DatePicker("From", selection: minuteBinding($rule.startMinute), displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: minuteBinding($rule.endMinute), displayedComponents: .hourAndMinute)
                    Stepper("\(rule.frequency) reminders a day", value: $rule.frequency, in: 1...60)
                } else {
                    ForEach(Array(rule.explicitMinutes.indices), id: \.self) { index in DatePicker("Time", selection: minuteBinding($rule.explicitMinutes[index]), displayedComponents: .hourAndMinute) }.onDelete { indexes in rule.explicitMinutes.remove(atOffsets: indexes) }
                    Button("Add time") { rule.explicitMinutes.append(min(1439, (rule.explicitMinutes.last ?? 480) + 60)) }.disabled(rule.explicitMinutes.count >= 60)
                }
            }
            Section("Days") {
                ForEach(1...7, id: \.self) { day in Toggle(Calendar.current.weekdaySymbols[day - 1], isOn: Binding(get: { rule.weekdays.contains(day) }, set: { on in if on { rule.weekdays.append(day) } else { rule.weekdays.removeAll { $0 == day } } })) }
                HStack { Button("Every day") { rule.weekdays = Array(1...7) }; Spacer(); Button("Weekdays") { rule.weekdays = Array(2...6) }; Spacer(); Button("Weekends") { rule.weekdays = [1, 7] } }.font(.caption).frame(minHeight: 44)
            }
            Section { Picker("Sound", selection: $rule.sound) { Text("No sound").tag("none"); Text("System default").tag("default"); ForEach(1...3, id: \.self) { Text("Soft chime \($0)").tag("chime\($0)") } } }
            if rule.isAlarm { Section { Text("This alarm is a local notification. It follows Focus and silent-mode settings and does not behave like a critical system alarm.").font(.footnote) } }
        }.navigationTitle(rule.isAlarm ? "Morning alarm" : "Reminder group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { rule.revision = UUID().uuidString; if let index = state.reminders.firstIndex(where: { $0.id == rule.id }) { state.reminders[index] = rule } else { state.reminders.append(rule) }; Task { await state.saveReminders(); dismiss() } }.disabled(rule.weekdays.isEmpty || rule.minutes.isEmpty || (rule.usesRange && rule.endMinute < rule.startMinute)) }
            }
    }
    private func minuteBinding(_ value: Binding<Int>) -> Binding<Date> {
        Binding(get: { Calendar.current.date(bySettingHour: value.wrappedValue / 60, minute: value.wrappedValue % 60, second: 0, of: Date()) ?? Date() }, set: { value.wrappedValue = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0) })
    }
}
