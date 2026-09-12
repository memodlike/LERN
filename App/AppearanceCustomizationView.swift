import SwiftUI
import LERNCore
import Photos

// MARK: - Logo & Icon Studio Models

enum PreviewMode: String, CaseIterable, Identifiable {
    case appIcon = "App Icon"
    case headerPill = "In-App Header"

    var id: String { rawValue }
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .appIcon: return "App Icon"
        case .headerPill: return "In-App Header"
        }
    }
}

enum LogoCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case geometric = "Geometric"
    case cosmic = "Cosmic & Flow"
    case reading = "Reading & Focus"
    case abstract = "Organic & Abstract"

    var id: String { rawValue }
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .all: return "All"
        case .geometric: return "Geometric"
        case .cosmic: return "Cosmic & Flow"
        case .reading: return "Reading & Focus"
        case .abstract: return "Organic & Abstract"
        }
    }

    func matches(_ variant: LogoVariant) -> Bool {
        switch self {
        case .all:
            return true
        case .geometric:
            return [.fold, .prism, .stack, .facet, .window].contains(variant)
        case .cosmic:
            return [.orbit, .portal, .northStar, .flow, .pulse].contains(variant)
        case .reading:
            return [.openPages, .bookmarkCut, .quoteSpark, .focus, .glyph].contains(variant)
        case .abstract:
            return [.seed, .loop, .steps, .link, .openFrame].contains(variant)
        }
    }
}

enum LogoSort: String, CaseIterable, Identifiable {
    case curated = "Curated"
    case alphabetical = "A–Z"

    var id: String { rawValue }
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .curated: return "Curated"
        case .alphabetical: return "A–Z"
        }
    }
}

// MARK: - Canvas View for App Icon & High-Res Export

struct AppIconCanvasView: View {
    let variant: LogoVariant
    let primary: Color
    let accent: Color
    let backgroundHex: String
    let glassAppearance: GlassAppearance
    let glassTint: Color
    let glassIntensity: Double
    let markScale: Double
    let size: CGFloat
    var isSquircle: Bool = true
    var showShadow: Bool = false

    private var cornerRadius: CGFloat {
        isSquircle ? size * 0.224 : 0
    }

