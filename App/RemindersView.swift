import SwiftUI
import UserNotifications
import AVFoundation
import AudioToolbox
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
                Picker("Heading", selection: $rule.notificationTitleMode) { Text("Topic").tag(NotificationTitleMode.topic); Text("Entry section").tag(NotificationTitleMode.section); Text("No heading").tag(NotificationTitleMode.none) }
                if rule.notificationTitleMode == .topic { TextField("Topic title", text: topic) }
                if rule.notificationTitleMode == .section { Text("Uses the section name stored with each entry. If there is no section, LERN uses the topic title.").font(.caption).foregroundStyle(.secondary) }
                TextField("Symbol or emoji", text: symbol).textInputAutocapitalization(.never)
                NotificationPreview(rule: rule)
                Text("iOS controls the final notification appearance. This preview shows only the content LERN can choose.").font(.caption).foregroundStyle(.secondary)
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
            Section("Sound") { NavigationLink { ReminderSoundPicker(selection: $rule.sound) } label: { LabeledContent("Sound", value: ReminderSoundPicker.name(for: rule.sound)) } }
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
    private var topic: Binding<String> { Binding(get: { rule.notificationTopic ?? "" }, set: { rule.notificationTopic = String($0.prefix(DataLimits.metadataCharacters)) }) }
    private var symbol: Binding<String> { Binding(get: { rule.notificationSymbol ?? "" }, set: { rule.notificationSymbol = String($0.prefix(16)) }) }
}

private struct NotificationPreview: View {
    let rule: ReminderRule
    private var topic: String {
        let custom = rule.notificationTopic?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? rule.name : custom
    }
    var body: some View {
        let titleMode = rule.notificationTitleMode
        HStack(alignment: .top, spacing: 12) {
            Group {
                let symbol = rule.notificationSymbol?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if symbol.isEmpty {
                    Image(systemName: "app.badge").font(.title3)
                } else {
                    Text(symbol).font(.title3)
                }
            }
                .frame(width: 38, height: 38)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("LERN").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if titleMode != .none { Text(titleMode == .section ? "Entry section" : topic).font(.subheadline.weight(.semibold)) }
                Text("A short thought will appear here.").font(.subheadline).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.separator.opacity(0.6)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Notification content preview")
    }
}

@MainActor private final class ReminderSoundPreviewer {
    private var player: AVAudioPlayer?
    func play(_ sound: String) {
        stop()
        if sound == "default" { AudioServicesPlaySystemSound(1007); return }
        guard sound.hasPrefix("chime"), let url = Bundle.main.url(forResource: sound, withExtension: "caf") else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay(); player?.play()
        } catch { player = nil }
    }
    func stop() { player?.stop(); player = nil }
}

private struct ReminderSoundPicker: View {
    @Environment(AppState.self) private var state
    @Binding var selection: String
    @State private var previewer = ReminderSoundPreviewer()
    private let sounds = ["none", "default", "chime1", "chime2", "chime3"]
    var body: some View {
        List {
            Section {
                ForEach(sounds, id: \.self) { sound in
                    HStack {
                        Button { selection = sound } label: {
                            HStack { Text(Self.name(for: sound)); Spacer(); if selection == sound { Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityLabel("Selected") } }
                        }.buttonStyle(.plain).foregroundStyle(.primary)
                        if sound != "none" { Button { previewer.play(sound) } label: { Image(systemName: "play.circle").font(.title3) }.buttonStyle(.borderless).accessibilityLabel("Preview \(Self.name(for: sound))") }
                    }.padding(.vertical, 4)
                }
            } footer: { Text("Previews are played only when you tap Play and mix with other audio.") }
            Section("Haptics") {
                Button("Preview haptic", systemImage: "wave.3.right") { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                    .disabled(!state.preferences.haptics)
                if !state.preferences.haptics { Text("Turn on Haptics in General to preview it.").font(.caption).foregroundStyle(.secondary) }
            }
        }.navigationTitle("Reminder sound")
            .onDisappear { previewer.stop() }
    }
    static func name(for sound: String) -> String {
        switch sound { case "none": "No sound"; case "default": "System default"; case "chime1": "Soft chime 1"; case "chime2": "Soft chime 2"; case "chime3": "Soft chime 3"; default: "System default" }
    }
}
