import CoreGraphics

/// Where the picker panel goes on screen (AppKit coordinates: origin bottom-left).
public enum PickerPlacement {
    static let inset: CGFloat = 8
    /// The panel's top-left corner sits this far left of and above the mouse.
    static let mouseOffset = CGPoint(x: 24, y: 12)

    /// Origin for a panel of `size` that opens at the mouse: slightly below-right of it, kept
    /// inside the screen's visible frame.
    public static func origin(mouse: CGPoint, size: CGSize, visible: CGRect) -> CGPoint {
        let origin = CGPoint(x: mouse.x - mouseOffset.x, y: mouse.y - size.height + mouseOffset.y)
        return clamped(CGRect(origin: origin, size: size), to: visible).origin
    }

    /// `frame` changed to `size` with its top edge in place, so rows grow downwards, and kept
    /// inside the visible frame.
    public static func resized(_ frame: CGRect, to size: CGSize, visible: CGRect) -> CGRect {
        clamped(CGRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height), to: visible)
    }

    /// Moved `inset` inside `visible`. A panel too big for the screen keeps its top-left corner
    /// on screen, where the links and the first targets are.
    static func clamped(_ frame: CGRect, to visible: CGRect) -> CGRect {
        var frame = frame
        frame.origin.x = max(min(frame.minX, visible.maxX - frame.width - inset), visible.minX + inset)
        frame.origin.y = min(max(frame.minY, visible.minY + inset), visible.maxY - frame.height - inset)
        return frame
    }
}
