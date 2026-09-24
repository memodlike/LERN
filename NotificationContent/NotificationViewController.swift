import UIKit
import SwiftUI
import UserNotifications
import UserNotificationsUI
import WidgetKit
import ImageIO
import LERNCore

/// Expanded (long-press) presentation of a LERN reminder: the full thought in the
/// reader's active theme instead of the system's truncated title + body.
final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private let model = NotificationQuoteModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let screenHeight = view.window?.windowScene?.screen.bounds.height ?? 844
        let root = NotificationQuoteView(
            model: model,
            maxHeight: screenHeight * 0.72,
            onHeight: { [weak self] height in self?.resize(to: height) },
            open: { [weak self] in self?.extensionContext?.performNotificationDefaultAction() }
        )
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        host.safeAreaRegions = []
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }

    func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        model.show(title: content.title, body: content.body, isAlarm: content.categoryIdentifier == "lern.alarm")
        let entryID = content.userInfo["entryID"] as? String
        Task { await model.load(entryID: entryID) }
    }

    private func resize(to height: CGFloat) {
        let size = CGSize(width: view.bounds.width, height: ceil(height))
        guard size.height > 0, abs(preferredContentSize.height - size.height) > 0.5 else { return }
        preferredContentSize = size
    }
}

@MainActor @Observable final class NotificationQuoteModel {
    var title = ""
    var text = ""
    var author = ""
    var source = ""
    var isAlarm = false
    var entryID: String?
    var favorite = false
    var theme = ThemeValue.starters[0]
    var photo: UIImage?
    var glassAppearance = GlassAppearance.automatic
    var glassTint: Color?
    var glassIntensity = 0.35

    func show(title: String, body: String, isAlarm: Bool) {
        self.title = title; self.text = body; self.isAlarm = isAlarm
    }

    func load(entryID: String?) async {
        guard let store = try? SharedStore.open() else { return }
        let preferences = (try? await store.get("preferences", default: Preferences())) ?? Preferences()
        let themes = (try? await store.get("themes", default: ThemeValue.starters)) ?? ThemeValue.starters
        var theme = themes.first { $0.id == preferences.themeID } ?? ThemeValue.starters[0]
        if let name = theme.photoName, let url = SharedStore.photoURL(name) { photo = Self.downsampledImage(at: url, maxPixel: 1400) }
        theme.photoName = nil
        self.theme = theme
        glassAppearance = GlassAppearance(rawValue: preferences.glassAppearance) ?? .automatic
        glassTint = Color(hex: preferences.glassTintColor.isEmpty ? theme.secondary : preferences.glassTintColor)
        glassIntensity = preferences.glassIntensity
        guard let entryID, FavoriteMutation.isEntryID(entryID), let entry = try? await store.entry(entryID) else { return }
        self.entryID = entry.id
        text = entry.draft.text
        author = entry.draft.author
        source = Self.isReference(entry.draft.source) ? "" : entry.draft.source
        favorite = entry.favorite
    }

    /// Import provenance (links, file paths) is library metadata, not something to read in a notification.
    private static func isReference(_ value: String) -> Bool {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.contains("://") || text.hasPrefix("www.") { return true }
        guard !text.contains(" ") else { return false }
        let fileExtensions = ["pdf", "txt", "md", "csv", "json", "jsonl", "epub", "docx", "html"]
        return text.contains("/") || fileExtensions.contains((text as NSString).pathExtension)
    }

    func toggleFavorite() async {
        guard let entryID, let store = try? SharedStore.open() else { return }
        let next = !favorite
        favorite = next
        do {
            try await store.setFlag(entryID, flag: "favorite", value: next)
            SharedStore.markNotificationScheduleDirty()
            WidgetCenter.shared.reloadTimelines(ofKind: "LERNQuoteWidget")
        } catch { favorite = !next }
    }

