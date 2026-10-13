// Generated from Design/WorkspaceMark.svg by Design/generate_brand_assets.py.
// Change the SVG and regenerate to keep onboarding and app icons identical.
import SwiftUI

enum WorkspaceBrand {
    static let blue = Color(.sRGB, red: 36 / 255, green: 150 / 255, blue: 237 / 255, opacity: 1)
}

struct WorkspaceMark: View {
    @Environment(\.colorScheme) private var colorScheme
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 222 / 1024)
                .fill(colorScheme == .dark ? WorkspaceBrand.blue : .white)
            WorkspaceLogoShape()
                .fill(colorScheme == .dark ? .white : WorkspaceBrand.blue, style: FillStyle(eoFill: true))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Tierin")
    }
}

struct WorkspaceLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 440, y: 208))
        p.addQuadCurve(to: CGPoint(x: 472, y: 176), control: CGPoint(x: 440, y: 176))
        p.addLine(to: CGPoint(x: 776, y: 176))
        p.addQuadCurve(to: CGPoint(x: 808, y: 208), control: CGPoint(x: 808, y: 176))
        p.addLine(to: CGPoint(x: 808, y: 504))
        p.addQuadCurve(to: CGPoint(x: 776, y: 536), control: CGPoint(x: 808, y: 536))
        p.addLine(to: CGPoint(x: 752, y: 536))
        p.addLine(to: CGPoint(x: 752, y: 288))
        p.addQuadCurve(to: CGPoint(x: 696, y: 232), control: CGPoint(x: 752, y: 232))
        p.addLine(to: CGPoint(x: 440, y: 232))
        p.closeSubpath()
        p.move(to: CGPoint(x: 312, y: 336))
        p.addQuadCurve(to: CGPoint(x: 344, y: 304), control: CGPoint(x: 312, y: 304))
        p.addLine(to: CGPoint(x: 648, y: 304))
        p.addQuadCurve(to: CGPoint(x: 680, y: 336), control: CGPoint(x: 680, y: 304))
        p.addLine(to: CGPoint(x: 680, y: 632))
        p.addQuadCurve(to: CGPoint(x: 648, y: 664), control: CGPoint(x: 680, y: 664))
        p.addLine(to: CGPoint(x: 624, y: 664))
        p.addLine(to: CGPoint(x: 624, y: 416))
        p.addQuadCurve(to: CGPoint(x: 568, y: 360), control: CGPoint(x: 624, y: 360))
        p.addLine(to: CGPoint(x: 312, y: 360))
        p.closeSubpath()
        p.move(to: CGPoint(x: 216, y: 432))
        p.addLine(to: CGPoint(x: 520, y: 432))
        p.addQuadCurve(to: CGPoint(x: 552, y: 464), control: CGPoint(x: 552, y: 432))
        p.addLine(to: CGPoint(x: 552, y: 776))
        p.addQuadCurve(to: CGPoint(x: 520, y: 808), control: CGPoint(x: 552, y: 808))
        p.addLine(to: CGPoint(x: 216, y: 808))
        p.addQuadCurve(to: CGPoint(x: 184, y: 776), control: CGPoint(x: 184, y: 808))
        p.addLine(to: CGPoint(x: 184, y: 464))
        p.addQuadCurve(to: CGPoint(x: 216, y: 432), control: CGPoint(x: 184, y: 432))
        p.closeSubpath()
        p.move(to: CGPoint(x: 256, y: 504))
        p.addQuadCurve(to: CGPoint(x: 244, y: 516), control: CGPoint(x: 244, y: 504))
        p.addLine(to: CGPoint(x: 244, y: 736))
        p.addQuadCurve(to: CGPoint(x: 256, y: 748), control: CGPoint(x: 244, y: 748))
        p.addLine(to: CGPoint(x: 296, y: 748))
        p.addQuadCurve(to: CGPoint(x: 308, y: 736), control: CGPoint(x: 308, y: 748))
        p.addLine(to: CGPoint(x: 308, y: 516))
        p.addQuadCurve(to: CGPoint(x: 296, y: 504), control: CGPoint(x: 308, y: 504))
        p.closeSubpath()
        p.move(to: CGPoint(x: 364, y: 504))
        p.addQuadCurve(to: CGPoint(x: 352, y: 516), control: CGPoint(x: 352, y: 504))
        p.addLine(to: CGPoint(x: 352, y: 580))
        p.addQuadCurve(to: CGPoint(x: 364, y: 592), control: CGPoint(x: 352, y: 592))
        p.addLine(to: CGPoint(x: 480, y: 592))
        p.addQuadCurve(to: CGPoint(x: 492, y: 580), control: CGPoint(x: 492, y: 592))
        p.addLine(to: CGPoint(x: 492, y: 516))
        p.addQuadCurve(to: CGPoint(x: 480, y: 504), control: CGPoint(x: 492, y: 504))
        p.closeSubpath()
        p.move(to: CGPoint(x: 364, y: 632))
        p.addQuadCurve(to: CGPoint(x: 352, y: 644), control: CGPoint(x: 352, y: 632))
        p.addLine(to: CGPoint(x: 352, y: 736))
        p.addQuadCurve(to: CGPoint(x: 364, y: 748), control: CGPoint(x: 352, y: 748))
        p.addLine(to: CGPoint(x: 480, y: 748))
        p.addQuadCurve(to: CGPoint(x: 492, y: 736), control: CGPoint(x: 492, y: 748))
        p.addLine(to: CGPoint(x: 492, y: 644))
        p.addQuadCurve(to: CGPoint(x: 480, y: 632), control: CGPoint(x: 492, y: 632))
        p.closeSubpath()
        let scale = min(rect.width, rect.height) / 1024
        return p.applying(CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: rect.midX - 512 * scale,
                                           y: rect.midY - 512 * scale)))
    }
}
