import SwiftUI
import LERNCore

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(clean, radix: 16) ?? 0x142C46
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    var hexValue: String {
        #if os(iOS)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        #else
        return "142C46"
        #endif
    }
}
extension ThemeValue {
    var textColor: Color { Color(hex: foreground) }
    var design: Font.Design { font == "serif" ? .serif : font == "rounded" ? .rounded : font == "monospaced" ? .monospaced : .default }
    var fontWeight: Font.Weight { weight == "bold" ? .bold : weight == "medium" ? .medium : .regular }
    var textAlignment: TextAlignment { alignment == "leading" ? .leading : alignment == "trailing" ? .trailing : .center }
}
struct ThemeBackground: View {
    var theme: ThemeValue
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(hex: theme.background)
                if theme.gradient {
                    Ellipse().fill(Color(hex: theme.secondary)).frame(width: geometry.size.width * 1.7, height: geometry.size.height * 0.8)
                        .blur(radius: 70).offset(y: geometry.size.height * 0.55)
                }
                #if os(iOS)
                if let name = theme.photoName, let url = SharedStore.photoURL(name), let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
                #endif
                Color.black.opacity(max(0, min(0.85, theme.overlay)))
            }.clipped()
        }.ignoresSafeArea()
    }
}
struct QuoteArtwork: View {
    let entry: EntryValue
    let theme: ThemeValue
    var watermark = false
    var body: some View {
        ZStack {
            ThemeBackground(theme: theme)
            VStack(spacing: 28) {
                Spacer(minLength: 0)
                Text(String(entry.draft.text.prefix(600)) + (entry.draft.text.count > 600 ? "…" : "")).font(.system(size: entry.draft.text.count > 400 ? 26 : 38, weight: theme.fontWeight, design: theme.design))
                    .multilineTextAlignment(theme.textAlignment).minimumScaleFactor(0.3)
                if !entry.draft.author.isEmpty { Text(String(entry.draft.author.prefix(120))).font(.system(size: 17)).opacity(0.85) }
                if !entry.draft.source.isEmpty { Text(String(entry.draft.source.prefix(160))).font(.system(size: 13)).opacity(0.8) }
                Spacer(minLength: 0)
                if watermark { Text(Product.name).font(.system(size: 14, weight: .semibold)).tracking(4) }
            }.foregroundStyle(theme.textColor).padding(48)
        }
    }
}
