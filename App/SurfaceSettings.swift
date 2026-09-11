import SwiftUI
import PhotosUI
import ImageIO
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
    private func save() { Task { do { try await state.store.put("presets", state.presets); WidgetCenter.shared.reloadTimelines(ofKind: "LERNQuoteWidget") } catch { state.error = error.localizedDescription } } }
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
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { if let index = state.presets.firstIndex(where: { $0.id == preset.id }) { state.presets[index] = preset } else { state.presets.append(preset) }; Task { do { try await state.store.put("presets", state.presets); WidgetCenter.shared.reloadTimelines(ofKind: "LERNQuoteWidget"); dismiss() } catch { state.error = error.localizedDescription } } }.disabled(preset.name.isEmpty) } }
    }
}
struct SurfaceSettings: View {
    @Environment(AppState.self) private var state
    let surface: String
    private var source: Binding<ContentSource> {
        Binding(get: { surface == "watch" ? state.preferences.watchSource : state.preferences.lockSource }, set: { value in
            if surface == "watch" { state.preferences.watchSource = value } else { state.preferences.lockSource = value }
            Task { await state.savePreferences() }
        })
    }
    var body: some View {
        Form {
            NavigationLink("Type of Content") { SourcePicker(source: source) }
            if surface == "watch" {
                Text("The Watch receives a local selection of up to 100 entries from this source. Open LERN on your iPhone after changing it. No internet is required.")
                Button("Sync to Watch") { Task { await state.savePreferences(); await WatchBridge.shared.update(store: state.store, source: source.wrappedValue) } }
                if let date = WatchBridge.shared.lastSuccessfulSync { LabeledContent("Last sync") { Text(date, format: .dateTime.month(.abbreviated).day().hour().minute()) } }
                LabeledContent("Thoughts synced", value: WatchBridge.shared.syncedCount.formatted())
                if let error = WatchBridge.shared.lastSyncError { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                Text("Notifications follow Apple's normal iPhone and Watch mirroring rules.").font(.footnote)
            } else {
                Text("Add LERN to your Lock Screen from the wallpaper editor. This source is independent of Home Screen presets.")
            }
        }.navigationTitle(surface == "watch" ? "Apple Watch" : "Lock Screen Widgets")
    }
}
struct WallpaperView: View {
    @Environment(AppState.self) private var state
    @State private var preview: EntryValue?
    @State private var preparing = false
    @State private var photo: PhotosPickerItem?
    @State private var photoBusy = false
    private var source: Binding<ContentSource> {
        Binding(get: { state.preferences.wallpaperSource }, set: { state.preferences.wallpaperSource = $0 })
    }
    var body: some View {
        @Bindable var state = state
        Form {
            Section("Wallpaper preview") {
                if let entry = state.current {
                    QuoteArtwork(entry: entry, theme: state.wallpaperTheme, watermark: state.preferences.watermark, imageBlur: state.preferences.wallpaperBlur, focalX: state.preferences.wallpaperFocalX, focalY: state.preferences.wallpaperFocalY)
                        .frame(height: 250).clipShape(RoundedRectangle(cornerRadius: 16)).accessibilityLabel("Wallpaper preview")
                } else {
                    ContentUnavailableView("Choose content to preview", systemImage: "photo")
                }
            }
            Section("Content source") { NavigationLink("Type of Content") { SourcePicker(source: source) } }
            Section("Wallpaper style") {
                Toggle("Link style to app theme", isOn: $state.preferences.wallpaperUsesAppTheme)
                if !state.preferences.wallpaperUsesAppTheme {
                    Picker("Wallpaper theme", selection: $state.preferences.wallpaperThemeID) {
                        ForEach(state.themes) { Text($0.name).tag($0.id) }
                    }
                }
                Text(state.preferences.wallpaperUsesAppTheme ? "Wallpaper uses the current app theme until you turn this off." : "This style changes only generated wallpapers.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Background photo") {
                PhotosPicker(selection: $photo, matching: .images) { Label("Choose wallpaper photo", systemImage: "photo") }
                if photoBusy { ProgressView() }
                if state.preferences.wallpaperPhotoName != nil { Button("Remove wallpaper photo", role: .destructive) { state.preferences.wallpaperPhotoName = nil } }
                Text("Wallpaper photos are stored locally on this device.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Image adjustment") {
                LabeledContent("Dim") { Slider(value: wallpaperOverlay, in: 0...0.85).frame(maxWidth: 180) }
                LabeledContent("Blur") { Slider(value: $state.preferences.wallpaperBlur, in: 0...20, step: 1).frame(maxWidth: 180) }
                LabeledContent("Focus horizontally") { Slider(value: $state.preferences.wallpaperFocalX, in: 0...1).frame(maxWidth: 180) }
                LabeledContent("Focus vertically") { Slider(value: $state.preferences.wallpaperFocalY, in: 0...1).frame(maxWidth: 180) }
            }
            Section {
                Button("Preview and save wallpaper", systemImage: "photo.on.rectangle") { Task { await saveAndPreparePreview() } }.disabled(preparing || photoBusy)
                if preparing { ProgressView() }
            }
            Section("Set up in Shortcuts") {
                Label("Create a personal Time of Day automation in Shortcuts.", systemImage: "clock")
                Label("Add LERN's Get Wallpaper action.", systemImage: "photo")
                Label("Pass its image to Set Wallpaper Photo.", systemImage: "iphone")
                Label("Choose your Lock Screen and the automation's run behavior.", systemImage: "checkmark.circle")
                Text("LERN creates the image locally. Only your Shortcuts automation changes the wallpaper. iOS may require confirmation for your chosen automation settings.").font(.footnote)
            }
        }.navigationTitle("Wallpapers")
            .navigationDestination(item: $preview) { entry in
                ShareImageView(entry: entry, initialFormat: "wallpaper", wallpaperTheme: state.wallpaperTheme, wallpaperBlur: state.preferences.wallpaperBlur, wallpaperFocalX: state.preferences.wallpaperFocalX, wallpaperFocalY: state.preferences.wallpaperFocalY)
            }
            .onAppear { if state.preferences.wallpaperThemeID.isEmpty { state.preferences.wallpaperThemeID = state.activeTheme.id } }
            .task(id: photo) { await importPhoto() }
    }
    private var wallpaperOverlay: Binding<Double> {
        Binding(get: { state.preferences.wallpaperOverlay ?? state.wallpaperTheme.overlay }, set: { state.preferences.wallpaperOverlay = $0 })
    }
    private func saveAndPreparePreview() async {
        preparing = true; defer { preparing = false }
        await state.savePreferences(notificationImpact: false, reloadWidgets: false)
        do {
            guard let entry = try await state.store.next(source: state.preferences.wallpaperSource, surface: "wallpaper", mode: .shuffle) else {
                state.error = String(localized: "No entries match your wallpaper source. Choose another source or import content."); return
            }
            preview = entry
        } catch { state.error = error.localizedDescription }
    }
    private func importPhoto() async {
        guard let photo else { return }
        photoBusy = true; defer { photoBusy = false }
        do {
            guard let data = try await photo.loadTransferable(type: Data.self), data.count < 20_000_000 else { throw ImportFailure.tooLarge }
            let file = try await Task.detached { () throws -> String in
                guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2048, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary), let jpg = UIImage(cgImage: image).jpegData(compressionQuality: 0.88) else { throw ImportFailure.malformed("Choose a valid photo.") }
                try FileManager.default.createDirectory(at: SharedStore.photosDirectory, withIntermediateDirectories: true)
                let name = UUID().uuidString + ".jpg"; try jpg.write(to: SharedStore.photosDirectory.appendingPathComponent(name), options: .atomic); return name
            }.value
            state.preferences.wallpaperPhotoName = file
        } catch { state.error = error.localizedDescription }
    }
}
struct AppIconsView: View {
    @Environment(AppState.self) private var state
    private let icons = [("Horizon", ""), ("Minimal Black", "MinimalBlack"), ("Minimal White", "MinimalWhite"), ("Gradient", "Gradient"), ("Quote Mark", "QuoteMark"), ("Warm", "Warm"), ("Cool", "Cool")]
    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 16)]
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(icons, id: \.0) { name, key in
                    Button { select(key) } label: {
                        VStack(spacing: 9) {
                            ZStack(alignment: .topTrailing) {
                                if let image = UIImage(named: key.isEmpty ? "IconPreview" : key + "Preview") { Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 18)).accessibilityHidden(true) }
                                if (UIApplication.shared.alternateIconName ?? "") == key { Image(systemName: "checkmark.circle.fill").font(.title2).symbolRenderingMode(.palette).foregroundStyle(.white, .blue).accessibilityLabel("Selected") }
                            }.frame(width: 92, height: 92)
                            Text(LocalizedStringKey(name)).font(.caption.weight(.medium)).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.plain).accessibilityLabel(name + ((UIApplication.shared.alternateIconName ?? "") == key ? ", selected" : ""))
                }
            }.padding(20)
            Text("These previews show the installed icon assets. iOS applies its own appearance treatment.").font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 20)
        }.navigationTitle("App Icon")
    }
    private func select(_ key: String) {
        UIApplication.shared.setAlternateIconName(key.isEmpty ? nil : key) { error in
            if let error { Task { @MainActor in state.error = error.localizedDescription } }
        }
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
            LabeledContent("Network dependency", value: String(localized: "None for core operation"))
            LabeledContent("Database", value: "SwiftData · local")
            LabeledContent("Network polling", value: String(localized: "None"))
            LabeledContent("Background refresh", value: String(localized: "Best effort"))
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
