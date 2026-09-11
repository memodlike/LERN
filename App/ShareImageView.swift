import SwiftUI
import Photos
import LERNCore

struct ShareImageView: View {
    @Environment(AppState.self) private var state
    let entry: EntryValue
    let wallpaperTheme: ThemeValue?
    let wallpaperBlur: Double
    let wallpaperFocalX: Double
    let wallpaperFocalY: Double
    @State private var format = "square"
    @State private var image: UIImage?
    @State private var activity = false
    @State private var saving = false
    @State private var saved = false
    init(entry: EntryValue, initialFormat: String = "square", wallpaperTheme: ThemeValue? = nil, wallpaperBlur: Double = 0, wallpaperFocalX: Double = 0.5, wallpaperFocalY: Double = 0.5) {
        self.entry = entry
        self.wallpaperTheme = wallpaperTheme
        self.wallpaperBlur = wallpaperBlur
        self.wallpaperFocalX = wallpaperFocalX
        self.wallpaperFocalY = wallpaperFocalY
        _format = State(initialValue: initialFormat)
    }
    var size: CGSize { switch format { case "story": CGSize(width: 432, height: 768); case "portrait": CGSize(width: 432, height: 540); case "wallpaper": CGSize(width: 430, height: 932); default: CGSize(width: 540, height: 540) } }
    var body: some View {
        @Bindable var state = state
        ScrollView {
            VStack(spacing: 24) {
                if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 380).clipShape(RoundedRectangle(cornerRadius: 16)).accessibilityIdentifier("share.preview").accessibilityLabel("Quote image") }
                Picker("Format", selection: $format) { Text("Square").tag("square"); Text("4:5").tag("portrait"); Text("Story").tag("story"); Text("Wallpaper").tag("wallpaper") }.pickerStyle(.segmented)
                Toggle("Show LERN watermark", isOn: $state.preferences.watermark)
                Button("Share image", systemImage: "square.and.arrow.up") { activity = true }.buttonStyle(.borderedProminent).foregroundStyle(.white).controlSize(.large).disabled(image == nil)
                Button("Save image", systemImage: "square.and.arrow.down") { Task { await save() } }.disabled(image == nil || saving).frame(minHeight: 44)
                if saved { Label("Image saved", systemImage: "checkmark.circle") }
                ShareLink(item: entry.draft.text + (entry.draft.author.isEmpty ? "" : "\n— " + entry.draft.author)) { Label("Share text", systemImage: "text.quote") }.frame(minHeight: 44)
                if entry.draft.text.count > 600 { Text("Long entries use an excerpt in images. Share text includes the complete entry.").font(.footnote).foregroundStyle(.secondary) }
                Text("Available apps appear in the iOS share sheet.").font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.navigationTitle("Share your thought")
            .task(id: format) { render() }
            .onChange(of: state.preferences.watermark) { _, _ in render(); Task { await state.savePreferences() } }
            .sheet(isPresented: $activity) { if let image { ActivitySheet(items: [image]) } }
    }
    private func render() {
        let style = format == "wallpaper" ? (wallpaperTheme ?? state.activeTheme) : state.activeTheme
        let renderer = ImageRenderer(content: QuoteArtwork(entry: entry, theme: style, watermark: state.preferences.watermark, imageBlur: format == "wallpaper" ? wallpaperBlur : 0, focalX: format == "wallpaper" ? wallpaperFocalX : 0.5, focalY: format == "wallpaper" ? wallpaperFocalY : 0.5).frame(width: size.width, height: size.height))
        renderer.scale = 3; image = renderer.uiImage
    }
    private func save() async {
        guard let image else { return }; saving = true; defer { saving = false }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { state.error = String(localized: "Allow photo access in Settings to save images. You can also use Share image and Save to Files."); return }
        do { try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: image) }; saved = true; state.notice = String(localized: "Image saved") }
        catch { state.error = error.localizedDescription }
    }
}
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