    /// Extensions run under a tight memory budget, so theme photos are decoded at display size.
    private static func downsampledImage(at url: URL, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

struct NotificationQuoteView: View {
    let model: NotificationQuoteModel
    let maxHeight: CGFloat
    let onHeight: (CGFloat) -> Void
    let open: () -> Void
    @State private var bodyHeight: CGFloat = 0
    @ScaledMetric(relativeTo: .title) private var scale: CGFloat = 1

    private var theme: ThemeValue { model.theme }
    private var horizontal: HorizontalAlignment { theme.alignment == "leading" ? .leading : theme.alignment == "trailing" ? .trailing : .center }
    private var frameAlignment: Alignment { theme.alignment == "leading" ? .leading : theme.alignment == "trailing" ? .trailing : .center }
    private var quoteSize: CGFloat {
        let count = model.text.count
        let base: CGFloat = count <= 90 ? 30 : count <= 200 ? 25 : count <= 400 ? 21 : 18
        return base * scale
    }
    // Header + footer + paddings; the quote scrolls once it exceeds the remaining space.
    private var maxBodyHeight: CGFloat { max(160, maxHeight - 150) }

    var body: some View {
        VStack(spacing: 18) {
            header
            ScrollView {
                quote.onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { bodyHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .frame(height: bodyHeight == 0 ? nil : min(bodyHeight, maxBodyHeight))
            footer
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .foregroundStyle(theme.textColor)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { onHeight($0) }
        .frame(maxHeight: .infinity, alignment: .top)
        .background { background }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: model.isAlarm ? "alarm" : "text.quote")
            Text(model.title.isEmpty ? Product.name : model.title).lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.system(.footnote, design: theme.design).weight(.semibold))
        .opacity(0.8)
        .accessibilityElement(children: .combine)
    }

    private var quote: some View {
        VStack(alignment: horizontal, spacing: 16) {
            Text(model.text)
                .font(.system(size: quoteSize, weight: theme.fontWeight, design: theme.design))
                .lineSpacing(quoteSize * 0.18)
                .multilineTextAlignment(theme.textAlignment)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if !model.author.isEmpty || !model.source.isEmpty {
                Capsule().fill(theme.textColor.opacity(0.35)).frame(width: 28, height: 2)
                VStack(alignment: horizontal, spacing: 4) {
                    if !model.author.isEmpty {
                        Text(model.author).font(.system(.callout, design: theme.design).weight(.semibold))
                    }
                    if !model.source.isEmpty {
                        Text(model.source).font(.system(.footnote, design: theme.design)).italic().opacity(0.8)
                    }
                }
                .multilineTextAlignment(theme.textAlignment)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if model.entryID != nil {
                Button { Task { await model.toggleFavorite() } } label: {
                    Label(model.favorite ? "In favorites" : "Favorite", systemImage: model.favorite ? "heart.fill" : "heart")
                        .contentTransition(.symbolEffect(.replace))
                }
                .sensoryFeedback(.impact(weight: .light), trigger: model.favorite)
                .buttonStyle(NotificationGlassButtonStyle(model: model))
            }
            Spacer(minLength: 0)
            Button(action: open) { Label("Open in LERN", systemImage: "arrow.up.forward.app") }
                .buttonStyle(NotificationGlassButtonStyle(model: model))
        }
        .font(.system(.subheadline, design: theme.design).weight(.semibold))
    }

    private var background: some View {
        GeometryReader { geometry in
            ZStack {
                Color(hex: theme.background)
                if theme.gradient {
                    Ellipse().fill(Color(hex: theme.secondary))
                        .frame(width: geometry.size.width * 1.7, height: geometry.size.height * 0.8)
                        .blur(radius: 70).offset(y: geometry.size.height * 0.55)
                }
                if let photo = model.photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
                Color.black.opacity(max(0, min(0.85, theme.overlay)))
            }
        }
    }
}

private struct NotificationGlassButtonStyle: ButtonStyle {
    let model: NotificationQuoteModel
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .lernGlassCapsule(appearance: model.glassAppearance, tint: model.glassTint, intensity: model.glassIntensity, elevation: .low)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}
