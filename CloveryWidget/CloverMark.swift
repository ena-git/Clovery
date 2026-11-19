import SwiftUI

/// Vector four-leaf clover matching the app logo: four heart-shaped leaves whose
/// tips meet in the middle (notches pointing at the corners) plus a short curved stem.
struct CloverLeaves: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let ox = rect.midX - s / 2, oy = rect.minY
        let L = s * 0.60                                   // leaf length
        var heart = Path()
        heart.move(to: CGPoint(x: 0.5, y: 1))
        heart.addCurve(to: CGPoint(x: 0.02, y: 0.36), control1: CGPoint(x: 0.20, y: 0.92), control2: CGPoint(x: -0.03, y: 0.64))
        heart.addCurve(to: CGPoint(x: 0.5, y: 0.22), control1: CGPoint(x: 0.05, y: 0.08), control2: CGPoint(x: 0.40, y: -0.05))
        heart.addCurve(to: CGPoint(x: 0.98, y: 0.36), control1: CGPoint(x: 0.60, y: -0.05), control2: CGPoint(x: 0.95, y: 0.08))
        heart.addCurve(to: CGPoint(x: 0.5, y: 1), control1: CGPoint(x: 1.03, y: 0.64), control2: CGPoint(x: 0.80, y: 0.92))
        heart.closeSubpath()

        let cx = ox + s / 2, cy = oy + s * 0.46            // clover centre
        let gap = s * 0.018                                // pushes leaves apart -> thin seams like the logo
        var p = Path()
        for deg in [-45.0, 45.0, 135.0, 225.0] {
            let rad = deg * .pi / 180
            // leaf axis points "up" in local space; after rotating by `deg` the notch faces outward
            let dx = sin(rad) * gap, dy = -cos(rad) * gap
            let t = CGAffineTransform(translationX: cx + dx, y: cy + dy)
                .rotated(by: rad)
                .translatedBy(x: -0.5 * L, y: -L)
                .scaledBy(x: L, y: L)
            p.addPath(heart.applying(t))
        }
        return p
    }
}

struct CloverStem: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let ox = rect.midX - s / 2, oy = rect.minY
        var p = Path()
        p.move(to: CGPoint(x: ox + s * 0.50, y: oy + s * 0.50))
        p.addQuadCurve(to: CGPoint(x: ox + s * 0.55, y: oy + s * 0.97), control: CGPoint(x: ox + s * 0.47, y: oy + s * 0.78))
        return p
    }
}

struct CloverMark: View {
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                CloverStem().stroke(style: StrokeStyle(lineWidth: s * 0.055, lineCap: .round))
                CloverLeaves().fill(style: FillStyle(eoFill: false))
            }
            .frame(width: s, height: s)
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
