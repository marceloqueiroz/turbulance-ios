import SwiftUI
import UIKit

// MARK: - Galley main menu (GDD §9a; specs/galley-main-menu)

/// The landing menu as the Comet's galley wall: the Continue and New Game carts, the oven (Options) and the crew
/// manual (About) are the buttons; the tag, the binder, the cups, the carts and the coffee react to each bump.
/// The window is see-through, so the title card's clouds drift past behind it.
struct GalleyMenu: View {
    let app: AppModel
    /// The bumps so far, on the clock that starts at `start`.
    let kicks: [GalleyKick]
    let start: Date
    /// 0 = nothing moves (Reduce Motion, or Screen shake off); 1 = full motion. Follows the Screen shake option.
    let motion: Double
    #if DEBUG
    /// Prototype only: a tap on the bare wall makes a bump, for tuning the feel.
    var bump: () -> Void = {}
    #endif

    /// The fitting that was tapped: it opens (door down, cover back, cart out) and stays open while its card is up.
    @State private var opening: GalleyLayout.Piece?

    private static let ink = Color(red: 0x5B / 255, green: 0x3A / 255, blue: 0x29 / 255)
    private static let wallTop = Color(red: 0.93, green: 0.87, blue: 0.79)
    private static let floor = Color(red: 0.62, green: 0.60, blue: 0.62)

