import XCTest

@testable import SignosoftSigner

final class BridgeMessageTests: XCTestCase {
    func testParsesDictionaryBody() {
        let message = BridgeMessage(body: ["event": "ready"] as [String: Any])

        XCTAssertEqual(message?.event, "ready")
        XCTAssertNil(message?.data)
    }

    func testParsesJsonStringBody() {
        let message = BridgeMessage(body: #"{"event":"error","data":{"message":"nope"}}"#)

        XCTAssertEqual(message?.event, "error")
        XCTAssertEqual(message?.data?["message"] as? String, "nope")
    }

    func testRejectsBodyWithoutEvent() {
        XCTAssertNil(BridgeMessage(body: ["data": ["x": 1]] as [String: Any]))
    }

    func testRejectsJunkBody() {
        XCTAssertNil(BridgeMessage(body: 42))
        XCTAssertNil(BridgeMessage(body: "not json"))
    }

    func testDiagnosticDataReplacesPdfBytesWithTheirLength() {
        let message = BridgeMessage(body: [
            "event": "signed",
            "data": ["documentToken": "tok", "pdfBase64": "AAAA"],
        ] as [String: Any])

        let diagnostic = message?.diagnosticData
        XCTAssertNil(diagnostic?["pdfBase64"])
        XCTAssertEqual(diagnostic?["pdfBase64Length"] as? Int, 4)
        XCTAssertEqual(diagnostic?["documentToken"] as? String, "tok")
    }
}
