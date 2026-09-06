import SwiftUI
import LERNCore
import WidgetKit

struct WidgetPresetsView: View {
    @Environment(AppState.self) private var state
    @State private var editing: WidgetPreset?
    var body: some View {
        List {
            Section { Text("Add a LERN widget from your Home Screen, then edit it to choose a saved preset. iOS decides the final refresh time.").font(.subheadline) }
            ForEach(state.presets) { preset in Button { editing = preset } label: { Label(preset.name, systemImage: "rectangle.on.rectangle") } }
                .onDelete { state.presets.remove(atOffsets: $0); save() }
            Button("New widget preset", systemImage: "plus") { editing = WidgetPreset() }
        }.navigationTitle("Widget presets")
            .sheet(item: $editing) { preset in NavigationStack { WidgetPresetEditor(preset: preset) }.environment(state) }
    }
    private func save() { Task { do { try await state.store.put("presets", state.presets); WidgetCenter.shared.reloadAllTimelines() } catch { state.error = error.localizedDescription } } }
}
struct WidgetPresetEditor: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State var preset: WidgetPreset
    var body: some View {
        Form {
            TextField("Name", text: $preset.name)
            NavigationLink("Type of Content") { SourcePicker(source: $preset.source) }
            Picker("Theme", selection: $preset.themeID) { ForEach(state.themes) { Text($0.name).tag($0.id) } }
            Picker("Widget type", selection: $preset.kind) { Text("Daily content").tag("daily"); Text("Streak").tag("streak"); Text("Fortune").tag("fortune") }
            Picker("Refresh", selection: $preset.refreshMinutes) { Text("30 minutes").tag(30); Text("Hourly").tag(60); Text("Every 3 hours").tag(180); Text("Daily").tag(1440) }
            Picker("Order", selection: $preset.mode) { Text("Sequential").tag(SelectionMode.sequential); Text("Shuffle without repeats").tag(SelectionMode.shuffle); Text("Random").tag(SelectionMode.random) }
            Toggle("Border", isOn: $preset.border); Toggle("Show buttons", isOn: $preset.showButtons)
            Text("Medium and large widgets support favorite and open/share actions. Refresh timing is managed by iOS.").font(.footnote).foregroundStyle(.secondary)
        }.navigationTitle("Widget preset")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { if let index = state.presets.firstIndex(where: { $0.id == preset.id }) { state.presets[index] = preset } else { state.presets.append(preset) }; Task { do { try await state.store.put("presets", state.presets); WidgetCenter.shared.reloadAllTimelines(); dismiss() } catch { state.error = error.localizedDescription } } }.disabled(preset.name.isEmpty) } }
    }
}
struct SurfaceSettings: View {
    @Environment(AppState.self) private var state
    let surface: String
    @State private var source = ContentSource()
    var body: some View {
        Form {
            NavigationLink("Type of Content") { SourcePicker(source: $source) }
            if surface == "watch" {
                Text("The Watch receives a local selection of up to 100 entries from this source. Open LERN on your iPhone after changing it. No internet is required.")
                Button("Sync to Watch") { Task { await save(); await WatchBridge.shared.update(store: state.store, source: source) } }
                Text("Notifications follow Apple's normal iPhone and Watch mirroring rules.").font(.footnote)
            } else {
                Text("Add LERN to your Lock Screen from the wallpaper editor. This source is independent of Home Screen presets.")
            }
        }.navigationTitle(surface == "watch" ? "Apple Watch" : "Lock Screen Widgets")
            .task { source = surface == "watch" ? state.preferences.watchSource : state.preferences.lockSource }
            .onDisappear { Task { await save() } }
    }
    private func save() async { if surface == "watch" { state.preferences.watchSource = source } else { state.preferences.lockSource = source }; await state.savePreferences(); WidgetCenter.shared.reloadAllTimelines() }
}
struct WallpaperView: View {
    @Environment(AppState.self) private var state
    @State private var source = ContentSource()
    var body: some View {
        Form {
            Section { NavigationLink("Type of Content") { SourcePicker(source: $source) }; NavigationLink("Theme") { ThemesView() }; if let entry = state.current { NavigationLink("Preview and save wallpaper") { ShareImageView(entry: entry) } } }
            Section("Set up in Shortcuts") {
                Label("Create a personal Time of Day automation in Shortcuts.", systemImage: "clock")
                Label("Add LERN's Get Wallpaper action.", systemImage: "photo")
                Label("Pass its image to Set Wallpaper Photo.", systemImage: "iphone")
                Label("Choose your Lock Screen and the automation's run behavior.", systemImage: "checkmark.circle")
                Text("LERN creates the image locally. Only your Shortcuts automation changes the wallpaper. iOS may require confirmation for your chosen automation settings.").font(.footnote)
            }
        }.navigationTitle("Wallpapers").task { source = state.preferences.wallpaperSource }.onDisappear { state.preferences.wallpaperSource = source; Task { await state.savePreferences() } }
    }
}
struct AppIconsView: View {
    @Environment(AppState.self) private var state
    private let icons = [("Horizon", ""), ("Minimal Black", "MinimalBlack"), ("Minimal White", "MinimalWhite"), ("Gradient", "Gradient"), ("Quote Mark", "QuoteMark"), ("Warm", "Warm"), ("Cool", "Cool")]
    var body: some View {
        List {
            ForEach(icons, id: \.0) { name, key in
                Button { UIApplication.shared.setAlternateIconName(key.isEmpty ? nil : key) { error in if let error { Task { @MainActor in state.error = error.localizedDescription } } } } label: {
                    HStack { if let image = UIImage(named: key.isEmpty ? "IconPreview" : key + "Preview") { Image(uiImage: image).resizable().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true) }; Text(LocalizedStringKey(name)); Spacer(); if (UIApplication.shared.alternateIconName ?? "") == key { Image(systemName: "checkmark") } }.padding(.vertical, 5)
                }
            }
        }.navigationTitle("App Icon")
    }
}
struct DiagnosticsView: View {
    @Environment(AppState.self) private var state
    @State private var bytes: Int64 = 0
    var body: some View {
        Form {
            LabeledContent("Entries", value: state.total.formatted())
            LabeledContent("Topics", value: state.topics.count.formatted())
            LabeledContent("Local storage", value: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
            LabeledContent("Pending notifications", value: "\(state.scheduler.pendingCount) / 60")
            LabeledContent("Network dependency", value: String(localized: "None for core operation"))
            LabeledContent("Database", value: "SwiftData · local")
            LabeledContent("Background polling", value: String(localized: "None"))
            Text("Scheduled means iOS accepted a request, not proof that it was shown. Opened is recorded only after a notification or deep link is opened.").font(.footnote)
            Button("Refresh diagnostics") { Task { await state.scheduler.replenish(); await measure() } }
        }.navigationTitle("Diagnostics").task { await measure() }
    }
    private func measure() async {
        bytes = await Task.detached { () -> Int64 in
            let enumerator = FileManager.default.enumerator(at: SharedStore.directory, includingPropertiesForKeys: [.fileSizeKey])
            var result: Int64 = 0
            while let url = enumerator?.nextObject() as? URL { result += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            return result
        }.value
    }
}
