import SwiftUI

/// The Zelda Labs flask mark, drawn in a 200 × 200 box (same geometry as ios/tools/make-studio-logo.swift).
/// `level` fills the flask from the bottom (0…1) so the splash can pour it in.
struct ZeldaLabsMark: View {
    var level: CGFloat = 1
    var bubbles: CGFloat = 1

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 200
            ctx.scaleBy(x: s, y: s)
            var flask = Path()
            flask.move(to: CGPoint(x: 80, y: 30)); flask.addLine(to: CGPoint(x: 80, y: 82))
            flask.addLine(to: CGPoint(x: 36, y: 158))
            flask.addQuadCurve(to: CGPoint(x: 52, y: 176), control: CGPoint(x: 28, y: 176))
            flask.addLine(to: CGPoint(x: 148, y: 176))
            flask.addQuadCurve(to: CGPoint(x: 164, y: 158), control: CGPoint(x: 172, y: 176))
            flask.addLine(to: CGPoint(x: 120, y: 82)); flask.addLine(to: CGPoint(x: 120, y: 30))

            let top = 176 - (176 - 106) * level
            var inside = ctx
            var closed = flask; closed.closeSubpath()
            inside.clip(to: closed)
            inside.fill(Path(CGRect(x: 0, y: top, width: 200, height: 200)), with: .color(.coral))
            inside.fill(Path(CGRect(x: 0, y: top, width: 200, height: 5)), with: .color(.white.opacity(0.25)))

            var z = Path()
            z.move(to: CGPoint(x: 76, y: 122)); z.addLine(to: CGPoint(x: 124, y: 122))
            z.addLine(to: CGPoint(x: 76, y: 160)); z.addLine(to: CGPoint(x: 124, y: 160))
            ctx.stroke(z, with: .color(.navy.opacity(level > 0.55 ? 1 : 0)), style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))

            let glass = StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)
            ctx.stroke(flask, with: .color(.text), style: glass)
            ctx.stroke(Path { $0.move(to: CGPoint(x: 68, y: 30)); $0.addLine(to: CGPoint(x: 132, y: 30)) }, with: .color(.text), style: glass)

            for (i, b) in [(108.0, 70.0, 7.0), (92.0, 50.0, 5.0), (104.0, 14.0, 4.0)].enumerated() {
                let shown = min(1, max(0, bubbles * 3 - CGFloat(i)))
                let y = b.1 + (1 - shown) * 30
                ctx.fill(Path(ellipseIn: CGRect(x: b.0 - b.2, y: y - b.2, width: 2 * b.2, height: 2 * b.2)),
                         with: .color(.teal.opacity(shown)))
            }
        }
    }
}

struct ZeldaLabsLogo: View {
    var level: CGFloat = 1
    var bubbles: CGFloat = 1
    var wordmark: Double = 1
    var body: some View {
        VStack(spacing: 10) {
            ZeldaLabsMark(level: level, bubbles: bubbles).frame(width: 130, height: 130)
            VStack(spacing: 2) {
                Text("ZELDA").font(rounded(40, .heavy)).tracking(4).foregroundStyle(Color.text)
                Text("LABS").font(rounded(17, .bold)).tracking(11).foregroundStyle(Color(red: 0.18, green: 0.70, blue: 0.71))
            }
            .opacity(wordmark)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zelda Labs")
    }
}

/// Studio card before the title (GDD §9a): 1.5 s, the flask pours in; tap to skip after the first launch.
struct StudioSplash: View {
    let done: () -> Void
    @State private var level: CGFloat = 0
    @State private var bubbles: CGFloat = 0
    @State private var wordmark = 0.0
    @State private var finished = false
    private static let seenKey = "seenStudioSplash"

    var body: some View {
        ZStack {
            Color.sky.ignoresSafeArea()
            ZeldaLabsLogo(level: level, bubbles: bubbles, wordmark: wordmark)
        }
        .contentShape(Rectangle())
        .onTapGesture { if UserDefaults.standard.bool(forKey: Self.seenKey) { finish() } }
        .task {
            withAnimation(.easeOut(duration: 0.7)) { level = 1 }
            withAnimation(.easeOut(duration: 0.6).delay(0.5)) { bubbles = 1 }
            withAnimation(.easeOut(duration: 0.4).delay(0.35)) { wordmark = 1 }
            try? await Task.sleep(for: .seconds(1.5))
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        done()
    }
}
