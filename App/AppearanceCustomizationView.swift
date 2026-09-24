import SwiftUI
import LERNCore

// MARK: - Glass Effect & Atmosphere Customization

struct AppearanceCustomizationView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        @Bindable var state = state
        Form {
            // Live Glass Preview
            Section("Preview") {
                ZStack {
                    ThemeBackground(theme: state.activeTheme)

                    VStack(spacing: 12) {
                        LogoGlassPreview(
                            appearance: glassAppearance,
                            tint: glassTint,
                            intensity: state.preferences.glassIntensity
                        )
                    }
                    .padding(.vertical, 24)
                }
                .frame(minHeight: 180)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityLabel("Glass effect preview")
            }

            // Glass Appearance & Tint Controls
            Section("Glass Effect") {
                Picker("Appearance", selection: $state.preferences.glassAppearance) {
                    Text("System").tag(GlassAppearance.automatic.rawValue)
                    Text("Regular").tag(GlassAppearance.regular.rawValue)
                    Text("Clear").tag(GlassAppearance.clear.rawValue)
                    Text("Off").tag(GlassAppearance.off.rawValue)
                }

                ColorPicker("Glass tint", selection: color($state.preferences.glassTintColor, fallback: state.activeTheme.secondary), supportsOpacity: false)

                LabeledContent("Tint intensity") {
                    Slider(value: $state.preferences.glassIntensity, in: 0...1)
                        .frame(maxWidth: 180)
                        .accessibilityLabel("Tint intensity")
                }

                if reduceTransparency {
                    Text("Reduce Transparency is enabled in iOS Settings, so LERN uses an opaque surface for legibility.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Reset glass to system") {
                    state.preferences.glassAppearance = GlassAppearance.automatic.rawValue
                    state.preferences.glassTintColor = ""
                    state.preferences.glassIntensity = 0.35
                }
            }
        }
        .navigationTitle("Glass Effect")
        .onDisappear {
            Task {
                await state.savePreferences(notificationImpact: false, reloadWidgets: false)
            }
        }
    }

    private var glassAppearance: GlassAppearance {
        GlassAppearance(rawValue: state.preferences.glassAppearance) ?? .automatic
    }

    private var glassTint: Color {
        Color(hex: state.preferences.glassTintColor.isEmpty ? state.activeTheme.secondary : state.preferences.glassTintColor)
    }

    private func color(_ hex: Binding<String>, fallback: String) -> Binding<Color> {
        Binding(
            get: { Color(hex: hex.wrappedValue.isEmpty ? fallback : hex.wrappedValue) },
            set: { hex.wrappedValue = $0.hexValue }
        )
    }
}

// MARK: - Micro-Interactive Favorite Button

struct FeedFavoriteButton: View {
    let entry: EntryValue
    let foregroundColor: Color
    let onToggle: () async -> Void

    @Environment(AppState.self) private var state
    @State private var isAnimating = false

    var body: some View {
        Button {
            triggerFavorite()
        } label: {
            ZStack {
                Image(systemName: "heart.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color.pink)
                    .opacity(entry.favorite ? 1 : 0)
                    .scaleEffect(entry.favorite ? 1.0 : 0.4)

                Image(systemName: "heart")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(foregroundColor)
                    .opacity(entry.favorite ? 0 : 1)
                    .scaleEffect(entry.favorite ? 0.4 : 1.0)
            }
            .symbolEffect(.bounce, value: isAnimating)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(entry.favorite ? "Remove favorite" : "Favorite")
        .accessibilityAddTraits(entry.favorite ? [.isSelected] : [])
        .accessibilityIdentifier("feed.favorite")
    }

    private func triggerFavorite() {
        if state.preferences.haptics {
            let style: UIImpactFeedbackGenerator.FeedbackStyle = entry.favorite ? .soft : .medium
            UIImpactFeedbackGenerator(style: style).impactOccurred()
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.52)) {
            isAnimating.toggle()
        }
        Task {
            await onToggle()
        }
    }
}

private struct LogoGlassPreview: View {
    let appearance: GlassAppearance
    let tint: Color
    let intensity: Double

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .medium))
            Text("LERN")
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .tracking(4)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
        .lernGlassCard(cornerRadius: 22, appearance: appearance, tint: tint, intensity: intensity, elevation: .medium)
    }
}

struct LogoGlassChrome: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let tint = Color(hex: state.preferences.glassTintColor.isEmpty ? state.activeTheme.secondary : state.preferences.glassTintColor)
        Text("LERN")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .tracking(2)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .lernGlass(
                shape: Capsule(),
                appearance: GlassAppearance(rawValue: state.preferences.glassAppearance) ?? .automatic,
                tint: tint,
                intensity: state.preferences.glassIntensity,
                elevation: .low
            )
            .accessibilityLabel("LERN")
    }
}
