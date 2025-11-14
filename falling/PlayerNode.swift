import SpriteKit

/// PlayerNode now uses a sprite sheet named "falling_guy" (4 columns x 2 rows, 8 frames)
/// The node remains an SKSpriteNode so existing code that assigns physics bodies to it continues to work.
class PlayerNode: SKSpriteNode {
    private let sprite = SKSpriteNode()
    private var frames: [SKTexture] = []
    private var bodySize: CGSize

    init(size: CGSize) {
        self.bodySize = size
        super.init(texture: nil, color: .clear, size: size)
        isUserInteractionEnabled = false
        zPosition = 10

        buildAppearance()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildAppearance() {
        // Configure the child sprite node that will show animation frames
        sprite.size = bodySize
        sprite.zPosition = 0
        sprite.position = CGPoint(x: 0, y: 0)
        addChild(sprite)

        // Attempt to load the spritesheet texture
        let sheetName = "character_sprite"
        let sheet = SKTexture(imageNamed: sheetName)

        // If texture could not be found, fallback to a simple colored rectangle
        if sheet.size() == CGSize.zero {
            sprite.color = .systemTeal
            sprite.colorBlendFactor = 1.0
            startPlaceholderAnimation()
            return
        }

        // Sprite sheet layout: 4 columns, 2 rows, total 8 frames
        let cols = 4
        let rows = 1
        var texs: [SKTexture] = []

        // We want frame order left-to-right, top-to-bottom
        for row in 0..<rows {
            for col in 0..<cols {
                let x = CGFloat(col) / CGFloat(cols)
                // Texture rect uses unit coordinates with origin at bottom-left; convert top-based row to bottom-based y
                let y = CGFloat(rows - 1 - row) / CGFloat(rows)
                let w = 1.0 / CGFloat(cols)
                let h = 1.0 / CGFloat(rows)
                let rect = CGRect(x: x, y: y, width: w, height: h)
                let frameTex = SKTexture(rect: rect, in: sheet)
                texs.append(frameTex)
            }
        }

        // Keep only first 8 frames in case the sheet has extra
        frames = Array(texs.prefix(8))

        if frames.isEmpty {
            sprite.color = .systemTeal
            sprite.colorBlendFactor = 1.0
            startPlaceholderAnimation()
            return
        }

        // Set initial texture and run the animation
        sprite.texture = frames.first
        startSpriteAnimation()

        // Create a physics body from the texture so the debug outline matches the sprite silhouette
        if let firstTex = frames.first {
            // Use the texture's alpha to build a tighter shape
            let body = SKPhysicsBody(texture: firstTex, size: bodySize)
            body.isDynamic = true
            body.affectedByGravity = false
            body.allowsRotation = false
            body.usesPreciseCollisionDetection = true
            body.categoryBitMask = 0 // leave masks to the scene-level config
            body.contactTestBitMask = 0
            body.collisionBitMask = 0
            // Assign to the parent node; GameScene will set the correct masks after adding the node
            self.physicsBody = body
        }
    }

    private func startSpriteAnimation() {
        guard !frames.isEmpty else { return }
        // Use a reasonable frame duration (e.g., 12 fps -> ~0.083s per frame)
        let frameDuration: TimeInterval = 0.08
        let anim = SKAction.animate(with: frames, timePerFrame: frameDuration, resize: false, restore: false)
        let loop = SKAction.repeatForever(anim)
        sprite.run(loop, withKey: "fallingAnimation")
    }

    private func startPlaceholderAnimation() {
        // simple pulse so the player is visible if the sprite sheet is missing
        let pulse = SKAction.sequence([SKAction.fadeAlpha(to: 0.6, duration: 0.3), SKAction.fadeAlpha(to: 1.0, duration: 0.3)])
        sprite.run(SKAction.repeatForever(pulse), withKey: "placeholder")
    }

    func stopAnimation() {
        sprite.removeAction(forKey: "fallingAnimation")
        sprite.removeAction(forKey: "placeholder")
    }

    /// Optionally adjust visual scale for a vertical orientation
    /// We apply this to the child sprite so physics body on the parent can remain unchanged (or be updated externally).
    func setVisualScaleFor(vertical: Bool) {
        if vertical {
            let scaleX: CGFloat = 0.7
            let scaleY: CGFloat = 1.25
            sprite.run(SKAction.group([SKAction.scaleX(to: scaleX, duration: 0.12), SKAction.scaleY(to: scaleY, duration: 0.12)]))
        } else {
            sprite.run(SKAction.group([SKAction.scaleX(to: 1.0, duration: 0.12), SKAction.scaleY(to: 1.0, duration: 0.12)]))
        }
    }
}
