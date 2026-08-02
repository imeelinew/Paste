import AppKit
import Foundation

struct PasteboardSnapshot: Sendable {
    let text: String?
    let imageData: Data?
    let imageIsPNG: Bool
    let sourceBundleID: String?
    let generation: UInt64
}

enum CapturedClipboardContent: Sendable, Equatable {
    case text(String)
    case image(Data)
}

struct ClipboardCapture: Sendable, Equatable {
    let content: CapturedClipboardContent
    let sourceBundleID: String?
    let generation: UInt64
}

/// Serial normalization boundary for pasteboard snapshots. Conversion order now matches observed
/// change order, while large text accounting and TIFF decoding stay off the main actor.
actor ClipboardCapturePipeline {
    static let maxTextBytes = 8 * 1024 * 1024

    func process(_ snapshot: PasteboardSnapshot) -> ClipboardCapture? {
        if let text = snapshot.text,
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            text.utf8.count <= Self.maxTextBytes
        {
            return ClipboardCapture(
                content: .text(text), sourceBundleID: snapshot.sourceBundleID,
                generation: snapshot.generation)
        }
        guard let data = snapshot.imageData else { return nil }
        let png =
            snapshot.imageIsPNG
            ? data : NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
        guard let png else { return nil }
        return ClipboardCapture(
            content: .image(png), sourceBundleID: snapshot.sourceBundleID,
            generation: snapshot.generation)
    }
}
