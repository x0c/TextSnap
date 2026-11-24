import CoreGraphics
import CoreText
import Foundation
@testable import TextSnap
import Testing

@Test func fileLoggerCreatesSecuredDirectoryAndRotates() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("TextSnapLogTests-\(UUID().uuidString)", isDirectory: true)
    let logsDir = root.appendingPathComponent("logs", isDirectory: true)
    defer { try? fm.removeItem(at: root) }

    let logger = TextSnapFileLogger(directory: logsDir, maxBytes: 220, maxBackups: 3)
    for index in 0..<12 {
        logger.append(level: "NOTICE", category: "capture", message: "capture event #\(index) payload=ok")
    }
    logger.flush()

    #expect(fm.fileExists(atPath: logger.activeFileURL.path))
    let dirPerms = try fm.attributesOfItem(atPath: logsDir.path)[.posixPermissions] as? NSNumber
    #expect(dirPerms?.intValue == 0o700)
    let filePerms = try fm.attributesOfItem(atPath: logger.activeFileURL.path)[.posixPermissions] as? NSNumber
    #expect(filePerms?.intValue == 0o600)

    let backup1 = logsDir.appendingPathComponent("textsnap.1.log")
    let backup2 = logsDir.appendingPathComponent("textsnap.2.log")
    let backup3 = logsDir.appendingPathComponent("textsnap.3.log")
    let backup4 = logsDir.appendingPathComponent("textsnap.4.log")
    #expect(fm.fileExists(atPath: backup1.path))
    #expect(fm.fileExists(atPath: backup2.path))
    #expect(fm.fileExists(atPath: backup3.path))
    #expect(!fm.fileExists(atPath: backup4.path))
}

@Test func textRecognizerHandlesMultiShapeSequenceWithoutE5RTFailure() throws {
    let cases: [(Int, Int, String, String)] = [
        (512, 256, "TextSnap 中文测试 12345", "TextSnap"),
        (856, 60, "TextSnap OCR 识别测试 2026", "识别"),
        (224, 160, "中文测试 Hello 123", "Hello"),
        (320, 64, "TextSnap Warmup 67890", "TextSnap"),
        (856, 60, "再次识别 中文 English 999", "English"),
    ]
    var warmedDevices: Set<String> = []
    for (index, item) in cases.enumerated() {
        let (width, height, inputText, token) = item
        let image = try makeSyntheticDisplayP3Image(width: width, height: height, text: inputText)
        let result = try TextRecognizer.recognizeWithDiagnostics(in: image)
        #expect(result.deviceName == "gpu" || result.deviceName == "cpu" || result.deviceName.hasPrefix("cpu+"))
        #expect(!result.text.isEmpty)
        #expect(result.text.contains(token) || result.text.contains("中文") || result.text.contains("TextSnap"))
        // Once a compute device has warmed up its model in-process, subsequent recognitions must stay fast.
        if warmedDevices.contains(result.deviceName) {
            #expect(result.durationMs < 5_000)
        }
        warmedDevices.insert(result.deviceName)
        if index == cases.count - 1 {
            #expect(result.durationMs < 5_000)
        }
    }
}

@Test func padForVisionPadsSmallCropsOnly() throws {
    let tiny = try makeSyntheticDisplayP3Image(width: 80, height: 28, text: "Hi")
    let paddedTiny = TextRecognizer.padForVisionIfNeeded(tiny)
    #expect(paddedTiny.width >= 320)
    #expect(paddedTiny.height >= 192)

    let strip = try makeSyntheticDisplayP3Image(width: 320, height: 64, text: "Test")
    let paddedStrip = TextRecognizer.padForVisionIfNeeded(strip)
    #expect(paddedStrip.width == 384)
    #expect(paddedStrip.height >= 192)

    let large = try makeSyntheticDisplayP3Image(width: 512, height: 256, text: "Large")
    let unpadded = TextRecognizer.padForVisionIfNeeded(large)
    #expect(unpadded.width == 512)
    #expect(unpadded.height == 256)
}

@Test func e5rtErrorMatcherIdentifiesVisionRuntimeErrors() {
    enum DummyError: Error {
        case e5rtError(String, Int)
        case cancelled
    }
    #expect(TextRecognizer.isE5RTError(DummyError.e5rtError("failed", 13)))
    #expect(!TextRecognizer.isE5RTError(DummyError.cancelled))
}

@Test func screenCaptureExitClassificationCoversEscAndErrors() {
    #expect(
        ScreenCapture.classifyExit(status: 0, fileExists: false, stderr: "", wasCancelled: false) == .cancelled
    )
    #expect(
        ScreenCapture.classifyExit(status: 1, fileExists: false, stderr: "", wasCancelled: false) == .cancelled
    )
    #expect(
        ScreenCapture.classifyExit(status: 0, fileExists: false, stderr: "cannot write file", wasCancelled: false)
            == .failed(status: 0, stderr: "cannot write file")
    )
    #expect(
        ScreenCapture.classifyExit(status: 2, fileExists: false, stderr: "", wasCancelled: false)
            == .failed(status: 2, stderr: "")
    )
    #expect(
        ScreenCapture.classifyExit(status: 15, fileExists: false, stderr: "terminated", wasCancelled: true)
            == .cancelled
    )
    #expect(
        ScreenCapture.classifyExit(status: 0, fileExists: true, stderr: "", wasCancelled: false) == nil
    )
}

@Test @MainActor func settingsIgnoresNegativeAndCorruptValuesSafely() throws {
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("TextSnapSettingsEdge-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: dir) }

    let file = dir.appendingPathComponent("settings.json")
    try Data(#"{"hotkeyKeyCode":-5,"hotkeyModifiers":-1,"hotkeyEnabled":true}"#.utf8).write(to: file)
    let negative = TextSnapSettings(directory: dir)
    #expect(negative.storedHotkey() == nil)
    #expect(negative.isMenuBarIconVisible)

    try Data("{corrupt json".utf8).write(to: file)
    let corrupt = TextSnapSettings(directory: dir)
    #expect(corrupt.storedHotkey() == nil)
    #expect(corrupt.hotkeyEnabled)
    #expect(corrupt.isMenuBarIconVisible)
}

@Test func hotkeyCarbonErrorNamesAreReadable() {
    #expect(HotkeyManager.carbonErrorName(for: -9878) == "eventHotKeyExistsErr")
    #expect(HotkeyManager.carbonErrorName(for: -9874) == "eventNotHandledErr")
    #expect(HotkeyManager.carbonErrorName(for: 0) == "noErr")
}

private func makeSyntheticDisplayP3Image(width: Int, height: Int, text: String) throws -> CGImage {
    guard let cs = CGColorSpace(name: CGColorSpace.displayP3),
          let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else {
        throw TextRecognizer.RecognizeError.imageUnreadable
    }
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, 24, nil)
    let attrs: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1),
    ]
    let str = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
    ctx.textPosition = CGPoint(x: 10, y: Double(height) / 2 - 10)
    CTLineDraw(CTLineCreateWithAttributedString(str), ctx)
    return ctx.makeImage()!
}