    var body: some View {
        ZStack {
            // Base background
            Color(hex: backgroundHex)

            // Dynamic depth gradient
            LinearGradient(
                colors: [
                    Color.white.opacity(0.12),
                    Color.clear,
                    Color.black.opacity(0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Centered Logo Mark
            LogoMark(variant: variant, primary: primary, accent: accent)
                .frame(width: size * markScale, height: size * markScale)

            // Frosted glass tint overlay
            if glassAppearance != .off {
                glassTint.opacity(0.12 * glassIntensity)
            }

            // Specular rim light (Fresnel refraction)
            if isSquircle {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.42), location: 0.0),
                                .init(color: Color.white.opacity(0.10), location: 0.45),
                                .init(color: Color.black.opacity(0.25), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: max(1, size * 0.012)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(
            color: showShadow ? Color.black.opacity(0.35) : .clear,
            radius: showShadow ? size * 0.12 : 0,
            x: 0,
            y: showShadow ? size * 0.05 : 0
        )
    }
}

// MARK: - Unified Appearance Customization View

struct AppearanceCustomizationView: View {
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    // Preview
    @State private var previewMode: PreviewMode = .appIcon

    // Logo filter & sort
    @State private var selectedCategory: LogoCategory = .all
    @State private var sortOption: LogoSort = .curated

    // Icon customization settings
    @AppStorage("icon_bg_mode") private var iconBgMode: String = "theme"
    @AppStorage("icon_custom_bg_hex") private var customBgHex: String = "142C46"
    @AppStorage("icon_mark_scale") private var markScale: Double = 0.54

    // Alternate app icon & export
    @State private var alternateIconName: String = UIApplication.shared.alternateIconName ?? ""
    @State private var isExporting = false
    @State private var showSavedNotice = false
    @State private var shareSheetItem: UIImage?
    @State private var showShareSheet = false
    @State private var showShortcutsGuide = false
    @State private var statusMessage: String?

    private let systemIcons: [(name: String, key: String, preview: String)] = [
        ("Horizon", "", "IconPreview"),
        ("Minimal Black", "MinimalBlack", "MinimalBlackPreview"),
        ("Minimal White", "MinimalWhite", "MinimalWhitePreview"),
        ("Gradient", "Gradient", "GradientPreview"),
        ("Quote Mark", "QuoteMark", "QuoteMarkPreview"),
        ("Warm", "Warm", "WarmPreview"),
        ("Cool", "Cool", "CoolPreview")
    ]

    var body: some View {
        @Bindable var state = state
        Form {
            // 1. LIVE PREVIEW SECTION
            Section {
                VStack(spacing: 16) {
                    Picker("Preview Mode", selection: $previewMode) {
                        ForEach(PreviewMode.allCases) { mode in
                            Text(mode.localizedTitle).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if previewMode == .appIcon {
                        VStack(spacing: 12) {
                            AppIconCanvasView(
                                variant: logoVariant,
                                primary: logoPrimary,
                                accent: logoAccent,
                                backgroundHex: effectiveBackgroundHex,
                                glassAppearance: glassAppearance,
                                glassTint: glassTint,
                                glassIntensity: state.preferences.glassIntensity,
                                markScale: markScale,
                                size: 120,
                                isSquircle: true,
                                showShadow: true
                            )
                            .padding(.top, 8)

                            Text("LERN")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("App icon preview for \(logoVariant.displayName)")
                    } else {
                        VStack(spacing: 14) {
                            LogoGlassPreview(
                                variant: logoVariant,
                                primary: logoPrimary,
                                accent: logoAccent,
                                foreground: state.activeTheme.textColor,
                                appearance: glassAppearance,
                                tint: glassTint,
                                intensity: state.preferences.glassIntensity
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }

                    if showSavedNotice {
                        Label("Icon saved to Photos!", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("Preview")
            }

            // 2. LOGO MARK SELECTION & SORTING
            Section {
                // Category Filter Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(LogoCategory.allCases) { category in
                            Button {
                                selectedCategory = category
                            } label: {
                                Text(category.localizedTitle)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        selectedCategory == category ? Color.accentColor : Color(uiColor: .tertiarySystemFill),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(selectedCategory == category ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selectedCategory == category ? [.isSelected] : [])
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Sorting
                Picker("Sort", selection: $sortOption) {
                    ForEach(LogoSort.allCases) { sort in
                        Text(sort.localizedTitle).tag(sort)
                    }
                }

                // Grid of 20 Marks
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 14)], spacing: 16) {
                    ForEach(filteredVariants, id: \.rawValue) { variant in
                        Button {
                            state.preferences.logoVariantID = variant.rawValue
                        } label: {
                            VStack(spacing: 6) {
                                LogoMark(variant: variant, primary: logoPrimary, accent: logoAccent)
                                    .frame(width: 44, height: 44)
                                Text(LocalizedStringKey(variant.displayName))
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .multilineTextAlignment(.center)

                                if variant == logoVariant {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 82)
                            .padding(.vertical, 4)
                            .background(
                                variant == logoVariant ? Color.accentColor.opacity(0.12) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(variant == logoVariant ? Color.accentColor : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(LocalizedStringKey("Logo " + variant.displayName))
                        .accessibilityAddTraits(variant == logoVariant ? .isSelected : [])
                    }
                }
                .padding(.vertical, 6)

                ColorPicker("Primary mark color", selection: color($state.preferences.logoPrimaryColor, fallback: state.activeTheme.foreground), supportsOpacity: false)
                ColorPicker("Accent mark color", selection: color($state.preferences.logoAccentColor, fallback: state.activeTheme.secondary), supportsOpacity: false)

                Button("Reset colors to theme") {
                    state.preferences.logoVariantID = LogoVariant.fallback.rawValue
                    state.preferences.logoPrimaryColor = ""
                    state.preferences.logoAccentColor = ""
                }
            } header: {
                Text("Logo Mark")
            }

            // 3. APP ICON STYLING & SIZING
            Section {
                Picker("Icon Background", selection: $iconBgMode) {
                    Text("Active Theme").tag("theme")
                    Text("Midnight Dark").tag("midnight")
                    Text("Pure White").tag("white")
                    Text("Custom Color").tag("custom")
                }

                if iconBgMode == "custom" {
                    ColorPicker("Custom Background Color", selection: customBgColorBinding, supportsOpacity: false)
                }

                LabeledContent("Mark Size") {
                    Slider(value: $markScale, in: 0.38...0.72)
                        .frame(maxWidth: 180)
                        .accessibilityLabel("Mark Size")
                }
            } header: {
                Text("Icon Canvas & Size")
            }

            // 4. GLASS EFFECTS
            Section {
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
                    Text("Reduce Transparency is enabled, so LERN uses an opaque preview for readability.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Reset glass to system") {
                    state.preferences.glassAppearance = GlassAppearance.automatic.rawValue
                    state.preferences.glassTintColor = ""
                    state.preferences.glassIntensity = 0.35
                }
            } header: {
                Text("Glass Effect")
            }

            // 5. SET AS APP ICON & EXPORT
            Section {
                // Official alternate icons grid
                VStack(alignment: .leading, spacing: 10) {
                    Text("Select an official precompiled icon or auto-match with your chosen colors.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(systemIcons, id: \.key) { icon in
                                Button {
                                    setAlternateIcon(icon.key)
                                } label: {
                                    VStack(spacing: 6) {
                                        ZStack(alignment: .topTrailing) {
                                            if let image = UIImage(named: icon.preview) {
                                                Image(uiImage: image)
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 60, height: 60)
                                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                            } else {
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .fill(Color.secondary.opacity(0.2))
                                                    .frame(width: 60, height: 60)
                                            }

                                            if alternateIconName == icon.key {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.subheadline)
                                                    .symbolRenderingMode(.palette)
                                                    .foregroundStyle(.white, .blue)
                                                    .offset(x: 4, y: -4)
                                            }
                                        }
                                        Text(LocalizedStringKey(icon.name))
                                            .font(.caption2)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 72)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(icon.name + (alternateIconName == icon.key ? ", selected" : ""))
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        autoMatchSystemIcon()
                    } label: {
                        Label("Auto-Match System Icon", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)

                // High-resolution export actions
                Button {
                    Task { await saveIconToPhotos() }
                } label: {
                    HStack {
                        Label("Save Custom Icon to Photos", systemImage: "square.and.arrow.down")
                        Spacer()
                        if isExporting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isExporting)

                Button {
                    exportIcon()
                } label: {
                    Label("Share Custom Icon", systemImage: "square.and.arrow.up")
                }

                // Collapsible Shortcuts Guide
                DisclosureGroup(isExpanded: $showShortcutsGuide) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("iOS allows custom Home Screen icons for any app using the Apple Shortcuts app:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("1. Tap **Save Custom Icon to Photos** above.")
                            Text("2. Open the **Shortcuts** app and tap **+**.")
                            Text("3. Add the action **Open App** and select **LERN**.")
                            Text("4. Tap Share > **Add to Home Screen**, choose the saved photo.")
                        }
                        .font(.caption)

                        Button {
                            if let url = URL(string: "shortcuts://"), UIApplication.shared.canOpenURL(url) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Open Apple Shortcuts", systemImage: "arrow.up.forward.app")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 6)
                } label: {
                    Label("How to set on Home Screen via Shortcuts", systemImage: "questionmark.circle")
                        .font(.subheadline)
                }
            } header: {
                Text("Home Screen App Icon")
            } footer: {
                Text("Official icons change your icon immediately. For fully customized artwork, save to Photos and apply via Apple Shortcuts.")
            }
        }
        .navigationTitle("Logo & App Icon")
        .sheet(isPresented: $showShareSheet) {
            if let shareSheetItem {
                ActivitySheet(items: [shareSheetItem])
            }
        }
        .onDisappear {
            Task {
                await state.savePreferences(notificationImpact: false, reloadWidgets: false)
            }
        }
    }

    // MARK: - Computed Properties & Helpers

    private var logoVariant: LogoVariant {
        LogoVariant(rawValue: state.preferences.logoVariantID) ?? .fallback
    }

    private var glassAppearance: GlassAppearance {
        GlassAppearance(rawValue: state.preferences.glassAppearance) ?? .automatic
    }

    private var logoPrimary: Color {
        Color(hex: state.preferences.logoPrimaryColor.isEmpty ? state.activeTheme.foreground : state.preferences.logoPrimaryColor)
    }

    private var logoAccent: Color {
        Color(hex: state.preferences.logoAccentColor.isEmpty ? state.activeTheme.secondary : state.preferences.logoAccentColor)
    }

    private var glassTint: Color {
        Color(hex: state.preferences.glassTintColor.isEmpty ? state.activeTheme.secondary : state.preferences.glassTintColor)
    }

    private var effectiveBackgroundHex: String {
        switch iconBgMode {
        case "midnight": return "12131A"
        case "white": return "FFFFFF"
        case "custom": return customBgHex.isEmpty ? "142C46" : customBgHex
        default: return state.activeTheme.background
        }
    }

    private var customBgColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: customBgHex) },
            set: { customBgHex = $0.hexValue }
        )
    }

    private var filteredVariants: [LogoVariant] {
        let matched = LogoVariant.allCases.filter { selectedCategory.matches($0) }
        switch sortOption {
        case .curated:
            return matched
        case .alphabetical:
            return matched.sorted { $0.displayName < $1.displayName }
        }
    }

    private func color(_ hex: Binding<String>, fallback: String) -> Binding<Color> {
        Binding(
            get: { Color(hex: hex.wrappedValue.isEmpty ? fallback : hex.wrappedValue) },
            set: { hex.wrappedValue = $0.hexValue }
        )
    }

    private func setAlternateIcon(_ key: String) {
        UIApplication.shared.setAlternateIconName(key.isEmpty ? nil : key) { error in
            Task { @MainActor in
                if let error {
                    statusMessage = error.localizedDescription
                } else {
                    alternateIconName = key
                    statusMessage = String(localized: "App icon updated!")
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }
    }

    private func autoMatchSystemIcon() {
        let hex = effectiveBackgroundHex.uppercased()
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(clean, radix: 16) ?? 0x142C46
        let r = Double((value >> 16) & 255) / 255
        let g = Double((value >> 8) & 255) / 255
        let b = Double(value & 255) / 255
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b

        let targetKey: String
        if luminance < 0.20 {
            targetKey = "MinimalBlack"
        } else if luminance > 0.85 {
            targetKey = "MinimalWhite"
        } else if r > b && (r > 0.4 || hex.contains("6E")) {
            targetKey = "Warm"
        } else if b > r && (b > 0.4 || hex.contains("24")) {
            targetKey = "Cool"
        } else {
            targetKey = "Gradient"
        }

        setAlternateIcon(targetKey)
    }

    @MainActor
    private func renderExportImage(size: CGFloat = 1024, isSquircle: Bool = true) -> UIImage? {
        let canvas = AppIconCanvasView(
            variant: logoVariant,
            primary: logoPrimary,
            accent: logoAccent,
            backgroundHex: effectiveBackgroundHex,
            glassAppearance: glassAppearance,
            glassTint: glassTint,
            glassIntensity: state.preferences.glassIntensity,
            markScale: markScale,
            size: size,
            isSquircle: isSquircle,
            showShadow: false
        )
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1.0
        return renderer.uiImage
    }

    @MainActor
    private func saveIconToPhotos() async {
        isExporting = true
        defer { isExporting = false }

        guard let image = renderExportImage(size: 1024, isSquircle: true) else {
            statusMessage = String(localized: "Failed to render icon.")
            return
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            statusMessage = String(localized: "Allow photo access in Settings to save images.")
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation { showSavedNotice = true }
            statusMessage = String(localized: "Icon saved to Photos!")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func exportIcon() {
        Task { @MainActor in
            guard let image = renderExportImage(size: 1024, isSquircle: true) else { return }
            shareSheetItem = image
            showShareSheet = true
        }
    }
}

// MARK: - Glass Elevation Hierarchy

public enum GlassElevation: Sendable {
    case flat
    case low       // Header pills, tags, chips
    case medium    // Floating action docks, toolbars
    case elevated  // Prominent cards, modals

    var shadowRadius: CGFloat {
        switch self {
        case .flat: return 0
        case .low: return 4
        case .medium: return 12
        case .elevated: return 22
        }
    }

    var shadowY: CGFloat {
        switch self {
        case .flat: return 0
        case .low: return 2
        case .medium: return 6
        case .elevated: return 10
        }
    }

    var shadowOpacity: Double {
        switch self {
        case .flat: return 0
        case .low: return 0.08
        case .medium: return 0.16
        case .elevated: return 0.24
        }
    }
}

// MARK: - Native iOS 18 Glass Modifier

public struct LERNGlassModifier<S: InsettableShape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    let shape: S
    let appearance: GlassAppearance
    let tint: Color?
    let intensity: Double
    let elevation: GlassElevation

    public init(
        shape: S,
        appearance: GlassAppearance = .automatic,
        tint: Color? = nil,
        intensity: Double = 0.35,
        elevation: GlassElevation = .low
    ) {
        self.shape = shape
        self.appearance = appearance
        self.tint = tint
        self.intensity = min(max(intensity, 0.0), 1.0)
        self.elevation = elevation
    }

    public func body(content: Content) -> some View {
        content
            .background(materialBackground)
            .overlay(specularRimLight)
            .compositingGroup()
            .shadow(
                color: Color.black.opacity(elevation.shadowOpacity),
                radius: elevation.shadowRadius,
                x: 0,
                y: elevation.shadowY
            )
            .shadow(
                color: Color.black.opacity(elevation.shadowOpacity * 0.4),
                radius: max(1, elevation.shadowRadius * 0.35),
                x: 0,
                y: 1
            )
    }

    // MARK: - Material & Tint Background

    @ViewBuilder
    private var materialBackground: some View {
        let activeTint = tint ?? (colorScheme == .dark ? Color.white : Color.black)

        if reduceTransparency {
            // High-contrast, 100% opaque solid background under Apple Accessibility standards
            shape
                .fill(colorScheme == .dark ? Color(uiColor: .secondarySystemBackground) : Color(uiColor: .systemBackground))
                .overlay(shape.fill(activeTint.opacity(0.08 * intensity)))
        } else {
            switch appearance {
            case .off:
                shape
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .overlay(shape.fill(activeTint.opacity(0.08 + (intensity * 0.18))))

            case .clear:
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(activeTint.opacity(0.10 * intensity)))

            case .regular:
                shape
                    .fill(.regularMaterial)
                    .overlay(shape.fill(activeTint.opacity(0.05 + (intensity * 0.20))))

            case .automatic:
                if colorScheme == .dark {
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay(shape.fill(activeTint.opacity(0.06 + (intensity * 0.22))))
                } else {
                    shape
                        .fill(.thinMaterial)
                        .overlay(shape.fill(activeTint.opacity(0.04 + (intensity * 0.18))))
                }
            }
        }
    }

    // MARK: - Apple HIG Specular Rim Highlight (Fresnel Refraction)

    @ViewBuilder
    private var specularRimLight: some View {
        if appearance == .off || reduceTransparency {
            shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
        } else {
            let topHighlight = colorScheme == .dark ? 0.35 : 0.65
            let midHighlight = colorScheme == .dark ? 0.08 : 0.20
            let bottomShadow = colorScheme == .dark ? 0.25 : 0.06

            shape.strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(topHighlight), location: 0.0),
                        .init(color: Color.white.opacity(midHighlight), location: 0.42),
                        .init(color: Color.black.opacity(bottomShadow), location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.75
            )
        }
    }
}

// MARK: - View Modifiers Extension

public extension View {
    func lernGlass<S: InsettableShape>(
        shape: S,
        appearance: GlassAppearance = .automatic,
        tint: Color? = nil,
        intensity: Double = 0.35,
        elevation: GlassElevation = .low
    ) -> some View {
        modifier(LERNGlassModifier(
            shape: shape,
            appearance: appearance,
            tint: tint,
            intensity: intensity,
            elevation: elevation
        ))
    }

    func lernGlassCapsule(
        appearance: GlassAppearance = .automatic,
        tint: Color? = nil,
        intensity: Double = 0.35,
        elevation: GlassElevation = .medium
    ) -> some View {
        lernGlass(
            shape: Capsule(),
            appearance: appearance,
            tint: tint,
            intensity: intensity,
            elevation: elevation
        )
    }

    func lernGlassCard(
        cornerRadius: CGFloat = 20,
        appearance: GlassAppearance = .automatic,
        tint: Color? = nil,
        intensity: Double = 0.35,
        elevation: GlassElevation = .low
    ) -> some View {
        lernGlass(
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            appearance: appearance,
            tint: tint,
            intensity: intensity,
            elevation: elevation
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
    let variant: LogoVariant
    let primary: Color
    let accent: Color
    let foreground: Color
    let appearance: GlassAppearance
    let tint: Color
    let intensity: Double
    var body: some View {
        VStack(spacing: 14) {
            LogoMark(variant: variant, primary: primary, accent: accent).frame(width: 84, height: 84)
            Text("LERN").font(.system(.title2, design: .rounded).weight(.semibold)).tracking(4)
        }
        .foregroundStyle(foreground)
        .padding(24)
        .lernGlassCard(cornerRadius: 22, appearance: appearance, tint: tint, intensity: intensity, elevation: .medium)
    }
}

struct LogoGlassChrome: View {
    @Environment(AppState.self) private var state
    var body: some View {
        let variant = LogoVariant(rawValue: state.preferences.logoVariantID) ?? .fallback
        let primary = Color(hex: state.preferences.logoPrimaryColor.isEmpty ? state.activeTheme.foreground : state.preferences.logoPrimaryColor)
        let accent = Color(hex: state.preferences.logoAccentColor.isEmpty ? state.activeTheme.secondary : state.preferences.logoAccentColor)
        let tint = Color(hex: state.preferences.glassTintColor.isEmpty ? state.activeTheme.secondary : state.preferences.glassTintColor)
        LogoMark(variant: variant, primary: primary, accent: accent).frame(width: 26, height: 26).padding(7)
            .lernGlass(shape: RoundedRectangle(cornerRadius: 12, style: .continuous), appearance: GlassAppearance(rawValue: state.preferences.glassAppearance) ?? .automatic, tint: tint, intensity: state.preferences.glassIntensity, elevation: .low)
            .accessibilityLabel("LERN logo")
    }
}
