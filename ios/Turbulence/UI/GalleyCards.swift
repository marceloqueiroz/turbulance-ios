import SwiftUI
import UIKit

// MARK: - Options and About as galley things (GDD §9a; specs/2026-10-08-galley-main-menu.md "Options and About cards")
//
// Options is the oven's control panel and About is the open crew manual. The art (`Cards` in the asset catalog) is
// text-free: every word, the logo and the studio mark are drawn here. Positions are fractions of each picture.

/// A picture fitted into the space it's given, with helpers to place things on it by fraction.
private struct Sheet {
    let w: CGFloat
    let h: CGFloat
    func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
    /// A length as a fraction of the picture's width.
    func len(_ f: CGFloat) -> CGFloat { f * w }

    static func fit(_ aspect: CGFloat, in size: CGSize, margin: CGFloat = 0.96) -> Sheet {
        let w = min(size.width * margin, size.height * margin * aspect)
        return Sheet(w: w, h: w / aspect)
    }
}

private let engrave = Color(red: 0x56 / 255, green: 0x4E / 255, blue: 0x47 / 255)
private let placardInk = Color(red: 0x5B / 255, green: 0x3A / 255, blue: 0x29 / 255)

// MARK: Options

/// The oven control panel: a knob for sound and a toggle lever with a lamp for haptics, both settings of this
/// device, and Done. (Screen shake and text size are no longer offered here.)
struct OptionsPanel: View {
    @State var device: DeviceSettings
    let updateDevice: (DeviceSettings) -> Void
    let done: () -> Void
    #if DEBUG
    var developer: DevSection?
    @State private var showDeveloper = false
    #endif

    init(device: DeviceSettings, updateDevice: @escaping (DeviceSettings) -> Void, done: @escaping () -> Void) {
        _device = State(initialValue: device)
        self.updateDevice = updateDevice
        self.done = done
    }

    private static let aspect: CGFloat = 1389 / 1549
    /// Where each part sits on `OptionsPanel` (fractions of its width and height).
    private enum Spot {
        static let title = CGPoint(x: 0.5024, y: 0.1336)
        static let knob = CGPoint(x: 0.343, y: 0.503)
        static let lamp = CGPoint(x: 0.705, y: 0.379)
        static let toggle = CGPoint(x: 0.705, y: 0.521)        // the hex nut the lever sits in
        static let soundPlacard = CGPoint(x: 0.346, y: 0.689)
        static let hapticsPlacard = CGPoint(x: 0.705, y: 0.689)
        static let button = CGPoint(x: 0.5016, y: 0.877)
    }

