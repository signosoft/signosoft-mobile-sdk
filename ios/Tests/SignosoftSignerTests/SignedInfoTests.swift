import XCTest

@testable import SignosoftSigner

final class SignedInfoTests: XCTestCase {
    /// Writing PDFs is out of scope here — a ceiling of zero refuses every
    /// document, so these tests never touch the file system.
    private let noPdfStore = SignedPdfStore(maximumBytes: 0)

    func testReadsEveryField() {
        let info = SignedInfo(bridgeData: [
            "result": "success",
            "document": "12345",
            "documentToken": "doc-token",
            "lang": "cs",
            "signaturesSigned": 2,
            "signaturesTotal": 2,
            "lastSignerFirstName": "Jan",
            "lastSignerLastName": "Novák",
            "lastSignerEmail": "jan@example.com",
        ], pdfStore: noPdfStore)

        XCTAssertEqual(info.result, "success")
        XCTAssertEqual(info.document, "12345")
        XCTAssertEqual(info.documentToken, "doc-token")
        XCTAssertEqual(info.lang, "cs")
        XCTAssertEqual(info.signaturesSigned, 2)
        XCTAssertEqual(info.signaturesTotal, 2)
        XCTAssertEqual(info.lastSignerFirstName, "Jan")
        XCTAssertEqual(info.lastSignerLastName, "Novák")
        XCTAssertEqual(info.lastSignerEmail, "jan@example.com")
    }

    func testDefaultsMissingAndMistypedFields() {
        let info = SignedInfo(bridgeData: [
            "documentToken": 99,
            "signaturesSigned": "two",
        ], pdfStore: noPdfStore)

        XCTAssertEqual(info.documentToken, "")
        XCTAssertEqual(info.signaturesSigned, 0)
        XCTAssertEqual(info.lastSignerEmail, "")
    }

    func testHandlesNilData() {
        let info = SignedInfo(bridgeData: nil, pdfStore: noPdfStore)

        XCTAssertEqual(info.result, "")
        XCTAssertNil(info.downloadUrl)
        XCTAssertNil(info.signedPdfFileURL)
    }

    func testDownloadUrlIsNilUnlessItIsUsable() {
        func url(_ value: Any?) -> URL? {
            SignedInfo(
                bridgeData: value.map { ["downloadUrl": $0] },
                pdfStore: noPdfStore
            ).downloadUrl
        }

        XCTAssertNil(url(nil))
        XCTAssertNil(url(""))
        XCTAssertNil(url("/relative/path.pdf"))
        XCTAssertNil(url(1234))
        XCTAssertEqual(url("https://example.com/a.pdf"), URL(string: "https://example.com/a.pdf"))
    }
}
