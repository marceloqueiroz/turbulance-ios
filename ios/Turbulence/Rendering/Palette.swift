import SwiftUI
import UIKit

/// GDD §8a palette, plus the night-sky chrome around the fuselage.
enum Palette {
    static let cream = UIColor(hex: 0xE8E2D8)
    static let carpet = UIColor(hex: 0xD6CCBD)
    static let navy = UIColor(hex: 0x1B2A4A)
    static let navyDeep = UIColor(hex: 0x111C33)
    static let steel = UIColor(hex: 0xC9CDD3)
    static let coral = UIColor(hex: 0xE8543E)
    static let teal = UIColor(hex: 0x1F8A8C)
    static let calm = UIColor(hex: 0xF5B942)
    static let urgent = UIColor(hex: 0xE8783E)
    static let critical = UIColor(hex: 0xD62828)
    static let failed = UIColor(hex: 0x8A8F99)
    static let sky = UIColor(hex: 0x0E1830)
    static let panel = UIColor(hex: 0x17264A)
    static let panelLine = UIColor(hex: 0x2A3B63)
    static let text = UIColor(hex: 0xF3EEE6)
    static let muted = UIColor(hex: 0xA9B3C8)

    static let skins: [UIColor] = [0xF1C9A5, 0xD9A07A, 0xA86F4C, 0x7A4A31, 0xF5D7BE].map { UIColor(hex: $0) }
    static let hairs: [UIColor] = [0x2B1D14, 0x5A3A22, 0xC9A15B, 0x1A1A1A, 0x8E8E8E, 0xA0442A].map { UIColor(hex: $0) }

    static func shirt(_ a: Archetype) -> UIColor {
        switch a {
        case .business: return UIColor(hex: 0x3A3F4B)
        case .family: return UIColor(hex: 0xE2A93B)
        case .nervous: return UIColor(hex: 0x9B8BC4)
        case .sleeper: return UIColor(hex: 0x6F8AA6)
        case .chatterbox: return UIColor(hex: 0xD9728F)
        }
    }

    static func escalation(_ e: Escalation) -> UIColor {
        switch e {
        case .calm: return calm
        case .urgent: return urgent
        case .critical: return critical
        case .failed: return failed
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}
