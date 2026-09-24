import SwiftUI
import LERNCore

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
