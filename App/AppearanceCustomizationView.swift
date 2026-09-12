import SwiftUI
import LERNCore

struct AppearanceCustomizationView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        @Bindable var state = state
        Form {
            Section("Preview") {
                ThemeBackground(theme: state.activeTheme)
                    .overlay {
                        LogoGlassPreview(variant: logoVariant, primary: logoPrimary, accent: logoAccent, foreground: state.activeTheme.textColor, appearance: glassAppearance, tint: glassTint, intensity: state.preferences.glassIntensity, reduceTransparency: reduceTransparency)
                    }
                    .frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 18)).accessibilityLabel("Logo and glass preview")
            }
            Section("Logo") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 14)], spacing: 18) {
                    ForEach(LogoVariant.allCases, id: \.rawValue) { variant in
                        Button { state.preferences.logoVariantID = variant.rawValue } label: {
                            VStack(spacing: 6) {
                                LogoMark(variant: variant, primary: logoPrimary, accent: logoAccent).frame(width: 46, height: 46)
                                Text(LocalizedStringKey(variant.displayName)).font(.caption2).lineLimit(1)
                                if variant == logoVariant { Image(systemName: "checkmark.circle.fill").accessibilityHidden(true) }
                            }.frame(maxWidth: .infinity, minHeight: 84)
                        }.buttonStyle(.plain).accessibilityLabel(LocalizedStringKey("Logo " + variant.displayName + (variant == logoVariant ? ", selected" : "")))
                            .accessibilityAddTraits(variant == logoVariant ? .isSelected : [])
                    }
                }
                ColorPicker("Primary logo color", selection: color($state.preferences.logoPrimaryColor, fallback: state.activeTheme.foreground), supportsOpacity: false)
                ColorPicker("Accent logo color", selection: color($state.preferences.logoAccentColor, fallback: state.activeTheme.secondary), supportsOpacity: false)
                Button("Reset logo to theme") { state.preferences.logoVariantID = LogoVariant.fallback.rawValue; state.preferences.logoPrimaryColor = ""; state.preferences.logoAccentColor = "" }
            }
            Section("Glass") {
                Picker("Appearance", selection: $state.preferences.glassAppearance) {
                    Text("System").tag(GlassAppearance.automatic.rawValue)
                    Text("Regular").tag(GlassAppearance.regular.rawValue)
                    Text("Clear").tag(GlassAppearance.clear.rawValue)
                    Text("Off").tag(GlassAppearance.off.rawValue)
                }
                ColorPicker("Glass tint", selection: color($state.preferences.glassTintColor, fallback: state.activeTheme.secondary), supportsOpacity: false)
                LabeledContent("Tint intensity") { Slider(value: $state.preferences.glassIntensity, in: 0...1).frame(maxWidth: 180) }
                if reduceTransparency { Text("Reduce Transparency is enabled, so LERN uses an opaque preview for readability.").font(.caption).foregroundStyle(.secondary) }
                Button("Reset glass to system") { state.preferences.glassAppearance = GlassAppearance.automatic.rawValue; state.preferences.glassTintColor = ""; state.preferences.glassIntensity = 0.35 }
            }
        }
        .navigationTitle("Logo & Glass")
        .onDisappear { Task { await state.savePreferences(notificationImpact: false, reloadWidgets: false) } }
    }

    private var logoVariant: LogoVariant { LogoVariant(rawValue: state.preferences.logoVariantID) ?? .fallback }
    private var glassAppearance: GlassAppearance { GlassAppearance(rawValue: state.preferences.glassAppearance) ?? .automatic }
    private var logoPrimary: Color { Color(hex: state.preferences.logoPrimaryColor.isEmpty ? state.activeTheme.foreground : state.preferences.logoPrimaryColor) }
    private var logoAccent: Color { Color(hex: state.preferences.logoAccentColor.isEmpty ? state.activeTheme.secondary : state.preferences.logoAccentColor) }
    private var glassTint: Color { Color(hex: state.preferences.glassTintColor.isEmpty ? state.activeTheme.secondary : state.preferences.glassTintColor) }
    private func color(_ hex: Binding<String>, fallback: String) -> Binding<Color> {
        Binding(get: { Color(hex: hex.wrappedValue.isEmpty ? fallback : hex.wrappedValue) }, set: { hex.wrappedValue = $0.hexValue })
    }
}

private extension View {
    @ViewBuilder func adaptiveGlass(appearance: GlassAppearance, tint: Color, intensity: Double, interactive: Bool, reduceTransparency: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        if reduceTransparency {
            self.background(tint.opacity(0.9), in: shape)
        } else if appearance == .off {
            self.background(tint.opacity(0.12 + intensity * 0.18), in: shape)
        } else if #available(iOS 26.0, *) {
            let glass: Glass = (appearance == .clear ? Glass.clear : Glass.regular).tint(tint.opacity(0.25 + intensity * 0.5)).interactive(interactive)
            self.glassEffect(glass, in: shape)
        } else {
            self.background(.regularMaterial, in: shape).overlay(shape.fill(tint.opacity(intensity * 0.12)))
        }
    }
}

private struct LogoGlassPreview: View {
    let variant: LogoVariant
    let primary: Color
    let accent: Color
    let foreground: Color
    let appearance: GlassAppearance
    let tint: Color
    let intensity: Double
    let reduceTransparency: Bool
    var card: some View {
        VStack(spacing: 14) {
            LogoMark(variant: variant, primary: primary, accent: accent).frame(width: 84, height: 84)
            Text("LERN").font(.system(.title2, design: .rounded).weight(.semibold)).tracking(4)
        }.foregroundStyle(foreground).padding(24).adaptiveGlass(appearance: appearance, tint: tint, intensity: intensity, interactive: false, reduceTransparency: reduceTransparency)
    }
    @ViewBuilder var body: some View {
        if #available(iOS 26.0, *) { GlassEffectContainer(spacing: 12) { card } }
        else { card }
    }
}

struct LogoGlassChrome: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        let variant = LogoVariant(rawValue: state.preferences.logoVariantID) ?? .fallback
        let primary = Color(hex: state.preferences.logoPrimaryColor.isEmpty ? state.activeTheme.foreground : state.preferences.logoPrimaryColor)
        let accent = Color(hex: state.preferences.logoAccentColor.isEmpty ? state.activeTheme.secondary : state.preferences.logoAccentColor)
        let tint = Color(hex: state.preferences.glassTintColor.isEmpty ? state.activeTheme.secondary : state.preferences.glassTintColor)
        LogoMark(variant: variant, primary: primary, accent: accent).frame(width: 26, height: 26).padding(7)
            .adaptiveGlass(appearance: GlassAppearance(rawValue: state.preferences.glassAppearance) ?? .automatic, tint: tint, intensity: state.preferences.glassIntensity, interactive: false, reduceTransparency: reduceTransparency)
            .accessibilityLabel("LERN logo")
    }
}
