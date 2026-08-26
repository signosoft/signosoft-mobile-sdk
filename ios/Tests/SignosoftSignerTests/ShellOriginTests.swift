import XCTest

@testable import SignosoftSigner

/// What the SDK will and will not point a ceremony at, and what counts as the
/// same origin. Runs under plain `swift test`: the type is free of WebKit and
/// UIKit precisely so this file is reachable on macOS.
final class ShellOriginTests: XCTestCase {

    // MARK: - isUsable

    func testAcceptsHttpsOrigins() {
        XCTAssertTrue(ShellOrigin.isUsable(URL(string: "https://www.signosoft.com/mobilesdk/")!))
        XCTAssertTrue(ShellOrigin.isUsable(URL(string: "https://tenant.example.com")!))
        XCTAssertTrue(ShellOrigin.isUsable(URL(string: "https://example.com:8443/shell")!))
        XCTAssertTrue(ShellOrigin.isUsable(URL(string: "HTTPS://WWW.Signosoft.COM/")!))
    }

    /// The old behaviour: `URL(string:)` accepts these, so the ceremony opened,
    /// failed to load, and reported `loadFailed` seconds later.
    func testRejectsInputWithNoSchemeOrNoHost() {
        XCTAssertFalse(ShellOrigin.isUsable(URL(string: "notaurl")!))
        XCTAssertFalse(ShellOrigin.isUsable(URL(string: "/just/a/path")!))
        XCTAssertFalse(ShellOrigin.isUsable(URL(string: "file:///tmp/shell.html")!))
    }

    /// A public cleartext origin would put the bioid on the wire, and could not
    /// complete a signature anyway — no secure context, no WebCrypto.
    func testRejectsPublicCleartextButAllowsLoopback() {
        XCTAssertFalse(ShellOrigin.isUsable(URL(string: "http://shell.example.com")!))
        XCTAssertFalse(ShellOrigin.isUsable(URL(string: "http://192.168.1.20:4200")!))

        XCTAssertTrue(ShellOrigin.isUsable(URL(string: "http://localhost:4200")!))
        XCTAssertTrue(ShellOrigin.isUsable(URL(string: "http://127.0.0.1:4200")!))
        XCTAssertTrue(ShellOrigin.isUsable(URL(string: "http://10.0.2.2:4200")!))
        XCTAssertTrue(ShellOrigin.isUsable(URL(string: "http://shell.localhost:4200")!))
    }

    // MARK: - matches

    func testMatchesIsCaseInsensitiveAndPortAware() throws {
        let shell = try XCTUnwrap(ShellOrigin(url: URL(string: "https://www.signosoft.com/mobilesdk/")!))

        XCTAssertTrue(shell.matches(url: URL(string: "https://WWW.Signosoft.COM/other/page")!))
        // 443 is https's default, however it is spelled.
        XCTAssertTrue(shell.matches(url: URL(string: "https://www.signosoft.com:443/x")!))

        XCTAssertFalse(shell.matches(url: URL(string: "https://evil.example.com/")!))
        XCTAssertFalse(shell.matches(url: URL(string: "http://www.signosoft.com/")!))
        XCTAssertFalse(shell.matches(url: URL(string: "https://www.signosoft.com:8443/")!))
        // A subdomain is a different origin.
        XCTAssertFalse(shell.matches(url: URL(string: "https://a.www.signosoft.com/")!))
        XCTAssertFalse(shell.matches(url: nil))
    }

    /// `WKSecurityOrigin` reports 0 for a scheme's default port; `URL` reports
    /// nil. They have to compare equal.
    func testDefaultPortFromWebKitMatchesDefaultPortFromURL() throws {
        let shell = try XCTUnwrap(ShellOrigin(url: URL(string: "https://www.signosoft.com/")!))
        let fromWebKit = ShellOrigin(scheme: "https", host: "www.signosoft.com", port: 0)

        XCTAssertTrue(shell.matches(fromWebKit))
    }

    func testExplicitPortIsCompared() throws {
        let shell = try XCTUnwrap(ShellOrigin(url: URL(string: "http://localhost:4200/")!))

        XCTAssertTrue(shell.matches(ShellOrigin(scheme: "http", host: "localhost", port: 4200)))
        XCTAssertFalse(shell.matches(ShellOrigin(scheme: "http", host: "localhost", port: 4201)))
        // Default-port normalisation must not swallow an explicit mismatch.
        XCTAssertFalse(shell.matches(ShellOrigin(scheme: "http", host: "localhost", port: 0)))
    }
}
