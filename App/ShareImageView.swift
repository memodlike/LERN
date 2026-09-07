import SwiftUI
import Photos
import LERNCore

struct ShareImageView: View {
    @Environment(AppState.self) private var state
    let entry: EntryValue
    @State private var format = "square"
    @State private var image: UIImage?
    @State private var activity = false
    @State private var saving = false
    init(entry: EntryValue, initialFormat: String = "square") {
        self.entry = entry
        _format = State(initialValue: initialFormat)
    }
    var size: CGSize { switch format { case "story": CGSize(width: 432, height: 768); case "portrait": CGSize(width: 432, height: 540); case "wallpaper": CGSize(width: 430, height: 932); default: CGSize(width: 540, height: 540) } }
    var body: some View {
        @Bindable var state = state
        ScrollView {
            VStack(spacing: 24) {
                if let image { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 380).clipShape(RoundedRectangle(cornerRadius: 16)) }
                Picker("Format", selection: $format) { Text("Square").tag("square"); Text("4:5").tag("portrait"); Text("Story").tag("story"); Text("Wallpaper").tag("wallpaper") }.pickerStyle(.segmented)
                Toggle("Show LERN watermark", isOn: $state.preferences.watermark)
                Button("Share image", systemImage: "square.and.arrow.up") { activity = true }.buttonStyle(.borderedProminent).controlSize(.large).disabled(image == nil)
                Button("Save image", systemImage: "square.and.arrow.down") { Task { await save() } }.disabled(image == nil || saving).frame(minHeight: 44)
                ShareLink(item: entry.draft.text + (entry.draft.author.isEmpty ? "" : "\n— " + entry.draft.author)) { Label("Share text", systemImage: "text.quote") }.frame(minHeight: 44)
                Text("Available apps appear in the iOS share sheet.").font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.navigationTitle("Share your thought")
            .task(id: format) { render() }
            .onChange(of: state.preferences.watermark) { _, _ in render(); Task { await state.savePreferences() } }
            .sheet(isPresented: $activity) { if let image { ActivitySheet(items: [image]) } }
    }
    private func render() {
        let renderer = ImageRenderer(content: QuoteArtwork(entry: entry, theme: state.activeTheme, watermark: state.preferences.watermark).frame(width: size.width, height: size.height))
        renderer.scale = 3; image = renderer.uiImage
    }
    private func save() async {
        guard let image else { return }; saving = true; defer { saving = false }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { state.error = String(localized: "Allow photo access in Settings to save images. You can also use Share image and Save to Files."); return }
        do { try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: image) }; state.notice = String(localized: "Image saved") }
        catch { state.error = error.localizedDescription }
    }
}
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