    var body: some View {
        GeometryReader { geo in
            let s = Sheet.fit(Self.aspect, in: geo.size)
            ZStack(alignment: .topLeading) {
                Image("OptionsPanel").resizable().accessibilityHidden(true)
                words(s)
                soundKnob(s)
                hapticsToggle(s)
                doneButton(s)
                #if DEBUG
                if developer != nil {
                    Button { showDeveloper = true } label: {
                        Text("DEV").font(.system(size: max(9, s.len(0.024)), weight: .heavy, design: .rounded))
                            .tracking(1).foregroundStyle(engrave.opacity(0.7))
                            .padding(8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Developer settings")
                    .position(s.at(0.875, 0.877))
                }
                #endif
            }
            .frame(width: s.w, height: s.h)
            .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        #if DEBUG
        .overlay {
            if showDeveloper, let developer {
                Card {
                    developer
                    CTA(title: "Close") { showDeveloper = false }.padding(.bottom, 4)
                }
                .frame(maxWidth: 420)
            }
        }
        #endif
        .onChange(of: device) { _, new in updateDevice(new) }
    }

    // MARK: Words

    private func words(_ s: Sheet) -> some View {
        ZStack(alignment: .topLeading) {
            Text("Options")
                .font(.system(size: s.len(0.08), weight: .heavy, design: .rounded))
                .tracking(s.len(0.006))
                .foregroundStyle(Color.cream)
                .fitted(CGSize(width: s.len(0.54), height: s.len(0.1)), upper: true)
                .position(s.at(Spot.title.x, Spot.title.y))
                .accessibilityAddTraits(.isHeader)
            placard("Sound", at: Spot.soundPlacard, s)
            placard("Haptics", at: Spot.hapticsPlacard, s)
            Image(systemName: "speaker.fill")
                .font(.system(size: s.len(0.03))).foregroundStyle(engrave)
                .position(s.at(0.225, 0.64)).accessibilityHidden(true)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: s.len(0.03))).foregroundStyle(engrave)
                .position(s.at(0.47, 0.64)).accessibilityHidden(true)
        }
    }

    private func placard(_ text: LocalizedStringKey, at p: CGPoint, _ s: Sheet) -> some View {
        Text(text)
            .font(.system(size: s.len(0.034), weight: .heavy, design: .rounded))
            .foregroundStyle(placardInk)
            .fitted(CGSize(width: s.len(0.16), height: s.len(0.058)), lines: 2, upper: true)     // clear of the screws
            .position(s.at(p.x, p.y))
            .accessibilityHidden(true)          // each control reads its own name
    }

    // MARK: Controls

    /// Sound: turn the knob (drag round it) over a 270° sweep; VoiceOver swipes up and down by 10%.
    private func soundKnob(_ s: Sheet) -> some View {
        let size = s.len(0.28)
        return Image("OptionsKnob")
            .resizable()
            .frame(width: size, height: size)
            .rotationEffect(.degrees(-135 + 270 * device.volume))
            .frame(width: size * 1.3, height: size * 1.3)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let c = size * 0.65
                let a = atan2(g.location.x - c, c - g.location.y) * 180 / .pi     // 0 = up, clockwise
                device.volume = min(1, max(0, (a + 135) / 270))
            })
            .accessibilityElement()
            .accessibilityLabel("Sound")
            .accessibilityValue("\(Int((device.volume * 100).rounded())) percent")
            .accessibilityAdjustableAction { dir in
                device.volume = min(1, max(0, device.volume + (dir == .increment ? 0.1 : -0.1)))
            }
            .position(s.at(Spot.knob.x, Spot.knob.y))
    }

    /// Haptics: a toggle lever with a green lamp above it.
    private func hapticsToggle(_ s: Sheet) -> some View {
        let on = device.haptics
        let w = s.len(0.125)
        // the lever pictures differ in height; place each so its round base sits on the panel's nut
        let h = w * (on ? 350.0 / 253 : 325.0 / 253)
        let base = on ? 0.67 : 0.34
        let nut = s.at(Spot.toggle.x, Spot.toggle.y)
        return ZStack(alignment: .topLeading) {
            Image(on ? "OptionsLampOn" : "OptionsLampOff")
                .resizable()
                .frame(width: s.len(0.08), height: s.len(0.08))
                .shadow(color: .green.opacity(on ? 0.8 : 0), radius: s.len(0.024))
                .position(s.at(Spot.lamp.x, Spot.lamp.y))
                .accessibilityHidden(true)
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { device.haptics.toggle() }
                if device.haptics { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
            } label: {
                Image(on ? "OptionsToggleUp" : "OptionsToggleDown")
                    .resizable()
                    .frame(width: w, height: h)
                    .frame(width: w * 1.6, height: w * 2.2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Haptics")
            .accessibilityValue(on ? "On" : "Off")
            .accessibilityAddTraits(.isToggle)
            .position(x: nut.x, y: nut.y - (base - 0.5) * h)
        }
    }

    private func doneButton(_ s: Sheet) -> some View {
        Button(action: done) { EmptyView() }
            .buttonStyle(PanelButton(width: s.len(0.43), title: "Done", size: s.len(0.06)))
            .accessibilityLabel("Done")
            .position(s.at(Spot.button.x, Spot.button.y))
    }
}

/// The coral push button: raised, then pressed in while held.
private struct PanelButton: ButtonStyle {
    let width: CGFloat
    let title: LocalizedStringKey
    let size: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        Image(configuration.isPressed ? "OptionsButtonPressed" : "OptionsButton")
            .resizable()
            .frame(width: width, height: width * 312 / 883)
            .overlay {
                Text(title)
                    .font(.system(size: size, weight: .heavy, design: .rounded))
                    .tracking(size * 0.07)
                    .foregroundStyle(Color.cream.opacity(configuration.isPressed ? 0.85 : 1))
                    .fitted(CGSize(width: width * 0.74, height: width * 0.22), upper: true)
                    .offset(y: configuration.isPressed ? size * 0.08 : 0)
            }
            .contentShape(Capsule())
    }
}

