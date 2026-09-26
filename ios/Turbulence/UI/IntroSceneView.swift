import SceneKit
import SpriteKit
import SwiftUI

/// Shows the 3D intro cutscene (GDD §8b) full screen, above the 2D cabin it hands over to.
struct IntroSceneView: UIViewRepresentable {
    let intro: IntroScene3D

    func makeUIView(context: Context) -> IntroSCNView {
        let view = IntroSCNView()
        view.scene = intro.scene
        view.pointOfView = intro.cameraNode
        view.backgroundColor = Palette.sky
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.isPlaying = true
        view.isUserInteractionEnabled = false          // taps go to SwiftUI (skip)
        return view
    }

    func updateUIView(_ view: IntroSCNView, context: Context) {
        if view.scene !== intro.scene { view.scene = intro.scene; view.pointOfView = intro.cameraNode }
    }
}

/// Carries the same vignette the 2D view draws, so the two frames match at the hand-over.
final class IntroSCNView: SCNView {
    private var overlaySize = CGSize.zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 1, bounds.size != overlaySize else { return }
        overlaySize = bounds.size
        let overlay = SKScene(size: bounds.size)
        overlay.backgroundColor = .clear
        overlay.scaleMode = .resizeFill
        let vignette = SKSpriteNode(texture: SKTexture(image: Art.vignette(bounds.size)))
        vignette.anchorPoint = .zero
        vignette.size = bounds.size
        overlay.addChild(vignette)
        overlaySKScene = overlay
    }
}
