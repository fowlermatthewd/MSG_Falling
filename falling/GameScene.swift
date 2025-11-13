//
//  GameScene.swift
//  falling
//
//  Created by Matthew fowler on 11/11/25.
//

import SpriteKit
import GameplayKit

struct PhysicsCategory {
    static let none: UInt32 = 0
    static let player: UInt32 = 0x1 << 0
    static let obstacle: UInt32 = 0x1 << 1
}

class GameScene: SKScene, SKPhysicsContactDelegate {

    // player
    private var player: SKSpriteNode?
    private var isVertical = false

    // spawning
    private var spawnTimer: Timer?
    private var spawnInterval: TimeInterval = 1.0
    private var scrollDuration: TimeInterval = 3.5
    private var obstacleZ: CGFloat = -1

    // swipe tracking
    private var touchStartPoint: CGPoint?
    private var touchStartTime: TimeInterval?

    // flag
    private var runningGame = false

    // game over overlay
    private var gameOverNode: SKNode?
    private var isGameOver = false

    override func didMove(to view: SKView) {
        backgroundColor = SKColor.black

        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self

        setupPlayer()
        startGame()
    }

    // MARK: - Setup
    private func setupPlayer() {
        // Create a simple rectangular player sprite
        let size = CGSize(width: 60, height: 24) // starts horizontal
        let p = SKSpriteNode(color: .systemTeal, size: size)
        // use scene size for placement so it fills full view
        p.position = CGPoint(x: self.size.width / 2.0, y: self.size.height - 120)
        p.zPosition = 10

        p.physicsBody = SKPhysicsBody(rectangleOf: p.size)
        // Make the player dynamic so SpriteKit reports contacts with obstacles.
        // Disable gravity and rotation so the player doesn't move physically.
        p.physicsBody?.isDynamic = true
        p.physicsBody?.affectedByGravity = false
        p.physicsBody?.allowsRotation = false
        // use precise collision detection for reliable contacts with fast-moving obstacles
        p.physicsBody?.usesPreciseCollisionDetection = true
        p.physicsBody?.categoryBitMask = PhysicsCategory.player
        p.physicsBody?.contactTestBitMask = PhysicsCategory.obstacle
        p.physicsBody?.collisionBitMask = PhysicsCategory.none

        addChild(p)
        isVertical = false
        p.zRotation = 0
        player = p
    }

    // Reposition player when size changes (device rotation / layout changes)
    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        // Move player back to top center relative to new size
        // `didChangeSize` can be called before `setupPlayer()` runs; guard against nil
        guard let p = player else { return }
        p.position = CGPoint(x: self.size.width / 2.0, y: self.size.height - 120)

