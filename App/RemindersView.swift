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
                Text("Choose what each reminder says and how its topic is presented. Focus, Silent Mode and Scheduled Summary can still affect delivery.").font(.caption).foregroundStyle(.secondary)
                if let error = state.scheduler.lastError { Text(error).foregroundStyle(.red) }
            }
            Section("Delivery diagnostics") {
                DisclosureGroup("iOS delivery details") {
                    LabeledContent("Alerts", value: presentation(state.scheduler.settings.alerts))
                    LabeledContent("Sound", value: presentation(state.scheduler.settings.sounds))
                    LabeledContent("Notification Center", value: presentation(state.scheduler.settings.notificationCenter))
                    LabeledContent("Lock Screen", value: presentation(state.scheduler.settings.lockScreen))
                    LabeledContent("Scheduled Summary", value: presentation(state.scheduler.settings.scheduledDelivery))
                    LabeledContent("Time Sensitive", value: presentation(state.scheduler.settings.timeSensitive))
                }
            }
            Section("Reminder groups") {
                ForEach(state.reminders) { rule in
                    Button { edit = rule } label: {
                        HStack { Text(rule.notificationSymbol?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? rule.notificationSymbol! : (rule.isAlarm ? "⏰" : "✦")).font(.title3).frame(width: 28); VStack(alignment: .leading, spacing: 5) { Text(topic(rule)); Text(summary(rule)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(rule.enabled ? "On" : "Off").font(.caption) }.padding(.vertical, 4)
                    }
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("reminders.rule")
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
        return times
    }
    private func topic(_ rule: ReminderRule) -> String {
        let topic = rule.notificationTopic?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return topic.isEmpty ? rule.name : topic
    }
    private func presentation(_ raw: String) -> String {
        switch raw {
        case "enabled": return String(localized: "Enabled")
        case "disabled": return String(localized: "Disabled")
        case "notSupported": return String(localized: "Not supported")
        default: return String(localized: "Unknown")
        }
    }
}
struct ReminderEditor: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State var rule: ReminderRule
    @State private var extraTime = Date()
    var body: some View {
        Form {
            Section("Reminder") { TextField("Reminder name", text: $rule.name); Toggle("Enabled", isOn: $rule.enabled); NavigationLink { SourcePicker(source: $rule.source) } label: { Label("Type of Content", systemImage: "square.stack") }; Picker("Order", selection: $rule.mode) { Text("Sequential").tag(SelectionMode.sequential); Text("Shuffle without repeats").tag(SelectionMode.shuffle); Text("Random").tag(SelectionMode.random) } }
            Section("Notification") {
                Picker("Heading", selection: titleMode) { Text("Topic").tag("topic"); Text("Entry section").tag("section"); Text("No heading").tag("none") }
                if titleMode.wrappedValue == "topic" { TextField("Topic title", text: topic) }
                if titleMode.wrappedValue == "section" { Text("Uses the section name stored with each entry. If there is no section, LERN uses the topic title.").font(.caption).foregroundStyle(.secondary) }
                TextField("Symbol or emoji", text: symbol).textInputAutocapitalization(.never)
                ColorPicker("Preview color", selection: tint, supportsOpacity: false)
                NotificationPreview(rule: rule)
                Text("The symbol is added to the title. iOS uses the selected LERN app icon in the notification list.").font(.caption).foregroundStyle(.secondary)
            }
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
    private var titleMode: Binding<String> { Binding(get: { rule.notificationTitleMode ?? "topic" }, set: { rule.notificationTitleMode = $0 }) }
    private var topic: Binding<String> { Binding(get: { rule.notificationTopic ?? "" }, set: { rule.notificationTopic = String($0.prefix(DataLimits.metadataCharacters)) }) }
    private var symbol: Binding<String> { Binding(get: { rule.notificationSymbol ?? "" }, set: { rule.notificationSymbol = String($0.prefix(16)) }) }
    private var tint: Binding<Color> { Binding(get: { Color(hex: rule.notificationTint ?? "6E60F8") }, set: { rule.notificationTint = $0.hexValue }) }
}

private struct NotificationPreview: View {
    let rule: ReminderRule
    private var topic: String {
        let custom = rule.notificationTopic?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? rule.name : custom
    }
    var body: some View {
        let titleMode = rule.notificationTitleMode ?? "topic"
        HStack(alignment: .top, spacing: 12) {
            Text(rule.notificationSymbol?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? rule.notificationSymbol! : "✦")
                .font(.title2).frame(width: 42, height: 42).background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                if titleMode != "none" { Text(titleMode == "section" ? "Entry section" : topic).font(.subheadline.weight(.semibold)) }
                Text("A short thought will appear here.").font(.subheadline).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white).padding(14)
        .background(Color(hex: rule.notificationTint ?? "6E60F8").opacity(0.82), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Notification preview")
    }
}
