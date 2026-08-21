import XCTest

/// Pasteboard snapshot normalization: text limits, image transcoding to PNG, and file-URL
/// resolution ordering.
final class ClipboardCapturePipelineTests: XCTestCase {
    private func makeSnapshot(
        text: String? = nil, imageData: Data? = nil, imageIsPNG: Bool = false,
        fileURLs: [URL] = []
    ) -> PasteboardSnapshot {
        PasteboardSnapshot(
            text: text, imageData: imageData, imageIsPNG: imageIsPNG, fileURLs: fileURLs,
            sourceBundleID: "com.test", generation: 0)
    }

    func testPlainTextCapture() async throws {
        let pipeline = ClipboardCapturePipeline()
        let capture = await pipeline.process(makeSnapshot(text: "hello"))
        XCTAssertEqual(capture?.content, .text("hello"))
        XCTAssertEqual(capture?.sourceBundleID, "com.test")
        XCTAssertEqual(capture?.generation, 0)
    }

    func testWhitespaceOnlyTextIsRejected() async throws {
        let pipeline = ClipboardCapturePipeline()
        let capture = await pipeline.process(makeSnapshot(text: "   \n\t  "))
        XCTAssertNil(capture)
    }

    func testOversizedTextIsRejected() async throws {
        let pipeline = ClipboardCapturePipeline()
        let oversized = String(repeating: "a", count: ClipboardCapturePipeline.maxTextBytes + 1)
        let capture = await pipeline.process(makeSnapshot(text: oversized))
        XCTAssertNil(capture)
    }

    func testTextAtLimitIsAccepted() async throws {
        let pipeline = ClipboardCapturePipeline()
        let atLimit = String(repeating: "a", count: ClipboardCapturePipeline.maxTextBytes)
        let capture = await pipeline.process(makeSnapshot(text: atLimit))
        XCTAssertEqual(capture?.content, .text(atLimit))
    }

    func testNonPNGImageDataIsTranscodedToPNG() async throws {
        let pipeline = ClipboardCapturePipeline()
        let jpeg = TestSupport.makeJPEGData()
        let capture = await pipeline.process(
            makeSnapshot(imageData: jpeg, imageIsPNG: false))

        guard case .image(let png)? = capture?.content else {
            return XCTFail("Expected an image capture")
        }
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "Payload must be PNG")
    }

    func testPNGImageDataIsPassedThrough() async throws {
        let pipeline = ClipboardCapturePipeline()
        let png = TestSupport.makePNGData()
        let capture = await pipeline.process(makeSnapshot(imageData: png, imageIsPNG: true))
        XCTAssertEqual(capture?.content, .image(png))
    }

    func testImageFileURLIsResolvedBeforeFilenameText() async throws {
        let directory = TestSupport.makeTemporaryDirectory("pipeline-file")
        defer { TestSupport.removeTemporaryDirectory(directory) }

        let imageURL = directory.appendingPathComponent("photo.jpg")
        try TestSupport.makeJPEGData().write(to: imageURL)

        let pipeline = ClipboardCapturePipeline()
        let capture = await pipeline.process(
            makeSnapshot(text: imageURL.lastPathComponent, fileURLs: [imageURL]))

        guard case .image(let png)? = capture?.content else {
            return XCTFail("Expected the image file to win over the filename text")
        }
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    func testNonImageFileURLFallsThroughToText() async throws {
        let directory = TestSupport.makeTemporaryDirectory("pipeline-txt")
        defer { TestSupport.removeTemporaryDirectory(directory) }

        let textURL = directory.appendingPathComponent("notes.txt")
        try Data("plain".utf8).write(to: textURL)

        let pipeline = ClipboardCapturePipeline()
        let capture = await pipeline.process(
            makeSnapshot(text: textURL.lastPathComponent, fileURLs: [textURL]))
        XCTAssertEqual(capture?.content, .text("notes.txt"))
    }

    func testCorruptImageDataIsRejected() async throws {
        let pipeline = ClipboardCapturePipeline()
        let capture = await pipeline.process(
            makeSnapshot(imageData: Data([0x00, 0x01, 0x02]), imageIsPNG: false))
        XCTAssertNil(capture)
    }
}