        // If game over overlay is visible, resize its background and reposition labels/buttons
        if let overlay = gameOverNode {
            if let bg = overlay.childNode(withName: "gameOverBackground") as? SKSpriteNode {
                bg.size = self.size
                bg.position = CGPoint(x: self.size.width/2, y: self.size.height/2)
            }
            if let title = overlay.childNode(withName: "gameOverTitle") as? SKLabelNode {
                title.position = CGPoint(x: self.size.width/2, y: self.size.height/2 + 40)
            }
            if let button = overlay.childNode(withName: "gameOverButton") as? SKSpriteNode {
                button.position = CGPoint(x: self.size.width/2, y: self.size.height/2 - 20)
            }
        }
    }

    // MARK: - Game flow
    private func startGame() {
        runningGame = true
        spawnInterval = 0.9
        scrollDuration = 3.5
        startSpawning()
    }

    private func stopGame() {
        runningGame = false
        stopSpawning()
    }

    private func resetGame(after delay: TimeInterval = 0.5) {
        stopGame()

        // small flash to indicate hit
        let flash = SKAction.sequence([
            SKAction.run { [weak self] in self?.player?.color = .systemRed },
            SKAction.wait(forDuration: 0.15),
            SKAction.run { [weak self] in self?.player?.color = .systemTeal }
        ])
        player?.run(flash)

        // remove all obstacles and restart after delay
        run(SKAction.sequence([
            SKAction.wait(forDuration: delay),
            SKAction.run { [weak self] in
                guard let self = self else { return }
                self.removeAllObstacles()
                if let p = self.player {
                    p.position = CGPoint(x: self.size.width / 2.0, y: self.size.height - 120)
                }
                self.setOrientation(vertical: false) // reset to horizontal start
                self.startGame()
            }
        ]))
    }

    // Present a Game Over overlay and stop the game (freeze movement)
    private func showGameOver() {
        guard !isGameOver else { return }
        isGameOver = true

        // stop spawning and mark not running
        stopGame()

        // freeze actions & physics by setting speeds to 0 (so nodes stop moving but touches still work)
        self.speed = 0.0
        self.physicsWorld.speed = 0.0

        // create overlay
        let overlay = SKNode()
        overlay.zPosition = 1000

        let bg = SKSpriteNode(color: UIColor(white: 0.0, alpha: 0.6), size: self.size)
        bg.position = CGPoint(x: self.size.width/2, y: self.size.height/2)
        bg.name = "gameOverBackground"
        overlay.addChild(bg)

        let title = SKLabelNode(text: "Game Over")
        title.fontName = "AvenirNext-Bold"
        title.fontSize = 48
        title.fontColor = .white
        title.position = CGPoint(x: self.size.width/2, y: self.size.height/2 + 40)
        title.name = "gameOverTitle"
        overlay.addChild(title)

        let button = SKSpriteNode(color: .white, size: CGSize(width: 120, height: 48))
        button.position = CGPoint(x: self.size.width/2, y: self.size.height/2 - 20)
        button.name = "gameOverButton"
        button.zPosition = overlay.zPosition + 1
        let okLabel = SKLabelNode(text: "OK")
        okLabel.fontName = "AvenirNext-Bold"
        okLabel.fontSize = 20
        okLabel.fontColor = .black
        okLabel.verticalAlignmentMode = .center
        okLabel.position = CGPoint.zero
        okLabel.name = "gameOverButtonLabel"
        button.addChild(okLabel)
        overlay.addChild(button)

        addChild(overlay)
        gameOverNode = overlay
    }

    // Remove the overlay and restart the game
    private func restartFromGameOver() {
        guard isGameOver else { return }
        // remove overlay
        gameOverNode?.removeFromParent()
        gameOverNode = nil
        isGameOver = false

        // unfreeze
        self.speed = 1.0
        self.physicsWorld.speed = 1.0

        // clear obstacles
        removeAllObstacles()

        // reset player
        if let p = player {
            p.position = CGPoint(x: self.size.width / 2.0, y: self.size.height - 120)
        }
        setOrientation(vertical: false)

        // restart
        startGame()
    }

    private func removeAllObstacles() {
        enumerateChildNodes(withName: "obstacle") { node, _ in
            node.removeAllActions()
            node.removeFromParent()
        }
    }

    // MARK: - Spawning obstacles
    private func startSpawning() {
        // Use SKAction sequence on the scene so we don't have to manage Timer lifecycles across pause states
        let spawn = SKAction.run { [weak self] in self?.spawnObstacleRow() }
        let wait = SKAction.wait(forDuration: spawnInterval)
        let seq = SKAction.sequence([spawn, wait])
        let repeatForever = SKAction.repeatForever(seq)
        run(repeatForever, withKey: "spawning")
    }

    private func stopSpawning() {
        removeAction(forKey: "spawning")
    }

    private func spawnObstacleRow() {
        // Create a horizontal platform with a hole (pit) at random x
        let rowWidth = self.size.width
        let rowHeight: CGFloat = 30.0
        let holeWidthMin: CGFloat = 70
        let holeWidthMax: CGFloat = 160
        let holeWidth = CGFloat.random(in: holeWidthMin...holeWidthMax)

        let holeX = CGFloat.random(in: (holeWidth/2)...(rowWidth - holeWidth/2))

        // left segment
        let leftWidth = holeX - holeWidth/2
        if leftWidth > 1 {
            let left = SKSpriteNode(color: .darkGray, size: CGSize(width: leftWidth, height: rowHeight))
            left.anchorPoint = CGPoint(x: 0, y: 0.5)
            left.position = CGPoint(x: 0, y: -rowHeight) // start below screen
            left.name = "obstacle"
            left.zPosition = obstacleZ
            left.physicsBody = SKPhysicsBody(rectangleOf: left.size, center: CGPoint(x: left.size.width/2, y: 0))
            left.physicsBody?.isDynamic = false
            left.physicsBody?.usesPreciseCollisionDetection = true
            left.physicsBody?.categoryBitMask = PhysicsCategory.obstacle
            left.physicsBody?.contactTestBitMask = PhysicsCategory.player
            left.physicsBody?.collisionBitMask = PhysicsCategory.none
            addChild(left)

            moveObstacleUp(node: left, height: rowHeight)
        }

        // right segment
        let rightWidth = rowWidth - (holeX + holeWidth/2)
        if rightWidth > 1 {
            let right = SKSpriteNode(color: .darkGray, size: CGSize(width: rightWidth, height: rowHeight))
            right.anchorPoint = CGPoint(x: 0, y: 0.5)
            right.position = CGPoint(x: holeX + holeWidth/2, y: -rowHeight)
            right.name = "obstacle"
            right.zPosition = obstacleZ
            right.physicsBody = SKPhysicsBody(rectangleOf: right.size, center: CGPoint(x: right.size.width/2, y: 0))
            right.physicsBody?.isDynamic = false
            right.physicsBody?.usesPreciseCollisionDetection = true
            right.physicsBody?.categoryBitMask = PhysicsCategory.obstacle
            right.physicsBody?.contactTestBitMask = PhysicsCategory.player
            right.physicsBody?.collisionBitMask = PhysicsCategory.none
            addChild(right)

            moveObstacleUp(node: right, height: rowHeight)
        }

        // Optional: Add small pillars (walls) to increase variety
        if Bool.random() && self.size.width > 200 {
            let pillarWidth: CGFloat = 20
            let pillarHeight: CGFloat = CGFloat.random(in: 40...140)
            let pillarX = CGFloat.random(in: 0...(self.size.width - pillarWidth))
            let pillar = SKSpriteNode(color: .brown, size: CGSize(width: pillarWidth, height: pillarHeight))
            pillar.anchorPoint = CGPoint(x: 0, y: 0)
            pillar.position = CGPoint(x: pillarX, y: -pillarHeight)
            pillar.name = "obstacle"
            pillar.zPosition = obstacleZ
            pillar.physicsBody = SKPhysicsBody(rectangleOf: pillar.size, center: CGPoint(x: pillar.size.width/2, y: pillar.size.height/2))
            pillar.physicsBody?.isDynamic = false
            pillar.physicsBody?.usesPreciseCollisionDetection = true
            pillar.physicsBody?.categoryBitMask = PhysicsCategory.obstacle
            pillar.physicsBody?.contactTestBitMask = PhysicsCategory.player
            pillar.physicsBody?.collisionBitMask = PhysicsCategory.none
            addChild(pillar)

            moveObstacleUp(node: pillar, height: pillarHeight)
        }
    }

    private func moveObstacleUp(node: SKNode, height: CGFloat) {
        // start position is current node.position (we placed it just below screen), move it up past the top
        let distance = self.size.height + height + 200
        let move = SKAction.moveBy(x: 0, y: distance, duration: scrollDuration)
        let remove = SKAction.removeFromParent()
        node.run(SKAction.sequence([move, remove]))
    }

    // MARK: - Swipes / Touches
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let t = touches.first {
            touchStartPoint = t.location(in: self)
            touchStartTime = t.timestamp
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // If game over overlay is visible, check if the OK button was tapped
        if let overlay = gameOverNode, let t = touches.first {
            let loc = t.location(in: self)
            let nodesAt = nodes(at: loc)
            for node in nodesAt {
                if node.name == "gameOverButton" || node.name == "gameOverButtonLabel" {
                    restartFromGameOver()
                    touchStartPoint = nil
                    touchStartTime = nil
                    return
                }
            }
            // ignore other touches while game over
            touchStartPoint = nil
            touchStartTime = nil
            return
        }

        guard let start = touchStartPoint, let startTime = touchStartTime, let t = touches.first, let p = player else { return }
        let end = t.location(in: self)
        let dt = t.timestamp - startTime
        let dx = end.x - start.x
        let dy = end.y - start.y

        let distance = hypot(dx, dy)
        let minDistance: CGFloat = 30
        let maxTime: TimeInterval = 0.6

        if distance < minDistance || dt > maxTime {
            // treat as tap: optionally, move player horizontally to tap x
            let targetX = max(0 + p.size.width/2, min(self.size.width - p.size.width/2, end.x))
            let duration: TimeInterval = 0.15
            // Use physics body velocity for the move so physics engine will detect contacts reliably
            if let body = p.physicsBody {
                let dx = targetX - p.position.x
                let vx = dx / CGFloat(duration)
                body.velocity = CGVector(dx: vx, dy: 0)
                // schedule a stop after duration to snap to exact position
                run(SKAction.sequence([
                    SKAction.wait(forDuration: duration),
                    SKAction.run { [weak self] in
                        guard let self = self else { return }
                        body.velocity = .zero
                        p.position.x = targetX
                    }
                ]))
            } else {
                let move = SKAction.moveTo(x: targetX, duration: duration)
                p.run(move)
            }
        } else {
            // determine main direction
            if abs(dy) > abs(dx) {
                // vertical swipe
                setOrientation(vertical: true)
            } else {
                // horizontal swipe
                setOrientation(vertical: false)
            }
        }

        touchStartPoint = nil
        touchStartTime = nil
    }

    // Change orientation of the player
    private func setOrientation(vertical: Bool) {
        guard vertical != isVertical else { return }
        isVertical = vertical

        let newSize = vertical ? CGSize(width: 24, height: 60) : CGSize(width: 60, height: 24)
        let rotate = SKAction.rotate(toAngle: vertical ? CGFloat.pi/2 : 0, duration: 0.12, shortestUnitArc: true)
        let resize = SKAction.customAction(withDuration: 0.12) { [weak self] _, _ in
            guard let s = self else { return }
            // animate size by replacing texture/color node size; preserve position
            guard let p = s.player else { return }
            p.size = newSize
            // update physics body
            p.physicsBody = SKPhysicsBody(rectangleOf: p.size)
            // preserve dynamic behavior so contacts fire
            p.physicsBody?.isDynamic = true
            p.physicsBody?.affectedByGravity = false
            p.physicsBody?.allowsRotation = false
            p.physicsBody?.usesPreciseCollisionDetection = true
            p.physicsBody?.categoryBitMask = PhysicsCategory.player
            p.physicsBody?.contactTestBitMask = PhysicsCategory.obstacle
            p.physicsBody?.collisionBitMask = PhysicsCategory.none
        }
        player?.run(SKAction.group([rotate, resize]))
    }

    // MARK: - Collisions
    func didBegin(_ contact: SKPhysicsContact) {
        debugPrint("Collision!")
        var other: SKPhysicsBody
        if contact.bodyA.categoryBitMask == PhysicsCategory.player {
            other = contact.bodyB
        } else if contact.bodyB.categoryBitMask == PhysicsCategory.player {
            other = contact.bodyA
        } else {
            return
        }

        if other.categoryBitMask == PhysicsCategory.obstacle {
            // player hit obstacle -> reset
            if runningGame {
                // show game over overlay and stop the game
                showGameOver()
            }
        }
    }

    // MARK: - Update loop
    override func update(_ currentTime: TimeInterval) {
        // Optionally increase difficulty slowly
        // e.g., shorten spawnInterval or reduce scrollDuration over time
    }
}
