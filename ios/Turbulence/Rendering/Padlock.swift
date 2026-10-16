import SpriteKit
import UIKit

/// The padlock over a locked route on the route map (GDD §9): painted soft-3D art (`Map/Padlock`, `Map/PadlockOpen`)
/// when it's in the catalogue, else a code-drawn brass lock of the same size. Sized in screen points; the badge
/// it sits on keeps it the same size at any zoom.
final class Padlock: SKNode {
    static let width: CGFloat = 44
    static let height: CGFloat = 56

    private let closed: SKNode
    private let opened: SKNode

    override init() {
        if let shut = UIImage(named: "Map/Padlock"), let open = UIImage(named: "Map/PadlockOpen") {
            closed = Self.sprite(shut)
            opened = Self.sprite(open)
        } else {
            closed = Self.drawn(open: false)
            opened = Self.drawn(open: true)
        }
        super.init()
        opened.isHidden = true
        addChild(closed)
        addChild(opened)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The shackle springs up.
    func open() {
        closed.isHidden = true
        opened.isHidden = false
    }

    private static func sprite(_ image: UIImage) -> SKSpriteNode {
        let node = SKSpriteNode(texture: SKTexture(image: image))
        let h = height, w = h * image.size.width / max(image.size.height, 1)
        node.size = CGSize(width: w, height: h)
        return node
    }

    /// Stand-in until the painted art lands: brass body, coral keyhole plate, steel shackle, soft drop shadow.
    private static func drawn(open: Bool) -> SKNode {
        let node = SKNode()
        let bodyH = height * 0.6, bodyY = -height / 2 + bodyH / 2
        let shadow = SKShapeNode(ellipseOf: CGSize(width: width * 0.9, height: 10))
        shadow.fillColor = UIColor.black.withAlphaComponent(0.18); shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -height / 2 - 2)
        node.addChild(shadow)

        // the shackle: a thick rounded arch; open, it lifts and swings clear of the right-hand socket
        let r = width * 0.27, lift: CGFloat = open ? height * 0.15 : 0
        let arch = CGMutablePath()
        arch.move(to: CGPoint(x: -r, y: bodyY + bodyH / 2 - 4))
        arch.addLine(to: CGPoint(x: -r, y: bodyY + bodyH / 2 + 8))
        arch.addArc(center: CGPoint(x: 0, y: bodyY + bodyH / 2 + 8), radius: r, startAngle: .pi, endAngle: 0, clockwise: true)
        arch.addLine(to: CGPoint(x: r, y: bodyY + bodyH / 2 + (open ? 2 : -4)))
        let shackle = SKShapeNode(path: arch)
        shackle.strokeColor = Palette.steel; shackle.lineWidth = 8; shackle.lineCap = .round
        shackle.position = CGPoint(x: open ? -8 : 0, y: lift)
        shackle.zRotation = open ? 0.18 : 0
        node.addChild(shackle)

        let body = SKShapeNode(rect: CGRect(x: -width / 2, y: bodyY - bodyH / 2, width: width, height: bodyH), cornerRadius: 12)
        body.fillColor = Palette.calm; body.strokeColor = UIColor(hex: 0xC98F1F); body.lineWidth = 2
        node.addChild(body)
        let shine = SKShapeNode(rect: CGRect(x: -width / 2 + 7, y: bodyY + bodyH / 2 - 13, width: width - 14, height: 7), cornerRadius: 3.5)
        shine.fillColor = UIColor.white.withAlphaComponent(0.35); shine.strokeColor = .clear
        node.addChild(shine)
        let plate = SKShapeNode(circleOfRadius: 11)
        plate.fillColor = Palette.coral; plate.strokeColor = .clear
        plate.position = CGPoint(x: 0, y: bodyY - 2)
        node.addChild(plate)
        let hole = CGMutablePath()
        hole.addEllipse(in: CGRect(x: -3.5, y: bodyY, width: 7, height: 7))
        hole.addRect(CGRect(x: -1.6, y: bodyY - 8, width: 3.2, height: 9))
        let keyhole = SKShapeNode(path: hole)
        keyhole.fillColor = Palette.navy; keyhole.strokeColor = .clear
        node.addChild(keyhole)
        return node
    }
}
