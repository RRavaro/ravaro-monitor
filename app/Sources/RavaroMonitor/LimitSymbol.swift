import SwiftUI

/// Das Zeichen in den beiden Limit-Ringen. Die öffentliche Fassung nutzt den Roboterkopf, die private Fassung das Claude-Symbol (`app/bau.sh`).
#if PRIVATES_SYMBOL
typealias LimitSymbol = ClaudeSymbol
#else
typealias LimitSymbol = RoboterKopf
#endif

/// Eigenes Zeichen ohne fremde Marke, gezeichnet auf einem Raster von 24 × 24.
struct RoboterKopf: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func punkt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var p = Path()
        // Kopf im Uhrzeigersinn, Augen und Mund gegenläufig, damit sie Löcher werden.
        p.move(to: punkt(7, 6))
        p.addLine(to: punkt(17, 6))
        p.addArc(tangent1End: punkt(21, 6), tangent2End: punkt(21, 10), radius: 4 * s)
        p.addLine(to: punkt(21, 17))
        p.addArc(tangent1End: punkt(21, 21), tangent2End: punkt(17, 21), radius: 4 * s)
        p.addLine(to: punkt(7, 21))
        p.addArc(tangent1End: punkt(3, 21), tangent2End: punkt(3, 17), radius: 4 * s)
        p.addLine(to: punkt(3, 10))
        p.addArc(tangent1End: punkt(3, 6), tangent2End: punkt(7, 6), radius: 4 * s)
        p.closeSubpath()
        for x in [8.5, 15.5] {
            p.move(to: punkt(x + 2, 12.5))
            p.addArc(center: punkt(x, 12.5), radius: 2 * s, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: true)
            p.closeSubpath()
        }
        p.move(to: punkt(8, 16.2))
        p.addLine(to: punkt(8, 18))
        p.addLine(to: punkt(16, 18))
        p.addLine(to: punkt(16, 16.2))
        p.closeSubpath()
        // Antenne und Ohren.
        p.addRect(CGRect(origin: punkt(11.2, 3.5), size: CGSize(width: 1.6 * s, height: 2.5 * s)))
        p.addEllipse(in: CGRect(origin: punkt(10.2, 0.5), size: CGSize(width: 3.6 * s, height: 3.6 * s)))
        p.addRoundedRect(in: CGRect(origin: punkt(0.8, 11), size: CGSize(width: 2.2 * s, height: 5 * s)), cornerSize: CGSize(width: s, height: s))
        p.addRoundedRect(in: CGRect(origin: punkt(21, 11), size: CGSize(width: 2.2 * s, height: 5 * s)), cornerSize: CGSize(width: s, height: s))
        return p
    }
}
