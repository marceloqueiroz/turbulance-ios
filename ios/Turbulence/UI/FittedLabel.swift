import SwiftUI

/// Words printed on painted art (cart plates, placards, the tag, the binder cover, the Options panel). Each label gets
/// the box of the surface it's printed on and never leaves it: it shrinks down to `minScale`, wraps onto up to
/// `lines` lines, and only as a last resort is cut short, so longer translations still fit (specs/2026-10-08-galley-main-menu.md).
/// Write keys in sentence case and let `upper` capitalise them, so translators see normal words.
struct FittedLabel: View {
    let text: Text
    let box: CGSize
    var lines = 1
    var minScale: CGFloat = 0.5
    var upper = false

    var body: some View {
        text
            .lineLimit(lines)
            .minimumScaleFactor(minScale)
            .allowsTightening(true)
            .multilineTextAlignment(.center)
            .textCase(upper ? .uppercase : nil)
            .frame(width: box.width, height: box.height)
    }
}

extension Text {
    /// This text fitted into the box of the surface it's printed on (see `FittedLabel`).
    func fitted(_ box: CGSize, lines: Int = 1, minScale: CGFloat = 0.5, upper: Bool = false) -> FittedLabel {
        FittedLabel(text: self, box: box, lines: lines, minScale: minScale, upper: upper)
    }
}
