import SwiftUI
import LERNCore

/// Twenty independent vector marks. They are deliberately in-app artwork, not
/// alternate Home Screen icons: iOS permits only predeclared icon assets there.
struct LogoMark: View {
    let variant: LogoVariant
    var primary: Color
    var accent: Color

    var body: some View {
        Canvas { context, size in
            let u = min(size.width, size.height) / 100
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * u + (size.width - 100 * u) / 2, y: y * u + (size.height - 100 * u) / 2) }
            func stroke(_ points: [CGPoint], _ color: Color = primary, _ width: CGFloat = 10, closed: Bool = false) {
                var path = Path(); guard let first = points.first else { return }; path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
                if closed { path.closeSubpath() }
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width * u, lineCap: .round, lineJoin: .round))
            }
            func fill(_ points: [CGPoint], _ color: Color = primary) {
                var path = Path(); guard let first = points.first else { return }; path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }; path.closeSubpath(); context.fill(path, with: .color(color))
            }
            func dot(_ point: CGPoint, _ radius: CGFloat, _ color: Color = primary) {
                context.fill(Path(ellipseIn: CGRect(x: point.x - radius * u, y: point.y - radius * u, width: 2 * radius * u, height: 2 * radius * u)), with: .color(color))
            }
            switch variant {
            case .fold:
                fill([p(18,20),p(77,14),p(63,47),p(82,82),p(36,86),p(48,53)]); fill([p(18,20),p(48,53),p(36,86),p(10,58)], accent)
            case .openPages:
                stroke([p(14,28),p(43,20),p(50,30),p(57,20),p(86,28),p(86,76),p(57,68),p(50,76),p(43,68),p(14,76)], primary, 8); stroke([p(50,30),p(50,76)], accent, 7)
            case .quoteSpark:
                stroke([p(22,33),p(39,33),p(33,53),p(22,53)], primary, 9); stroke([p(50,33),p(67,33),p(61,53),p(50,53)], primary, 9); stroke([p(76,18),p(76,34)], accent, 7); stroke([p(68,26),p(84,26)], accent, 7)
            case .bookmarkCut:
                fill([p(28,14),p(72,14),p(72,86),p(50,68),p(28,86)]); fill([p(43,14),p(57,14),p(57,42),p(50,35),p(43,42)], accent)
            case .orbit:
                dot(p(50,50), 11); var orbit = Path(); orbit.addArc(center: p(50,50), radius: 35*u, startAngle: .degrees(25), endAngle: .degrees(305), clockwise: false); context.stroke(orbit, with: .color(accent), style: StrokeStyle(lineWidth: 8*u, lineCap: .round)); dot(p(77,34), 5, accent)
            case .portal:
                stroke([p(24,80),p(24,36),p(50,16),p(76,36),p(76,80)], primary, 9); stroke([p(42,80),p(42,44),p(50,38),p(58,44),p(58,80)], accent, 8)
            case .prism:
                fill([p(16,72),p(46,18),p(84,70),p(49,86)]); fill([p(46,18),p(49,86),p(62,57)], accent); stroke([p(16,72),p(84,70)], Color.white.opacity(0.28), 2)
            case .flow:
                var wave = Path(); wave.move(to:p(12,61)); wave.addCurve(to:p(88,39), control1:p(30,8), control2:p(62,92)); context.stroke(wave, with:.color(primary), style:StrokeStyle(lineWidth:10*u,lineCap:.round)); dot(p(74,44),7,accent)
            case .stack:
                stroke([p(20,34),p(64,20),p(82,35),p(38,49),p(20,34)], primary, 8, closed:true); stroke([p(20,51),p(64,37),p(82,52),p(38,66),p(20,51)], accent, 8, closed:true)
            case .focus:
                stroke([p(18,42),p(18,24),p(36,24)], primary,8); stroke([p(64,24),p(82,24),p(82,42)], primary,8); stroke([p(18,58),p(18,76),p(36,76)],primary,8); stroke([p(64,76),p(82,76),p(82,58)],primary,8); dot(p(50,50),9,accent)
            case .loop:
                var loop = Path(); loop.move(to:p(20,57)); loop.addCurve(to:p(50,20),control1:p(22,20),control2:p(42,19)); loop.addCurve(to:p(78,47),control1:p(65,21),control2:p(86,37)); loop.addCurve(to:p(47,80),control1:p(80,70),control2:p(59,84)); loop.addCurve(to:p(20,57),control1:p(29,79),control2:p(17,69)); context.stroke(loop,with:.color(primary),style:StrokeStyle(lineWidth:9*u,lineCap:.round)); dot(p(50,20),4,accent)
            case .northStar:
                fill([p(50,12),p(59,41),p(88,50),p(59,59),p(50,88),p(41,59),p(12,50),p(41,41)], primary); dot(p(50,50),7,accent)
            case .seed:
                var left=Path(); left.move(to:p(50,82)); left.addCurve(to:p(19,26),control1:p(20,67),control2:p(17,36)); left.addCurve(to:p(50,48),control1:p(42,19),control2:p(53,30)); context.fill(left,with:.color(primary)); var right=Path(); right.move(to:p(50,82)); right.addCurve(to:p(81,26),control1:p(80,67),control2:p(83,36)); right.addCurve(to:p(50,48),control1:p(58,19),control2:p(47,30)); context.fill(right,with:.color(accent))
            case .steps:
                fill([p(18,76),p(18,60),p(43,60),p(43,44),p(68,44),p(68,28),p(84,28),p(84,84),p(18,84)]); dot(p(76,18),5,accent)
            case .link:
                var a=Path(); a.addArc(center:p(38,50),radius:22*u,startAngle:.degrees(300),endAngle:.degrees(120),clockwise:false); context.stroke(a,with:.color(primary),style:StrokeStyle(lineWidth:10*u,lineCap:.round)); var b=Path(); b.addArc(center:p(62,50),radius:22*u,startAngle:.degrees(120),endAngle:.degrees(300),clockwise:false); context.stroke(b,with:.color(accent),style:StrokeStyle(lineWidth:10*u,lineCap:.round))
            case .openFrame:
                stroke([p(76,30),p(76,20),p(24,20),p(24,80),p(67,80)], primary,9); stroke([p(77,51),p(77,80)],accent,9)
            case .pulse:
                stroke([p(12,56),p(30,56),p(39,34),p(51,72),p(61,44),p(70,56),p(88,56)],primary,9); dot(p(51,72),4,accent)
            case .facet:
                fill([p(50,12),p(84,37),p(70,78),p(30,78),p(16,37)]); fill([p(50,12),p(70,78),p(50,60),p(30,78)],accent); stroke([p(16,37),p(84,37)],Color.white.opacity(0.3),2)
            case .window:
                fill([p(18,18),p(52,18),p(52,48),p(18,48)]); fill([p(58,18),p(82,18),p(82,82),p(58,82)],accent); fill([p(18,54),p(52,54),p(52,82),p(18,82)])
            case .glyph:
                stroke([p(28,22),p(28,76),p(49,76),p(67,54),p(67,29)],primary,11); stroke([p(49,76),p(76,76)],accent,8)
            }
        }.aspectRatio(1, contentMode: .fit).accessibilityLabel(LocalizedStringKey("Logo " + variant.displayName))
    }
}
