import AppKit

/// Viewfinder frame with two text lines. Template image: shape only, system tints it.
enum StatusBarIcon {
    static func image(pointSize: CGFloat) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { rect in
            let scale = rect.width / 18
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale)
            }
            NSColor.black.set()
            let frame = NSBezierPath(roundedRect: r(1.6, 2.2, 14.8, 13.6), xRadius: 2.4 * scale, yRadius: 2.4 * scale)
            frame.lineWidth = 1.7 * scale
            frame.stroke()
            let corner = 3.4 * scale
            let frameOrigin = NSPoint(x: 1.6 * scale, y: 2.2 * scale)
            let tl = NSBezierPath()
            tl.move(to: NSPoint(x: frameOrigin.x, y: frameOrigin.y + 6.0 * scale))
            tl.line(to: NSPoint(x: frameOrigin.x, y: frameOrigin.y + corner))
            tl.appendArc(withCenter: NSPoint(x: frameOrigin.x + corner, y: frameOrigin.y + corner), radius: corner, startAngle: 180, endAngle: 270)
            tl.lineWidth = 2.2 * scale
            tl.lineCapStyle = .round
            tl.stroke()
            let line1 = NSBezierPath(roundedRect: r(5.0, 9.6, 8.0, 1.9), xRadius: 0.9 * scale, yRadius: 0.9 * scale)
            line1.fill()
            let line2 = NSBezierPath(roundedRect: r(5.0, 6.6, 5.6, 1.9), xRadius: 0.9 * scale, yRadius: 0.9 * scale)
            line2.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
