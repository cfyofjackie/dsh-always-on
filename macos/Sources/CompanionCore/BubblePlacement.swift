import Foundation
import CoreGraphics

public enum BubbleTailSide: Equatable, Sendable { case left, right, top, bottom }

public struct BubblePlacement: Sendable {
    public static let size = CGSize(width: 300, height: 176)
    public var frame: CGRect
    public var tailSide: BubbleTailSide
    /// Tail position along its edge, in the view's top-left coordinate system.
    public var tailOffset: CGFloat

    public static func beside(pet: CGRect, screen: CGRect) -> Self {
        let size = Self.size, gap: CGFloat = 8
        let faceY = pet.maxY - 72
        func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
            Swift.min(Swift.max(value, lower), Swift.max(lower, upper))
        }
        let left = pet.minX - size.width - gap, right = pet.maxX + gap
        let fitsLeft = left >= screen.minX, fitsRight = right + size.width <= screen.maxX
        var x: CGFloat, y: CGFloat, side: BubbleTailSide
        if fitsLeft || fitsRight {
            let useLeft = fitsLeft && (!fitsRight || pet.midX >= screen.midX)
            x = useLeft ? left : right; side = useLeft ? .right : .left
            y = clamp(faceY - size.height * 0.34, min: screen.minY, max: screen.maxY - size.height)
        } else if pet.maxY + gap + size.height <= screen.maxY {
            x = clamp(pet.midX - size.width / 2, min: screen.minX, max: screen.maxX - size.width)
            y = pet.maxY + gap; side = .bottom
        } else if pet.minY - gap - size.height >= screen.minY {
            x = clamp(pet.midX - size.width / 2, min: screen.minX, max: screen.maxX - size.width)
            y = pet.minY - gap - size.height; side = .top
        } else {
            let useLeft = pet.midX >= screen.midX
            x = clamp(useLeft ? left : right, min: screen.minX, max: screen.maxX - size.width)
            y = clamp(faceY - size.height * 0.34, min: screen.minY, max: screen.maxY - size.height)
            side = useLeft ? .right : .left
        }
        let vertical = side == .left || side == .right
        let offset = vertical ? size.height - (faceY - y) : pet.midX - x
        return Self(frame: CGRect(origin: CGPoint(x: x, y: y), size: size), tailSide: side,
                    tailOffset: clamp(offset, min: 38, max: (vertical ? size.height : size.width) - 38))
    }
}
