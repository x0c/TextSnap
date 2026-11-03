import AppKit

@MainActor
enum StatusBarIcon {
    static func image(pointSize: CGFloat) -> NSImage {
        let image = NSImage(resource: .menuBarIcon)
        image.size = NSSize(width: pointSize, height: pointSize)
        image.isTemplate = true
        return image
    }
}
