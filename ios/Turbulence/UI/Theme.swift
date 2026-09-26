import SwiftUI
import UIKit

func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font { .system(size: size, weight: weight, design: .rounded) }

extension Color {
    static let cream = Color(uiColor: Palette.cream)
    static let navy = Color(uiColor: Palette.navy)
    static let coral = Color(uiColor: Palette.coral)
    static let teal = Color(uiColor: Palette.teal)
    static let sky = Color(uiColor: Palette.sky)
    static let panel = Color(uiColor: Palette.panel)
    static let panelLine = Color(uiColor: Palette.panelLine)
    static let text = Color(uiColor: Palette.text)
    static let muted = Color(uiColor: Palette.muted)
    static let calm = Color(uiColor: Palette.calm)
    static let finePrint = Color(red: 0x55 / 255, green: 0x60 / 255, blue: 0x7A / 255)
}

/// Crew looks a profile can pick (GDD §7: cosmetic only).
enum Avatar {
    static let looks: [(skin: UIColor, hair: UIColor)] = [
        (UIColor(hex: 0xE9B892), UIColor(hex: 0x3A2A20)),
        (UIColor(hex: 0xA86F4C), UIColor(hex: 0x1A1A1A)),
        (UIColor(hex: 0xF5D7BE), UIColor(hex: 0xC9A15B)),
        (UIColor(hex: 0x7A4A31), UIColor(hex: 0xA0442A))
    ]
    static func look(_ i: Int) -> (skin: UIColor, hair: UIColor) { looks[max(0, min(looks.count - 1, i))] }
}

/// Top-down attendant portrait matching the in-game crew: teal uniform, coral scarf, hair in a bun.
struct AvatarView: View {
    let index: Int
    var size: CGFloat = 44
    var body: some View {
        let look = Avatar.look(index)
        Canvas { ctx, sz in
            let s = sz.width / 44
            let body = CGRect(x: 12 * s, y: 4 * s, width: 20 * s, height: 36 * s)
            ctx.fill(Path(ellipseIn: body), with: .color(.teal))
            ctx.stroke(Path(ellipseIn: body), with: .color(.navy), lineWidth: 2 * s)
            var scarf = Path()
            scarf.move(to: CGPoint(x: 16 * s, y: 16 * s)); scarf.addLine(to: CGPoint(x: 22 * s, y: 11 * s)); scarf.addLine(to: CGPoint(x: 28 * s, y: 16 * s))
            ctx.fill(scarf, with: .color(.coral))
            let head = CGRect(x: 13 * s, y: 13 * s, width: 18 * s, height: 18 * s)
            ctx.fill(Path(ellipseIn: head), with: .color(Color(uiColor: look.skin)))
            ctx.stroke(Path(ellipseIn: head), with: .color(.navy), lineWidth: 1.5 * s)
            var hair = Path()
            hair.addArc(center: CGPoint(x: 22 * s, y: 22 * s), radius: 9 * s, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            ctx.fill(hair, with: .color(Color(uiColor: look.hair)))
            ctx.fill(Path(ellipseIn: CGRect(x: 18 * s, y: 29 * s, width: 8 * s, height: 8 * s)), with: .color(Color(uiColor: look.hair)))
        }
        .frame(width: size, height: size)
        .background(Color.cream, in: Circle())
        .overlay(Circle().stroke(Color.navy, lineWidth: 2))
        .accessibilityHidden(true)
    }
}

struct StarRow: View {
    let stars: Int
    var size: CGFloat = 14
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < stars ? "star.fill" : "star")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(i < stars ? Color.calm : Color.muted)
            }
        }
        .accessibilityLabel("\(stars) of 3 stars")
    }
}

struct Logo: View {
    var size: CGFloat = 40
    var body: some View {
        (Text("Turbu").foregroundColor(.text) + Text("lence").foregroundColor(.coral))
            .font(rounded(size, .heavy))
    }
}
