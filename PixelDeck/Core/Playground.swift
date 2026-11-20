import Foundation

/// What the player is pressing.
struct PlayInput: Equatable, Sendable {
    var left = false
    var right = false
    var jump = false
}

/// Things that happened in a step, for sounds and haptics.
enum PlayEvent: Equatable, Sendable {
    case jump, coin, hurt, stomp, win
}

/// Pixel Playground: a small platformer played on a tile scene. Positions are in scene pixels
/// (y grows downwards). The rules: run and jump, collect every coin, don't touch water or
/// enemies (jumping on an enemy beats it), and reach the goal flag if the level has one.
struct PlaygroundGame: Sendable {
    enum Status: Equatable, Sendable { case playing, won }

    struct Enemy: Equatable, Sendable {
        var x: Double
        var y: Double
        var direction: Double
        var alive = true
    }

    // Tuned for 16-pixel tiles: a jump clears two tiles up and four across.
    static let moveSpeed = 72.0
    static let gravity = 560.0
    static let jumpSpeed = 215.0
    static let maxFall = 300.0
    static let enemySpeed = 26.0
    /// A jump pressed just after walking off an edge still counts.
    static let coyoteTime = 0.09
    static let enemySize = 12.0

    let scene: TileScene
    /// The hero's collision box, in pixels.
    let heroWidth: Double
    let heroHeight: Double

    private(set) var x: Double
    private(set) var y: Double
    private(set) var vx = 0.0
    private(set) var vy = 0.0
    private(set) var onGround = false
    private(set) var facingLeft = false
    private(set) var coinsLeft: [PixelPoint]
    private(set) var enemies: [Enemy]
    private(set) var elapsed = 0.0
    private(set) var status: Status = .playing
    private(set) var falls = 0
    /// Drained by the view after each step.
    var events: [PlayEvent] = []

    private var sinceGround = 0.0
    private var jumpHeld = false

    var coinTotal: Int { scene.coins.count }
    var coinsCollected: Int { coinTotal - coinsLeft.count }
    var isMoving: Bool { abs(vx) > 1 }

    init(scene: TileScene, heroWidth: Int = 12, heroHeight: Int = 14) {
        self.scene = scene
        // Never wider or taller than a tile gap the level was built around.
        self.heroWidth = Double(min(max(heroWidth, 6), 14))
        self.heroHeight = Double(min(max(heroHeight, 6), 30))
        coinsLeft = scene.coins
        enemies = []
        x = 0
        y = 0
        respawn()
        enemies = scene.enemies.map { p in
            let t = Double(TileScene.tileSize)
            return Enemy(x: Double(p.x) * t + (t - PlaygroundGame.enemySize) / 2, y: Double(p.y + 1) * t - PlaygroundGame.enemySize, direction: -1)
        }
    }

    private mutating func respawn() {
        let t = Double(TileScene.tileSize)
        x = Double(scene.start.x) * t + (t - heroWidth) / 2
        y = Double(scene.start.y + 1) * t - heroHeight
        vx = 0
        vy = 0
        onGround = false
    }

    /// Advances the game by `dt` seconds (in small fixed steps, so fast frames and slow frames
    /// play the same).
    mutating func step(_ dt: Double, input: PlayInput) {
        guard status == .playing, dt > 0 else { return }
        var left = min(dt, 0.1)
        let h = 1.0 / 120
        while left > 1e-9 {
            let d = min(h, left)
            tick(d, input: input)
            left -= d
            if status != .playing { break }
        }
    }

    private mutating func tick(_ dt: Double, input: PlayInput) {
        elapsed += dt
        // Run.
        vx = (input.right ? PlaygroundGame.moveSpeed : 0) - (input.left ? PlaygroundGame.moveSpeed : 0)
        if vx < 0 { facingLeft = true } else if vx > 0 { facingLeft = false }
        // Jump on a fresh press, from the ground (or just after leaving it).
        sinceGround = onGround ? 0 : sinceGround + dt
        if input.jump && !jumpHeld && sinceGround <= PlaygroundGame.coyoteTime {
            vy = -PlaygroundGame.jumpSpeed
            onGround = false
            sinceGround = PlaygroundGame.coyoteTime + 1
            events.append(.jump)
        }
        // Letting go early makes a shorter hop.
        if !input.jump && vy < -80 { vy = -80 }
        jumpHeld = input.jump
        vy = min(vy + PlaygroundGame.gravity * dt, PlaygroundGame.maxFall)

        moveHorizontally(vx * dt)
        moveVertically(vy * dt)

        // Off the bottom, or into water.
        if y > Double(scene.pixelHeight) + 32 || touchesHazard() {
            hurt()
            return
        }
        collectCoins()
        stepEnemies(dt)
        checkWin()
    }

