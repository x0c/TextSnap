import AppKit
import Testing
@testable import TextSnap

@Test @MainActor func statusIconLoadsQuoteSilhouetteAsTemplate() throws {
    let image = StatusBarIcon.image(pointSize: 18)
    #expect(image.isTemplate)
    #expect(image.isValid)
    #expect(image.size == NSSize(width: 18, height: 18))
    let data = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: data))
    #expect(bitmap.pixelsWide >= 18)
    #expect(bitmap.pixelsHigh >= 18)

    func alpha(_ x: Double, _ y: Double) throws -> CGFloat {
        let color = try #require(bitmap.colorAt(
            x: Int(x * Double(bitmap.pixelsWide)),
            y: Int(y * Double(bitmap.pixelsHigh))
        ))
        return color.alphaComponent
    }
    // Both lower bodies are solid, with a transparent gap and no app-icon ground.
    #expect(try alpha(0.25, 0.65) > 0.95)
    #expect(try alpha(0.75, 0.65) > 0.95)
    #expect(try alpha(0.50, 0.65) < 0.1)
    #expect(try alpha(0, 0) == 0)
}
