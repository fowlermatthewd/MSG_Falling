//
//  GameViewController.swift
//  fallin
//
//  Created by Matthew fowler on 10/28/25.
//

import UIKit
import SpriteKit
import GameplayKit

class GameViewController: UIViewController {

    private var scenePresented = false

    override func viewDidLoad() {
        super.viewDidLoad()

        // keep viewDidLoad minimal; scene will be presented in viewDidLayoutSubviews so it uses the final view size
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard let skView = self.view as? SKView else { return }

        // Present the scene the first time using the view's bounds so the scene coordinate space matches the view
        if !scenePresented {
            let scene = GameScene(size: skView.bounds.size)
            scene.scaleMode = .resizeFill
            skView.presentScene(scene)

            skView.ignoresSiblingOrder = true
            skView.showsFPS = true
            skView.showsNodeCount = true
            // Helpful debug overlays while developing collisions
            skView.showsPhysics = true
            skView.showsFields = true

            scenePresented = true
            return
        }

        // On subsequent layout changes (rotation/resize) update the scene's size so content spans the full view
        if let scene = skView.scene {
            scene.size = skView.bounds.size
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }
}