    private func tiles(_ lo: Double, _ hi: Double) -> ClosedRange<Int> {
        let t = Double(TileScene.tileSize)
        let a = Int((lo / t).rounded(.down)), b = Int(((hi - 0.001) / t).rounded(.down))
        return a...max(a, b)
    }

    private func blocked(x: Double, y: Double) -> Bool {
        for ty in tiles(y, y + heroHeight) {
            for tx in tiles(x, x + heroWidth) where scene.isSolid(tx, ty) { return true }
        }
        return false
    }

    private mutating func moveHorizontally(_ dx: Double) {
        guard dx != 0 else { return }
        var nx = x + dx
        // The level's left and right edges are walls.
        nx = min(max(nx, 0), Double(scene.pixelWidth) - heroWidth)
        if blocked(x: nx, y: y) {
            let t = Double(TileScene.tileSize)
            if dx > 0 {
                nx = (((nx + heroWidth) / t).rounded(.down)) * t - heroWidth
            } else {
                nx = ((nx / t).rounded(.down) + 1) * t
            }
            if blocked(x: nx, y: y) { nx = x }
        }
        x = nx
    }

    private mutating func moveVertically(_ dy: Double) {
        guard dy != 0 else { return }
        var ny = y + dy
        onGround = false
        if blocked(x: x, y: ny) {
            let t = Double(TileScene.tileSize)
            if dy > 0 {
                ny = (((ny + heroHeight) / t).rounded(.down)) * t - heroHeight
                onGround = true
            } else {
                ny = ((ny / t).rounded(.down) + 1) * t
            }
            vy = 0
            if blocked(x: x, y: ny) { ny = y }
        }
        y = ny
    }

    private func touchesHazard() -> Bool {
        // The middle of the hero, so skimming the edge of a pond is forgiven.
        let inset = 3.0
        for ty in tiles(y + inset, y + heroHeight) {
            for tx in tiles(x + inset, x + heroWidth - inset) where scene.isHazard(tx, ty) { return true }
        }
        return false
    }

    private mutating func hurt() {
        falls += 1
        events.append(.hurt)
        respawn()
    }

    private mutating func collectCoins() {
        let t = Double(TileScene.tileSize)
        let before = coinsLeft.count
        coinsLeft.removeAll { c in
            // A coin sits in the middle of its cell.
            let cx = Double(c.x) * t + 3, cy = Double(c.y) * t + 3, size = t - 6
            return x < cx + size && x + heroWidth > cx && y < cy + size && y + heroHeight > cy
        }
        for _ in 0..<(before - coinsLeft.count) { events.append(.coin) }
    }

    private mutating func stepEnemies(_ dt: Double) {
        let t = Double(TileScene.tileSize), size = PlaygroundGame.enemySize
        for i in enemies.indices where enemies[i].alive {
            var e = enemies[i]
            let nx = e.x + e.direction * PlaygroundGame.enemySpeed * dt
            // Turn round at walls, at the level's edges, and where the floor ends.
            let ahead = e.direction > 0 ? nx + size : nx
            let tx = Int((ahead / t).rounded(.down)), ty = Int(((e.y + size / 2) / t).rounded(.down))
            let floorY = Int(((e.y + size + 1) / t).rounded(.down))
            if nx < 0 || nx + size > Double(scene.pixelWidth) || scene.isSolid(tx, ty) || !scene.isSolid(tx, floorY) {
                e.direction = -e.direction
            } else {
                e.x = nx
            }
            // Touching: landing on it from above beats it; anything else hurts.
            if x < e.x + size && x + heroWidth > e.x && y < e.y + size && y + heroHeight > e.y {
                if vy > 40 && y + heroHeight - e.y < size * 0.75 {
                    e.alive = false
                    vy = -PlaygroundGame.jumpSpeed * 0.6
                    events.append(.stomp)
                } else {
                    enemies[i] = e
                    hurt()
                    return
                }
            }
            enemies[i] = e
        }
    }

    private mutating func checkWin() {
        // A level with nothing to collect and no flag is free play: it never ends.
        guard coinsLeft.isEmpty, coinTotal > 0 || scene.goal != nil else { return }
        if let g = scene.goal {
            let t = Double(TileScene.tileSize)
            let gx = Double(g.x) * t, gy = Double(g.y) * t
            guard x < gx + t && x + heroWidth > gx && y < gy + t && y + heroHeight > gy else { return }
        }
        status = .won
        events.append(.win)
    }
}
