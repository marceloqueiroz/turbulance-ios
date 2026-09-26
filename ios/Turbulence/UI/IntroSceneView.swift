import SceneKit
import SwiftUI

/// Shows the 3D intro cutscene (GDD §8b) full screen, above the 2D cabin it hands over to.
struct IntroSceneView: UIViewRepresentable {
    let intro: IntroScene3D

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
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

    func updateUIView(_ view: SCNView, context: Context) {
        if view.scene !== intro.scene { view.scene = intro.scene; view.pointOfView = intro.cameraNode }
    }
}
