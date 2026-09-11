import Foundation
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
    private func luminance(_ hex: String) -> Double {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        let channels = [Double((value >> 16) & 255), Double((value >> 8) & 255), Double(value & 255)].map { component -> Double in
            let unit = component / 255
            return unit <= 0.04045 ? unit / 12.92 : pow((unit + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }
    var contrastRatio: Double {
        let foreground = luminance(foreground), background = luminance(background)
        return (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05)
    }
    var hasLowContrast: Bool { contrastRatio < 4.5 || (photoName != nil && overlay < 0.45) }
    mutating func improveContrast() {
        foreground = luminance(background) > 0.45 ? "142C46" : "FFFFFF"
        if photoName != nil { overlay = max(overlay, 0.45) }
    }
}
struct ThemeBackground: View {
    var theme: ThemeValue
    var imageBlur: Double = 0
    var focalX: Double = 0.5
    var focalY: Double = 0.5
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
                    if focalX == 0.5 && focalY == 0.5 && imageBlur == 0 {
                        Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    } else {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .scaleEffect(1.08)
                            .offset(x: (0.5 - min(1, max(0, focalX))) * geometry.size.width * 0.16,
                                    y: (0.5 - min(1, max(0, focalY))) * geometry.size.height * 0.16)
                            .blur(radius: min(20, max(0, imageBlur)))
                            .clipped()
                    }
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
    var imageBlur: Double = 0
    var focalX: Double = 0.5
    var focalY: Double = 0.5
    var body: some View {
        ZStack {
            ThemeBackground(theme: theme, imageBlur: imageBlur, focalX: focalX, focalY: focalY)
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