    var body: some View {
        GeometryReader { geo in
            let p = GalleyLayout.placement(in: geo.size)
            TimelineView(.animation(paused: motion == 0)) { timeline in
                let t = timeline.date.timeIntervalSince(start)
                ZStack(alignment: .topLeading) {
                    // an iPad shows the whole wall: wall colour above it and floor below (never behind it: the window is see-through)
                    Self.wallTop
                        .frame(width: geo.size.width, height: max(0, p.wallRect.minY) + 1)
                        .allowsHitTesting(false)
                    Self.floor
                        .frame(width: geo.size.width, height: max(0, geo.size.height - p.wallRect.maxY) + 1)
                        .offset(y: p.wallRect.maxY - 1)
                        .allowsHitTesting(false)
                    windowView(p, t)
                    Image("GalleyWall")
                        .resizable()
                        .frame(width: p.wallRect.width, height: p.wallRect.height)
                        .offset(x: p.origin.x, y: p.origin.y)
                        .accessibilityHidden(true)
                        #if DEBUG
                        .onTapGesture(perform: bump)
                        #endif
                    coffee(p, t)
                    readyLight(p, t)
                    cups(p, t)
                    oven(p)
                    manual(p, t)
                    newGameCart(p, t)
                    if !app.slots.isEmpty { continueCart(p, t) }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
        }
        .ignoresSafeArea()
        #if DEBUG
        .onAppear {
            // -galleyOpen oven|manual: start with that fitting open and no card, for screenshots of the open state
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-galleyOpen"), i + 1 < args.count {
                opening = args[i + 1] == "oven" ? .oven : args[i + 1] == "manual" ? .manual : nil
            }
        }
        #endif
        .onChange(of: app.sheet == nil) { _, closed in
            // the card went away: the fitting closes again
            if closed { withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { opening = nil } }
        }
    }

    private func v(_ sway: Sway, _ t: TimeInterval, delay: Double = 0) -> Double {
        guard motion > 0 else { return 0 }
        let lagged = Sway(amplitude: sway.amplitude, frequency: sway.frequency, settle: sway.settle,
                          delay: sway.delay + delay, limit: sway.limit)
        return lagged.value(at: t, kicks: kicks) * motion
    }

    // MARK: Buttons

    private func newGameCart(_ p: GalleyLayout.Placement, _ t: TimeInterval) -> some View {
        // with no crew yet, the Continue bay stays empty and New Game takes the coral cart (mirrored to fit the right bay)
        let coral = app.slots.isEmpty
        let frame = coral
            ? CGRect(x: GalleyLayout.frame(.cartNewGame).maxX - GalleyLayout.frame(.cartContinue).width,
                     y: GalleyLayout.frame(.cartNewGame).minY,
                     width: GalleyLayout.frame(.cartContinue).width, height: GalleyLayout.frame(.cartContinue).height)
            : GalleyLayout.frame(.cartNewGame)
        let plate = coral
            ? CGPoint(x: frame.width - GalleyLayout.continuePlate.x, y: GalleyLayout.continuePlate.y)
            : GalleyLayout.newGamePlate
        return fitting(.cartNewGame, label: "New Game", p: p, action: app.newGame) {
            ZStack(alignment: .topLeading) {
                Image(coral ? "GalleyCartCoral" : "GalleyCartTeal")
                    .resizable()
                    .scaleEffect(x: coral ? -1 : 1)
                plateText("NEW GAME", at: plate, p: p)
            }
            .frame(width: frame.width * p.scale, height: frame.height * p.scale)
        }
        .modifier(CartMotion(open: opening == .cartNewGame,
                             tilt: v(GalleyMotion.cartTilt, t, delay: GalleyMotion.cartLag),
                             slide: v(GalleyMotion.cartSlide, t, delay: GalleyMotion.cartLag) * p.scale))
        .position(x: p.rect(frame).midX, y: p.rect(frame).midY)
    }

    private func continueCart(_ p: GalleyLayout.Placement, _ t: TimeInterval) -> some View {
        let frame = GalleyLayout.frame(.cartContinue)
        let tag = GalleyLayout.frame(.tag)
        let pivot = UnitPoint(x: GalleyLayout.tagPivot.x / tag.width, y: GalleyLayout.tagPivot.y / tag.height)
        let name = app.profile?.name ?? ""
        return fitting(.cartContinue, label: "Continue, last flown: \(name)", p: p, action: app.continueGame) {
            ZStack(alignment: .topLeading) {
                Image("GalleyCartCoral").resizable()
                plateText("CONTINUE", at: GalleyLayout.continuePlate, p: p)
                // the tag hangs from the cart's handle and swings on its string
                ZStack {
                    Image("GalleyTag").resizable()
                    VStack(spacing: 0) {
                        Text("Last flown:").font(.system(size: 19 * p.scale, weight: .medium, design: .rounded))
                        Text(name).font(.system(size: 28 * p.scale, weight: .heavy, design: .rounded))
                            .minimumScaleFactor(0.5).lineLimit(1)
                    }
                    .foregroundStyle(Self.ink)
                    .frame(width: 92 * p.scale)
                    .position(x: 57 * p.scale, y: 152 * p.scale)
                }
                .frame(width: tag.width * p.scale, height: tag.height * p.scale)
                .rotationEffect(.degrees(v(GalleyMotion.tag, t) + GalleyMotion.tagDrift(at: t) * motion), anchor: pivot)
                .offset(x: (tag.minX - frame.minX) * p.scale, y: (tag.minY - frame.minY) * p.scale)
            }
            .frame(width: frame.width * p.scale, height: frame.height * p.scale, alignment: .topLeading)
        }
        .modifier(CartMotion(open: opening == .cartContinue, tilt: v(GalleyMotion.cartTilt, t),
                             slide: v(GalleyMotion.cartSlide, t) * p.scale))
        .position(x: p.rect(frame).midX, y: p.rect(frame).midY)
    }

    /// Options: the oven door drops open on its bottom hinge and the oven lights up inside.
    private func oven(_ p: GalleyLayout.Placement) -> some View {
        let r = p.rect(GalleyLayout.frame(.oven))
        let door = p.rect(GalleyLayout.ovenDoor)
        let open = opening == .oven
        return fitting(.oven, label: "Options", p: p, action: { app.sheet = .options }) {
            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: r.width, height: r.height)
                OvenInside(lit: open, scale: p.scale)
                    .frame(width: door.width, height: door.height)
                    .offset(x: door.minX - r.minX, y: door.minY - r.minY)
                Image("GalleyOvenDoor")
                    .resizable()
                    .frame(width: door.width, height: door.height)
                    .brightness(open ? -0.12 : 0)
                    .rotation3DEffect(.degrees(open ? -78 : 0), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.55)
                    .offset(x: door.minX - r.minX, y: door.minY - r.minY)
            }
        }
        .position(x: r.midX, y: r.midY)
    }

    /// About: the crew manual's cover swings open on its spine to the first page.
    private func manual(_ p: GalleyLayout.Placement, _ t: TimeInterval) -> some View {
        let frame = GalleyLayout.frame(.manual)
        let hit = p.rect(GalleyLayout.hitRect(.manual))
        let r = p.rect(frame)
        let tip = v(GalleyMotion.manualTip, t)
        let spine = GalleyLayout.manualSpine
        return fitting(.manual, label: "About", p: p, action: { app.sheet = .about }) {
            ZStack(alignment: .topLeading) {
                ManualPage(scale: p.scale)
                    .frame(width: r.width * (0.97 - spine), height: r.height * 0.93)
                    .offset(x: r.width * spine, y: r.height * 0.03)
                Image("GalleyManual")
                    .resizable()
                    .modifier(CoverSwing(angle: opening == .manual ? -158 : 0, spine: spine))
            }
            .frame(width: r.width, height: r.height, alignment: .topLeading)
            // it tips over the bottom corner on the side it leans to
            .rotationEffect(.degrees(tip), anchor: tip >= 0 ? .bottomTrailing : .bottomLeading)
            .offset(x: v(GalleyMotion.manualSlide, t) * p.scale)
            .position(x: r.midX - hit.minX, y: r.midY - hit.minY)
            .frame(width: hit.width, height: hit.height)
        }
        .position(x: hit.midX, y: hit.midY)
    }

    /// A button over a fitting: the pressed motion plays, then the card opens. Its tap area moves with it.
    private func fitting(_ piece: GalleyLayout.Piece, label: String, p: GalleyLayout.Placement,
                         action: @escaping () -> Void, @ViewBuilder content: () -> some View) -> some View {
        Button {
            guard opening == nil else { return }
            if app.device.haptics { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { opening = piece }
            Task {
                try? await Task.sleep(for: .seconds(0.35))      // long enough to see it open
                action()
            }
        } label: {
            content().contentShape(Rectangle())
        }
        .buttonStyle(FittingPress())
        .accessibilityLabel(label)
    }

    private func plateText(_ s: String, at c: CGPoint, p: GalleyLayout.Placement) -> some View {
        Text(s)
            .font(.system(size: 66 * p.scale, weight: .heavy, design: .rounded))
            .foregroundStyle(Self.ink)
            .lineLimit(1).minimumScaleFactor(0.5)
            .frame(width: 420 * p.scale)
            .position(x: c.x * p.scale, y: c.y * p.scale)
    }

    // MARK: Set dressing

    /// The sky through the window: the title card's clouds, smaller and slower, drifting right to left.
    private func windowView(_ p: GalleyLayout.Placement, _ t: TimeInterval) -> some View {
        let r = p.rect(GalleyLayout.frame(.window)).insetBy(dx: -4, dy: -4)
        let clouds: [(name: String, h: CGFloat, y: CGFloat, speed: Double, x: Double)] = [
            ("TitleCloud4", 0.30, 0.25, 0.035, 0.1), ("TitleCloud3", 0.36, 0.62, 0.05, 0.55), ("TitleCloud2", 0.44, 0.95, 0.07, 0.9)]
        return ZStack {
            LinearGradient(colors: [Color(red: 0.42, green: 0.66, blue: 0.93), Color(red: 0.74, green: 0.87, blue: 0.98)],
                           startPoint: .top, endPoint: .bottom)
            ForEach(clouds.indices, id: \.self) { i in
                let c = clouds[i]
                let h = r.height * c.h, w = h * 1.75
                let span = r.width + w
                let x = (c.x * span - t * c.speed * span * (motion > 0 ? 1 : 0)).truncatingRemainder(dividingBy: span)
                Image(c.name).resizable().scaledToFit().frame(height: h)
                    .position(x: (x < 0 ? x + span : x) - w / 2, y: r.height * c.y)
            }
        }
        .frame(width: r.width, height: r.height)
        .clipped()
        .position(x: r.midX, y: r.midY)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func cups(_ p: GalleyLayout.Placement, _ t: TimeInterval) -> some View {
        ZStack(alignment: .topLeading) {
            cup("GalleyCup", .cupA, p, hop: v(GalleyMotion.cupHop, t))
            cup("GalleyCupB", .cupB, p, hop: v(GalleyMotion.cupHop, t, delay: 0.05))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func cup(_ name: String, _ piece: GalleyLayout.Piece, _ p: GalleyLayout.Placement, hop: Double) -> some View {
        let r = p.rect(GalleyLayout.frame(piece))
        return Image(name).resizable()
            .frame(width: r.width, height: r.height)
            .rotationEffect(.degrees(hop * 0.4), anchor: .bottom)
            .position(x: r.midX, y: r.midY - abs(hop) * p.scale)
    }

    /// The coffee is drawn here, not painted: a wavy surface that tilts against each jolt and sloshes back,
    /// clipped to the inside of the glass pot.
    private func coffee(_ p: GalleyLayout.Placement, _ t: TimeInterval) -> some View {
        let r = p.rect(GalleyLayout.frame(.pot))
        let tilt = v(GalleyMotion.coffeeTilt, t) + GalleyMotion.coffeeRipple(at: t) * motion
        let slosh = abs(v(GalleyMotion.coffeeTilt, t)) / GalleyMotion.coffeeTilt.amplitude
        return Canvas { ctx, size in
            let level = size.height * 0.5
            let slope = tan(tilt * .pi / 180)
            let waveH = size.height * (0.015 + 0.05 * slosh)
            var surface = Path()
            surface.move(to: CGPoint(x: 0, y: size.height))
            for i in 0...24 {
                let x = size.width * Double(i) / 24
                let y = level + slope * (x - size.width / 2) + waveH * sin(Double(i) / 24 * 2 * .pi * 1.5 + t * 5)
                surface.addLine(to: CGPoint(x: x, y: y))
            }
            surface.addLine(to: CGPoint(x: size.width, y: size.height))
            surface.closeSubpath()
            ctx.fill(surface, with: .linearGradient(
                Gradient(colors: [Color(red: 0.42, green: 0.25, blue: 0.14), Color(red: 0.20, green: 0.11, blue: 0.06)]),
                startPoint: CGPoint(x: 0, y: level), endPoint: CGPoint(x: 0, y: size.height)))
        }
        .frame(width: r.width, height: r.height)
        .clipShape(PotGlass())
        .blendMode(.multiply)
        .position(x: r.midX, y: r.midY)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The coffee maker's ready light dips twice on a bump.
    private func readyLight(_ p: GalleyLayout.Placement, _ t: TimeInterval) -> some View {
        let r = p.rect(GalleyLayout.frame(.readyLight))
        return RoundedRectangle(cornerRadius: r.width / 3)
            .fill(Color.black.opacity(min(0.45, abs(v(GalleyMotion.lightFlicker, t)) * 0.45)))
            .frame(width: r.width * 0.7, height: r.height * 0.8)
            .position(x: r.midX, y: r.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The inside of the coffee pot's glass: narrow under the collar, round at the bottom.
private struct PotGlass: Shape {
    func path(in r: CGRect) -> Path {
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var p = Path()
        p.move(to: pt(0.2, 0))
        p.addQuadCurve(to: pt(0.01, 0.55), control: pt(0.03, 0.15))
        p.addQuadCurve(to: pt(0.14, 0.98), control: pt(-0.01, 0.92))
        p.addLine(to: pt(0.86, 0.98))
        p.addQuadCurve(to: pt(0.99, 0.55), control: pt(1.01, 0.92))
        p.addQuadCurve(to: pt(0.8, 0), control: pt(0.97, 0.15))
        p.closeSubpath()
        return p
    }
}

/// The inside of the oven behind its door: dark metal, a rack, and a warm glow once it's open.
private struct OvenInside: View {
    let lit: Bool
    let scale: CGFloat
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 14 * scale)
                    .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.27)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 10 * scale)
                    .fill(Color(white: 0.34))
                    .frame(width: w * 0.62, height: h * 0.55)
                    .offset(y: -h * 0.04)
                ForEach(0..<2) { i in
                    Capsule().fill(Color(white: 0.62))
                        .frame(width: w * 0.8, height: max(1, 5 * scale))
                        .offset(y: h * (0.18 + 0.06 * Double(i)))
                }
                RadialGradient(colors: [Color.orange.opacity(0.75), Color.orange.opacity(0)],
                               center: .init(x: 0.5, y: 0.3), startRadius: 0, endRadius: w * 0.55)
                    .blendMode(.screen)
                    .opacity(lit ? 1 : 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14 * scale))
        }
    }
}

/// The crew manual's first page, under the cover: ring holes and a few lines.
private struct ManualPage: View {
    let scale: CGFloat
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6 * scale).fill(Color(red: 0.97, green: 0.95, blue: 0.89))
                ForEach(0..<3) { i in
                    Circle().fill(Color(white: 0.75))
                        .frame(width: 16 * scale, height: 16 * scale)
                        .offset(x: w * 0.05, y: h * (0.15 + 0.33 * Double(i)))
                }
                Text("CREW MANUAL")
                    .font(.system(size: 24 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.navy)
                    .offset(x: w * 0.2, y: h * 0.1)
                ForEach(0..<6) { i in
                    Capsule().fill(Color(white: 0.8))
                        .frame(width: w * (i % 3 == 2 ? 0.45 : 0.65), height: max(1, 6 * scale))
                        .offset(x: w * 0.2, y: h * (0.3 + 0.1 * Double(i)))
                }
            }
        }
    }
}

/// The binder's cover turning on its spine. Past 90° the inside of the cover shows, not the mirrored front.
private struct CoverSwing: ViewModifier, Animatable {
    var angle: Double
    let spine: Double
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }
    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: [Color(red: 0.13, green: 0.16, blue: 0.29), Color(red: 0.20, green: 0.24, blue: 0.40)],
                                         startPoint: .leading, endPoint: .trailing))
                    .opacity(abs(angle) > 90 ? 1 : 0)
            }
            .brightness(-abs(sin(angle * .pi / 180)) * 0.15)
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: UnitPoint(x: spine, y: 0.5), perspective: 0.45)
    }
}

/// A cart rocks on its wheels and slides a little; pressed, it rolls toward you (the drawer art comes in phase 2).
private struct CartMotion: ViewModifier {
    let open: Bool
    let tilt: Double
    let slide: Double
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(tilt), anchor: tilt >= 0 ? .bottomTrailing : .bottomLeading)
            .offset(x: slide)
            .scaleEffect(open ? 1.04 : 1, anchor: .bottom)
    }
}

/// Pressed fittings darken a touch.
private struct FittingPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.brightness(configuration.isPressed ? -0.06 : 0)
    }
}
