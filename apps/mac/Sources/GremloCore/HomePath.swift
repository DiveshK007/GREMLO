import CoreGraphics

// The trip home (spec D §4): along the floor to the right wall, up it, along the top under the menu bar to the door
// in the notch. Pure geometry in screen points (origin bottom left), so the whole path can be checked: the sprite's
// rectangle stays inside the screen and never goes up into the menu bar band, where it can end up out of sight.
public struct HomePath: Equatable, Sendable {
    public let screen: CGRect        // NSScreen.frame
    public let visible: CGRect       // NSScreen.visibleFrame: below the menu bar, beside the Dock
    public let sprite: CGSize
    public let footPadding: CGFloat  // empty rows under the feet in the art

    public init(screen: CGRect, visible: CGRect, sprite: CGSize, footPadding: CGFloat) {
        self.screen = screen; self.visible = visible; self.sprite = sprite; self.footPadding = footPadding
    }

    /// Feet on the bottom edge (the empty rows under them may dip below it, never off the screen).
    public var floorY: CGFloat { max(visible.minY - footPadding, screen.minY) }
    public var leftX: CGFloat { visible.minX }
    /// Against the right wall.
    public var wallX: CGFloat { visible.maxX - sprite.width }
    /// Upside down under the menu bar: the sprite's top edge at the bottom of the band, not in it.
    public var ceilingY: CGFloat { visible.maxY - sprite.height }
    /// Under the door, kept on the top edge.
    public func doorX(doorCenterX: CGFloat) -> CGFloat { min(max(doorCenterX - sprite.width / 2, leftX), wallX) }
    /// A perched pet's walls are its window's edges, but never past the screen's.
    public func walls(perch: CGRect?) -> (left: CGFloat, right: CGFloat) {
        guard let p = perch else { return (leftX, wallX) }
        let right = min(p.maxX - sprite.width, wallX)
        return (min(max(p.minX, leftX), right), right)
    }

    /// The sprite at `origin` is fully on the screen and below the menu bar band.
    public func keepsInside(_ origin: CGPoint) -> Bool {
        let r = CGRect(origin: origin, size: sprite)
        return screen.insetBy(dx: -0.5, dy: -0.5).contains(r) && r.maxY <= visible.maxY + 0.5
    }

    /// Sprite origins along the whole trip from `startX` on the floor, every `step` points (for tests and the log).
    public func points(startX: CGFloat, doorCenterX: CGFloat, step: CGFloat = 4) -> [CGPoint] {
        func run(_ a: CGFloat, _ b: CGFloat) -> [CGFloat] {
            let n = max(1, Int((abs(b - a) / step).rounded(.up)))
            return (0...n).map { a + (b - a) * CGFloat($0) / CGFloat(n) }
        }
        let floor = run(min(startX, wallX), wallX).map { CGPoint(x: $0, y: floorY) }
        let climb = run(floorY, ceilingY).map { CGPoint(x: wallX, y: $0) }
        let top = run(wallX, doorX(doorCenterX: doorCenterX)).map { CGPoint(x: $0, y: ceilingY) }
        return floor + climb + top
    }
}