// MARK: About

/// The crew manual open at its first page: the logo, version and studio on the left, the manual's sections on the
/// right. The ribbon bookmark (or the × in the corner) closes it.
struct AboutSpread: View {
    let close: () -> Void

    private static let aspect: CGFloat = 2707 / 1490

    private var version: Text {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return Text("Version \(v) (\(b))")
    }

    private let sections: [(LocalizedStringKey, LocalizedStringKey)] = [
        ("Credits", "Designed and built by Zelda Labs. Sound effects are synthesised in the game."),
        ("Privacy", "Your crew and progress are saved on this device only. No account, no ads, no tracking."),
        ("Made with", "Swift, SwiftUI and SpriteKit."),
    ]

    var body: some View {
        GeometryReader { geo in
            let s = Sheet.fit(Self.aspect, in: geo.size)
            let body = max(12, s.len(0.0145)), head = max(15, s.len(0.021))
            ZStack(alignment: .topLeading) {
                Image("AboutSpread").resizable().accessibilityHidden(true)
                // left page: inside its printed frame
                VStack(spacing: s.len(0.012)) {
                    Spacer(minLength: 0)
                    Image("LogoCrew")
                        .resizable().scaledToFit()
                        .frame(width: s.len(0.25))
                        .accessibilityLabel("Turbulence")
                    Spacer(minLength: 0)
                    version.font(.system(size: body, weight: .semibold, design: .rounded))
                    HStack(spacing: s.len(0.008)) {
                        ZeldaLabsMark().frame(width: s.len(0.04), height: s.len(0.04)).accessibilityHidden(true)
                        Text(verbatim: "Zelda Labs").font(.system(size: body, weight: .bold, design: .rounded))
                    }
                    Spacer(minLength: 0).frame(height: s.len(0.02))
                }
                .foregroundStyle(Color.navy)
                .frame(width: (0.436 - 0.0924) * s.w, height: (0.827 - 0.054) * s.h)
                .position(s.at((0.0924 + 0.436) / 2, (0.054 + 0.827) / 2))
                // right page: the manual's sections, clear of the ribbon
                ScrollView {
                    VStack(alignment: .leading, spacing: s.len(0.006)) {
                        ForEach(sections.indices, id: \.self) { i in
                            (Text(verbatim: "\(i + 1). ") + Text(sections[i].0))
                                .font(.system(size: head, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color.coral)
                                .accessibilityAddTraits(.isHeader)
                            Text(sections[i].1)
                                .font(.system(size: body, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.navy)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, s.len(0.016))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                // the page fades out at the bottom, so a longer translation reads as "scroll for more"
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.86), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: (0.894 - 0.613) * s.w, height: (0.78 - 0.09) * s.h)
                .position(s.at((0.613 + 0.894) / 2, (0.09 + 0.78) / 2))
                Text("p. 1")
                    .font(.system(size: max(10, s.len(0.011)), weight: .semibold, design: .rounded))
                    .foregroundStyle(engrave)
                    .position(s.at(0.875, 0.8))
                    .accessibilityHidden(true)
                // the ribbon closes the manual
                Button(action: close) {
                    Color.clear.frame(width: s.len(0.045), height: 0.64 * s.h).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(s.at(0.5875, 0.32))
                .accessibilityHidden(true)
                Button(action: close) {
                    // a round coral button on the binder's corner, in the game's pressed-capsule style
                    let d = max(34, s.len(0.034))
                    Image(systemName: "xmark")
                        .font(.system(size: d * 0.42, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: d, height: d)
                        .background(Color.coral, in: Circle())
                        .overlay(Circle().stroke(Color.navy, lineWidth: 3))
                        .background(Circle().fill(Color.navy).offset(y: 3))
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        .frame(width: max(44, d), height: max(44, d))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .position(s.at(0.935, 0.075))
                .accessibilityLabel("Close")
            }
            .frame(width: s.w, height: s.h)
            .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}
