import CoreGraphics

/// Where the pieces of the galley main menu sit (GDD §9a; specs/galley-main-menu). Every rectangle is in the
/// pixels of the wall picture (`GalleyWall`, 3168 × 1344); `placement(in:)` maps them onto a screen.
/// Phase 1 prototype: the layers are cut from the mockup, so these numbers change with the final art.
enum GalleyLayout {
    static let wall = CGSize(width: 3168, height: 1344)
    /// What must always be on screen: the tag on the left to the teal cart's handle on the right, the window top to the floor.
    static let safe = CGRect(x: 495, y: 50, width: 2170, height: 1250)

    enum Piece: CaseIterable {
        case cartContinue, cartNewGame, tag, manual, cupA, cupB, pot, readyLight, window, oven
    }

    /// The picture's own frame (for the four buttons, `hitRect` is the tap area).
    static func frame(_ piece: Piece) -> CGRect {
        switch piece {
        case .cartContinue: CGRect(x: 516, y: 864, width: 1005, height: 476)
        case .cartNewGame: CGRect(x: 1604, y: 864, width: 1042, height: 476)
        case .tag: CGRect(x: 507, y: 936, width: 116, height: 225)
        case .manual: CGRect(x: 2164, y: 206, width: 322, height: 337)
        case .cupA: CGRect(x: 1357, y: 621, width: 122, height: 172)
        case .cupB: CGRect(x: 1483, y: 621, width: 127, height: 172)
        case .pot: CGRect(x: 1305, y: 393, width: 195, height: 117)       // the glass of the coffee pot, under its collar
        case .readyLight: CGRect(x: 1544, y: 233, width: 45, height: 160)
        case .window: CGRect(x: 680, y: 152, width: 286, height: 386)
        case .oven: CGRect(x: 1671, y: 114, width: 444, height: 496)      // the oven and its OPTIONS placard
        }
    }

    /// The tap areas of the four buttons, in wall pixels: the binder's covers its cubby and the ABOUT placard.
    static func hitRect(_ piece: Piece) -> CGRect {
        piece == .manual ? CGRect(x: 2150, y: 200, width: 345, height: 415) : frame(piece)
    }

    static let buttons: [Piece] = [.cartContinue, .cartNewGame, .oven, .manual]

    /// The middle of each cart's label plate, from the cart's top-left corner; the tag's pivot (where its string
    /// hangs from the cart handle), from the tag's top-left corner.
    static let continuePlate = CGPoint(x: 551, y: 283)
    static let newGamePlate = CGPoint(x: 464, y: 283)
    static let tagPivot = CGPoint(x: 55, y: 2)
    /// The oven door (`GalleyOvenDoor`), hinged at its bottom edge.
    static let ovenDoor = CGRect(x: 1672, y: 212, width: 443, height: 328)
    /// The binder's spine, as a fraction of its width: the cover swings open about it.
    static let manualSpine = 0.06

    /// How the wall sits on a screen: one scale and the wall's top-left corner, in points.
    struct Placement {
        let scale: CGFloat
        let origin: CGPoint
        func rect(_ r: CGRect) -> CGRect {
            CGRect(x: origin.x + r.minX * scale, y: origin.y + r.minY * scale, width: r.width * scale, height: r.height * scale)
        }
        var wallRect: CGRect { rect(CGRect(origin: .zero, size: GalleyLayout.wall)) }
    }

    /// The wall fills the screen where it can, but never crops the safe area: a wide iPhone crops the far wall at
    /// the sides; an iPad shows the whole wall with a band above and below.
    static func placement(in size: CGSize) -> Placement {
        let fill = max(size.width / wall.width, size.height / wall.height)
        let fitSafe = min(size.width / safe.width, size.height / safe.height)
        let s = min(fill, fitSafe)
        var x = size.width / 2 - safe.midX * s
        var y = size.height / 2 - safe.midY * s
        if wall.width * s >= size.width { x = min(0, max(size.width - wall.width * s, x)) }
        if wall.height * s >= size.height { y = min(0, max(size.height - wall.height * s, y)) }
        return Placement(scale: s, origin: CGPoint(x: x, y: y))
    }

    /// A button's tap area on screen, grown to at least 44 × 44 pt around its middle.
    static func tapRect(_ piece: Piece, in size: CGSize) -> CGRect {
        let r = placement(in: size).rect(hitRect(piece))
        return r.insetBy(dx: min(0, (r.width - 44) / 2), dy: min(0, (r.height - 44) / 2))
    }
}
