import SwiftUI
import PhotosUI
import LERNCore
import ImageIO

struct ThemesView: View {
    @Environment(AppState.self) private var state
    @State private var editing: ThemeValue?
    let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]
    var body: some View {
        @Bindable var state = state
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(state.themes) { theme in
                        Button { state.preferences.themeID = theme.id; Task { await state.savePreferences() } } label: {
                            ZStack {
                                ThemeBackground(theme: theme)
                                VStack(spacing: 20) { Spacer(); Text("A little room\nto think.").font(.system(.title3, design: theme.design)).multilineTextAlignment(.center); Spacer(); HStack { Text(theme.name).font(.caption.weight(.medium)); Spacer(); if state.preferences.themeID == theme.id { Image(systemName: "checkmark.circle.fill") } } }
                                    .foregroundStyle(theme.textColor).padding(16)
                            }.frame(height: 210).clipShape(RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(.plain).contextMenu { Button("Edit theme") { editing = theme } }
                    }
                }
                Button("Edit current theme", systemImage: "slider.horizontal.3") { editing = state.activeTheme }.frame(minHeight: 44)
                Button("Create a theme", systemImage: "plus") { editing = ThemeValue(name: String(localized: "My theme")) }.frame(minHeight: 44)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Theme Mix").font(.title2.bold())
                    Picker("Rotate themes", selection: $state.preferences.themeRotation) { Text("Fixed").tag("fixed"); Text("Every entry").tag("entry"); Text("Every day").tag("day") }.pickerStyle(.segmented)
                    ForEach(state.themes) { theme in Toggle(theme.name, isOn: Binding(get: { state.preferences.themeMixIDs.contains(theme.id) }, set: { on in if on { state.preferences.themeMixIDs.append(theme.id) } else { state.preferences.themeMixIDs.removeAll { $0 == theme.id } }; Task { await state.savePreferences() } })) }
                }
            }.padding(20)
        }.navigationTitle("Themes")
            .onChange(of: state.preferences.themeRotation) { _, _ in Task { state.rotateTheme(); await state.savePreferences() } }
            .sheet(item: $editing) { theme in NavigationStack { ThemeEditor(theme: theme) }.environment(state) }
    }
}
struct ThemeEditor: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State var theme: ThemeValue
    @State private var photo: PhotosPickerItem?
    @State private var photoBusy = false
    var body: some View {
        Form {
            Section { ZStack { ThemeBackground(theme: theme); Text("Give your thoughts\na place to breathe.").font(.system(.title2, design: theme.design)).fontWeight(theme.fontWeight).multilineTextAlignment(theme.textAlignment).foregroundStyle(theme.textColor).padding(24) }.frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 16)) }
            Section { TextField("Theme name", text: $theme.name)
                Picker("Font", selection: $theme.font) { Text("Rounded").tag("rounded"); Text("Serif").tag("serif"); Text("System").tag("default"); Text("Monospaced").tag("monospaced") }
                Picker("Weight", selection: $theme.weight) { Text("Regular").tag("regular"); Text("Medium").tag("medium"); Text("Bold").tag("bold") }
                Picker("Alignment", selection: $theme.alignment) { Text("Left").tag("leading"); Text("Center").tag("center"); Text("Right").tag("trailing") }
                ColorPicker("Text color", selection: color($theme.foreground), supportsOpacity: false)
                ColorPicker("Background", selection: color($theme.background), supportsOpacity: false)
                Toggle("Horizon light", isOn: $theme.gradient)
                if theme.gradient { ColorPicker("Light color", selection: color($theme.secondary), supportsOpacity: false) }
                LabeledContent("Dark overlay") { Slider(value: $theme.overlay, in: 0...0.85).frame(maxWidth: 180).accessibilityLabel("Dark overlay") }
                LabeledContent("Readability", value: theme.hasLowContrast ? "Low contrast" : "Good")
                if theme.hasLowContrast { Button("Improve contrast") { theme.improveContrast() } }
            }
            Section {
                PhotosPicker(selection: $photo, matching: .images) { Label("Choose background photo", systemImage: "photo") }
                if photoBusy { ProgressView() }
                if theme.photoName != nil { Button("Remove photo", role: .destructive) { theme.photoName = nil } }
                Text("Keep text readable over your photo using the overlay and text color.").font(.caption)
            }
        }.navigationTitle("Edit theme")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { if let index = state.themes.firstIndex(where: { $0.id == theme.id }) { state.themes[index] = theme } else { state.themes.append(theme) }; state.preferences.themeID = theme.id; Task { await state.saveThemes(); dismiss() } }.disabled(theme.name.isEmpty || photoBusy) } }
            .task(id: photo) {
                guard let photo else { return }; photoBusy = true; defer { photoBusy = false }
                do {
                    guard let data = try await photo.loadTransferable(type: Data.self), data.count < 20_000_000 else { throw ImportFailure.tooLarge }
                    let file = try await Task.detached { () throws -> String in
                        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2048, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary), let jpg = UIImage(cgImage: image).jpegData(compressionQuality: 0.88) else { throw ImportFailure.malformed("Choose a valid photo.") }
                        try FileManager.default.createDirectory(at: SharedStore.photosDirectory, withIntermediateDirectories: true)
                        let name = UUID().uuidString + ".jpg"; try jpg.write(to: SharedStore.photosDirectory.appendingPathComponent(name), options: .atomic); return name
                    }.value
                    theme.photoName = file; theme.overlay = max(0.35, theme.overlay)
                } catch { state.error = error.localizedDescription }
            }
    }
    private func color(_ hex: Binding<String>) -> Binding<Color> { Binding(get: { Color(hex: hex.wrappedValue) }, set: { hex.wrappedValue = $0.hexValue }) }
}
