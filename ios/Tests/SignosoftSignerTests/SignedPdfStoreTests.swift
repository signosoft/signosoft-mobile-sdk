import XCTest

@testable import SignosoftSigner

final class SignedPdfStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SignedPdfStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testWritesDecodedBytes() throws {
        let payload = Data("%PDF-1.7 signed".utf8)
        let store = SignedPdfStore(directory: directory)

        let url = try XCTUnwrap(store.write(
            base64: payload.base64EncodedString(),
            fileName: "report.pdf"
        ))

        XCTAssertEqual(url.lastPathComponent, "report.pdf")
        XCTAssertEqual(try Data(contentsOf: url), payload)
    }

    func testReturnsNilRatherThanThrowingOnBadInput() {
        let store = SignedPdfStore(directory: directory)

        XCTAssertNil(store.write(base64: nil, fileName: "a.pdf"))
        XCTAssertNil(store.write(base64: "", fileName: "a.pdf"))
        XCTAssertNil(store.write(base64: "not base64 at all!!", fileName: "a.pdf"))
        XCTAssertNil(store.write(base64: Data().base64EncodedString(), fileName: "a.pdf"))
    }

    func testRefusesDocumentsOverTheCeiling() {
        let store = SignedPdfStore(directory: directory, maximumBytes: 8)
        let tooBig = Data(repeating: 0x41, count: 64).base64EncodedString()

        XCTAssertNil(store.write(base64: tooBig, fileName: "big.pdf"))
    }

    func testFileNameCannotEscapeTheDirectory() throws {
        let store = SignedPdfStore(directory: directory)
        let payload = Data("x".utf8).base64EncodedString()

        let url = try XCTUnwrap(store.write(base64: payload, fileName: "../../evil.pdf"))

        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL,
                       directory.standardizedFileURL)
        XCTAssertEqual(url.lastPathComponent, "evil.pdf")
    }

    /// A signed medical document must not be readable while the device is
    /// locked. The simulator has no data protection at all, so there the
    /// attribute is absent and there is nothing to assert — only a device run
    /// proves this one.
    func testWritesWithCompleteFileProtectionOnIOS() throws {
        #if os(iOS)
        let store = SignedPdfStore(directory: directory)
        let url = try XCTUnwrap(store.write(
            base64: Data("%PDF-1.7 signed".utf8).base64EncodedString(),
            fileName: "protected.pdf"
        ))

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let protection = attributes[.protectionKey] as? FileProtectionType
        try XCTSkipIf(protection == nil, "this filesystem reports no protection class")
        XCTAssertEqual(protection, .complete)
        #else
        throw XCTSkip("file protection is an iOS API")
        #endif
    }

    func testSafeNameFallsBackForPathologicalNames() {
        XCTAssertEqual(SignedPdfStore.safeName(nil), "document.pdf")
        XCTAssertEqual(SignedPdfStore.safeName(""), "document.pdf")
        XCTAssertEqual(SignedPdfStore.safeName("/"), "document.pdf")
        XCTAssertEqual(SignedPdfStore.safeName(".."), "document.pdf")
        XCTAssertEqual(SignedPdfStore.safeName("a/b/../c.pdf"), "c.pdf")
        XCTAssertEqual(SignedPdfStore.safeName("plain.pdf"), "plain.pdf")
    }
}
