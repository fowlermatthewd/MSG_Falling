//
//  GameScene.swift
//  falling
//
//  Created by Matthew fowler on 11/11/25.
//
// swipe down its like a grapple that pulls, tap to unhook
// swipe up to grapple up and swing

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

    // grapple
    private var isGrappling = false
    private var grappleLine: SKShapeNode?
    private var grappleTargetPoint: CGPoint?

    // post-grapple drift tracking
    private var lastGrappleDirection: CGVector = .zero
    private var lastGrappleSpeed: CGFloat = 0

    // spawning
    private var spawnTimer: Timer?
    private var spawnInterval: TimeInterval = 6.0
    private var scrollDuration: TimeInterval = 7.5
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
        // Create the composite PlayerNode (guy falling with clothes flapping)
        let size = CGSize(width: 60, height: 24) // visual size; starts horizontal
        let p = PlayerNode(size: size)
        // use scene size for placement so it fills full view
        p.position = CGPoint(x: self.size.width / 2.0, y: self.size.height - 120)
        p.zPosition = 10

        // Prefer the texture-based physics body created inside PlayerNode (so debug outlines match the sprite).
        // If PlayerNode didn't create one (missing texture), create a simple fallback rectangle body.
        if let body = p.physicsBody {
            // Configure masks on the existing body instead of replacing it (prevents replacing a tighter texture body with a box)
            body.isDynamic = true
            body.affectedByGravity = false
            body.allowsRotation = false
            body.usesPreciseCollisionDetection = true
            body.categoryBitMask = PhysicsCategory.player
            body.contactTestBitMask = PhysicsCategory.obstacle
            body.collisionBitMask = PhysicsCategory.none
        } else {
            let body = SKPhysicsBody(rectangleOf: p.size)
            body.isDynamic = true
            body.affectedByGravity = false
            body.allowsRotation = false
            body.usesPreciseCollisionDetection = true
            body.categoryBitMask = PhysicsCategory.player
            body.contactTestBitMask = PhysicsCategory.obstacle
            body.collisionBitMask = PhysicsCategory.none
            p.physicsBody = body
        }

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
        spawnInterval = 3.9
        scrollDuration = 9.5
        startSpawning()
    }

    private func stopGame() {
        runningGame = false
        stopSpawning()
    }

    private func resetGame(after delay: TimeInterval = 0.5) {
        stopGame()
        cancelGrapple()

        // small flash to indicate hit
        // alpha pulse so PlayerNode children are affected visually
        let flash = SKAction.sequence([
            SKAction.run { [weak self] in self?.player?.alpha = 0.25 },
            SKAction.wait(forDuration: 0.12),
            SKAction.run { [weak self] in self?.player?.alpha = 1.0 }
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
                self.setOrientation(angle: 0) // reset to horizontal start
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
        cancelGrapple()

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
        cancelGrapple()

        // clear obstacles
        removeAllObstacles()

        // reset player
        if let p = player {
            p.position = CGPoint(x: self.size.width / 2.0, y: self.size.height - 120)
        }
        setOrientation(angle: 0)

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

    // MARK: - Grapple helpers
    private func cancelGrapple() {
        isGrappling = false
        grappleTargetPoint = nil
        grappleLine?.removeFromParent()
        grappleLine = nil
        // stop any pull action on player
        player?.removeAction(forKey: "grapplePull")
        // apply horizontal drift based on the last grapple before clearing velocities
        applyPostGrappleDrift()
    }

    private func drawGrappleLine(from start: CGPoint, to end: CGPoint) {
        grappleLine?.removeFromParent()
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)
        let line = SKShapeNode(path: path)
        line.strokeColor = .cyan
        line.lineWidth = 3.0
        line.zPosition = 999
        addChild(line)
        grappleLine = line
    }

    // Visualize a grapple attempt even if it doesn't connect
    private func showGrappleMiss(from origin: CGPoint, direction: CGVector) {
        let maxDistance: CGFloat = 520.0
        let dirLen = sqrt(direction.dx * direction.dx + direction.dy * direction.dy)
        guard dirLen > 0.0001 else { return }
        let ux = direction.dx / dirLen
        let uy = direction.dy / dirLen
        let missEnd = CGPoint(x: origin.x + ux * maxDistance, y: origin.y + uy * maxDistance)

        let path = CGMutablePath()
        path.move(to: origin)
        path.addLine(to: missEnd)
        let line = SKShapeNode(path: path)
        line.strokeColor = .cyan
        line.lineWidth = 2.0
        line.alpha = 0.9
        line.zPosition = 998
        addChild(line)

        let fade = SKAction.sequence([
            SKAction.wait(forDuration: 0.05),
            SKAction.fadeOut(withDuration: 0.18),
            SKAction.removeFromParent()
        ])
        line.run(fade)
    }

    // Apply horizontal drift after a grapple completes, proportional to grapple speed and direction.
    private func applyPostGrappleDrift() {
        guard let p = player, let body = p.physicsBody else { return }
        // Only apply if we had a meaningful direction
        let mag = sqrt(lastGrappleDirection.dx * lastGrappleDirection.dx + lastGrappleDirection.dy * lastGrappleDirection.dy)
        guard mag > 0.0001 else { return }
        // Horizontal component of the unit direction
        let ux = lastGrappleDirection.dx / mag
        // Scale drift by speed and a tuning factor
        let driftScale: CGFloat = 0.65 // tuning factor for how strong the carry is
        let vx = ux * lastGrappleSpeed * driftScale

        // Apply horizontal velocity and re-enable damping so it decays naturally
        body.affectedByGravity = false
        body.allowsRotation = false
        // Preserve any vertical velocity (usually 0 after grapple), only set horizontal
        let currentVy = body.velocity.dy
        body.velocity = CGVector(dx: vx, dy: currentVy)

        // Temporarily increase linear damping to let drift decay smoothly
        let originalDamping = body.linearDamping
        body.linearDamping = max(originalDamping, 2.0)

        // After a short time, restore damping to original to avoid over-damping future moves
        let restore = SKAction.sequence([
            SKAction.wait(forDuration: 0.6),
            SKAction.run { [weak body] in
                body?.linearDamping = originalDamping
            }
        ])
        p.run(restore, withKey: "restoreDampingAfterDrift")

        // Clear last values so repeated taps don't compound unintentionally
        lastGrappleDirection = .zero
        lastGrappleSpeed = 0
    }

    // Cast a ray from the player in the swipe direction to find the first obstacle hit
    private func raycastToFirstObstacle(from origin: CGPoint, direction: CGVector, maxDistance: CGFloat = 2000) -> CGPoint? {
        // step along the direction and test nodes at points; SpriteKit doesn't expose a built-in raycast for static bodies
        let steps = 120
        let stepDistance = maxDistance / CGFloat(steps)
        let dirLen = sqrt(direction.dx * direction.dx + direction.dy * direction.dy)
        guard dirLen > 0.0001 else { return nil }
        let ux = direction.dx / dirLen
        let uy = direction.dy / dirLen
        for i in 1...steps {
            let d = CGFloat(i) * stepDistance
            let pt = CGPoint(x: origin.x + ux * d, y: origin.y + uy * d)
            // Bounds check to avoid sampling far outside scene
            if pt.x < -100 || pt.x > self.size.width + 100 || pt.y < -300 || pt.y > self.size.height + 300 { continue }
            let nodesHere = nodes(at: pt)
            if nodesHere.contains(where: { $0.name == "obstacle" }) {
                return pt
            }
        }
        return nil
    }

    private func beginGrapple(toward direction: CGVector) {
        guard !isGrappling, let p = player else { return }
        // Find first obstacle point in that direction
        let origin = p.position
        guard let hitPoint = raycastToFirstObstacle(from: origin, direction: direction) else {
            // Show a short miss line even if nothing is hit
            showGrappleMiss(from: origin, direction: direction)
            return
        }
        isGrappling = true
        grappleTargetPoint = hitPoint
        lastGrappleDirection = direction

        drawGrappleLine(from: origin, to: hitPoint)

        // Pull the player along the line to the target point
        let distance = hypot(hitPoint.x - origin.x, hitPoint.y - origin.y)
        let pullSpeed: CGFloat = 300.0 // points per second
        let duration = TimeInterval(distance / pullSpeed)
        lastGrappleSpeed = pullSpeed

        // Freeze rotation and clear velocities to make the pull feel tight
        if let body = p.physicsBody {
            body.velocity = .zero
            body.angularVelocity = 0
            body.allowsRotation = false
            body.affectedByGravity = false
            body.linearDamping = 0.5
        }

        // Action that updates the line while moving
        let moveAction = SKAction.move(to: hitPoint, duration: duration)
        moveAction.timingMode = .easeIn

        let updateLine = SKAction.customAction(withDuration: duration) { [weak self] _, _ in
            guard let self = self, let pl = self.player, let target = self.grappleTargetPoint else { return }
            self.drawGrappleLine(from: pl.position, to: target)
        }
        let group = SKAction.group([moveAction, updateLine])
        let finish = SKAction.run { [weak self] in
            guard let self = self else { return }
            self.cancelGrapple()
        }
        p.run(SKAction.sequence([group, finish]), withKey: "grapplePull")
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
        let minDistance: CGFloat = 20
        let maxTime: TimeInterval = 0.6

        if distance < minDistance || dt > maxTime {
            if isGrappling {
                // Tap while grappling cancels the grapple
                cancelGrapple()
                return
            }
            /*
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
             */

        } else {
            // Create a grapple toward the swipe direction
            let angle = atan2(dy, dx)
            let dir = CGVector(dx: cos(angle), dy: sin(angle))
            beginGrapple(toward: dir)
        }

        touchStartPoint = nil
        touchStartTime = nil
    }

    // Rotate player to a specific angle (radians) based on swipe direction. Keeps the player's size
    // constant and recreates the physics body after rotating so contacts remain accurate.
    private func setOrientation(angle: CGFloat) {
        // normalize angle to [-pi, pi] for shortest rotation
        let normalized = atan2(sin(angle), cos(angle))
        // If already roughly at the same angle, skip
        if let p = player {
            let current = atan2(sin(p.zRotation), cos(p.zRotation))
            let delta = abs(current - normalized)
            if delta < 0.02 { return }
        }

        // ensure physics body matches the player's current size and will be ready immediately
        if let p = player {
            let body = SKPhysicsBody(rectangleOf: p.size)
            body.isDynamic = true
            body.affectedByGravity = false
            body.allowsRotation = false
            body.usesPreciseCollisionDetection = true
            body.categoryBitMask = PhysicsCategory.player
            body.contactTestBitMask = PhysicsCategory.obstacle
            body.collisionBitMask = PhysicsCategory.none
            p.physicsBody = body
        }

        // rotate visually (physics body already assigned so contacts will fire during the animation)
        let rotate = SKAction.rotate(toAngle: normalized, duration: 0.12, shortestUnitArc: true)
        // update visual scale for near-vertical orientations
        if let pn = player as? PlayerNode {
            // consider vertical if within 30 degrees of straight up/down
            let deg = abs(normalized) * 180.0 / .pi
            let verticalThresholdDeg: CGFloat = 30.0
            let isNearVertical = abs(deg - 90.0) <= verticalThresholdDeg
            pn.setVisualScaleFor(vertical: isNearVertical)
        }
        player?.run(rotate)
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

