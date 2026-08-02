import AppKit
import Foundation

@main
@MainActor
struct ClipboardCaptureTests {
    static var passes = 0
    static var failures = 0

    static func main() async {
        await longTextIsPreserved()
        await unreasonableTextIsRejected()
        await whitespaceFallsThrough()
        await tiffBecomesPNG()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    static func longTextIsPreserved() async {
        let text = String(repeating: "日志与 code\n", count: 20_000)
        let capture = await ClipboardCapturePipeline().process(
            snapshot(text: text, source: "com.example.Editor", generation: 7))
        expect(
            capture
                == ClipboardCapture(
                    content: .text(text), sourceBundleID: "com.example.Editor", generation: 7),
            "text far beyond the old 32,000-character cap is preserved")
    }

    static func unreasonableTextIsRejected() async {
        let text = String(repeating: "x", count: ClipboardCapturePipeline.maxTextBytes + 1)
        let capture = await ClipboardCapturePipeline().process(snapshot(text: text))
        expect(capture == nil, "the byte cap bounds pathological pasteboard payloads")
    }

    static func whitespaceFallsThrough() async {
        let capture = await ClipboardCapturePipeline().process(snapshot(text: "  \n\t "))
        expect(capture == nil, "blank text is ignored")
    }

    static func tiffBecomesPNG() async {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation else {
            expect(false, "the TIFF fixture is available")
            return
        }
        let capture = await ClipboardCapturePipeline().process(
            PasteboardSnapshot(
                text: nil, imageData: tiff, imageIsPNG: false,
                sourceBundleID: nil, generation: 1))
        guard case .image(let png) = capture?.content else {
            expect(false, "TIFF capture produces image content")
            return
        }
        expect(
            png.starts(with: [0x89, 0x50, 0x4E, 0x47]),
            "TIFF normalization produces PNG bytes")
    }

    static func snapshot(
        text: String?, source: String? = nil, generation: UInt64 = 0
    ) -> PasteboardSnapshot {
        PasteboardSnapshot(
            text: text, imageData: nil, imageIsPNG: false,
            sourceBundleID: source, generation: generation)
    }

    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            passes += 1
        } else {
            print("FAIL: \(label)")
            failures += 1
        }
    }
}
