#if canImport(UIKit)
import UIKit
import WebKit
import XCTest

@testable import SignosoftSigner

/// Behaviour of the view controller as a host observes it: which
/// `SignosoftSignerResult` arrives, and that exactly one arrives.
///
/// iOS Simulator only — the whole view controller is behind
/// `#if canImport(UIKit)`, so `swift test` on macOS compiles this file away.
/// Run it with the `xcodebuild test` invocation in `.github/workflows/ci.yml`.
///
/// No test here reaches the network. Every controller is pointed at a loopback
/// socket that accepts nothing and answers nothing, so the page load hangs at
/// the TLS handshake for as long as the test lives. That gives each test a
/// controller in the state a real one is in before `ready` arrives, and it means
/// nothing but the test itself can deliver a result.
final class SignosoftSignerViewControllerTests: XCTestCase {
    private var server: HangingLoopbackServer!
    private var controller: SignosoftSignerViewController!
    /// Only the teardown tests need a host container; the rest drive the
    /// controller directly.
    private var host: UIViewController?
    /// Every result the host was handed, in order. The count is the assertion
    /// that matters as much as the case: a result must arrive exactly once.
    private var results: [SignosoftSignerResult] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        server = try HangingLoopbackServer()
        results = []
    }

    override func tearDown() {
        host = nil
        controller = nil
        server?.close()
        server = nil
        super.tearDown()
    }

    // MARK: - The six

    func test_a_signed_bridge_message_produces_a_signed_result() throws {
        let controller = startController()

        send("signed", data: [
            "result": "success",
            "document": "12345",
            "documentToken": "doc-token",
            "signaturesSigned": 2,
            "signaturesTotal": 2,
        ], to: controller)

        XCTAssertEqual(results.count, 1)
        guard case .signed(let info) = try XCTUnwrap(results.first) else {
            return XCTFail("expected .signed, got \(String(describing: results.first))")
        }
        XCTAssertEqual(info.documentToken, "doc-token")
        XCTAssertEqual(info.signaturesSigned, 2)
    }

    func test_an_unrecognised_bridge_event_is_ignored() throws {
        let controller = startController()
        var seenEvents: [String] = []
        controller.onEvent = { event, _ in seenEvents.append(event) }

        send("somethingTheShellInventedLater", to: controller)

        XCTAssertTrue(results.isEmpty, "an unknown event must not end the session")
        XCTAssertEqual(seenEvents, ["somethingTheShellInventedLater"],
                       "it is ignored, not swallowed: diagnostics still see it")

        // Ignored and still live: the session can still be finished afterwards.
        send("cancelled", to: controller)
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(isCancelled(results.first), "expected .cancelled")
    }

    func test_a_main_frame_response_of_4xx_or_worse_reports_loadFailed() throws {
        let controller = startController()

        let policy = respond(statusCode: 404, isForMainFrame: true, to: controller)

        XCTAssertEqual(policy, .allow, "the SDK must not cancel the navigation it reports on")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(try errorCode(of: results.first), .loadFailed)
    }

    func test_the_watchdog_reports_loadTimeout_when_ready_never_arrives() throws {
        let arrived = expectation(description: "a result reaches the host")
        _ = startController(loadTimeout: 0.5) { _ in arrived.fulfill() }

        wait(for: [arrived], timeout: 5)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(try errorCode(of: results.first), .loadTimeout)
    }

    func test_tapping_close_reports_cancelled() throws {
        let controller = startController()

        try tapClose(on: controller)

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(isCancelled(results.first), "expected .cancelled")
    }

    func test_a_second_bridge_event_after_a_result_is_dropped() throws {
        let controller = startController()

        send("signed", data: ["documentToken": "first"], to: controller)
        send("cancelled", to: controller)
        send("error", data: ["message": "too late"], to: controller)
        send("rejected", to: controller)

        XCTAssertEqual(results.count, 1, "a session reports exactly once")
        guard case .signed(let info) = try XCTUnwrap(results.first) else {
            return XCTFail("the first result must be the one that stands")
        }
        XCTAssertEqual(info.documentToken, "first")
    }

    // MARK: - The rest of the same surface

    func test_ready_stops_the_watchdog() {
        let controller = startController(loadTimeout: 0.3)

        send("ready", to: controller)
        // Outlive the watchdog: if `ready` did not invalidate it, it fires here.
        spinRunLoop(for: 1.2)

        XCTAssertTrue(results.isEmpty, "a ready page must never time out")
    }

    func test_a_rejected_bridge_message_produces_a_rejected_result() throws {
        let controller = startController()

        send("rejected", data: ["result": "rejected", "documentToken": "doc-token"], to: controller)

        XCTAssertEqual(results.count, 1)
        guard case .rejected(let info) = try XCTUnwrap(results.first) else {
            return XCTFail("expected .rejected, got \(String(describing: results.first))")
        }
        XCTAssertEqual(info.result, "rejected")
    }

    func test_an_error_bridge_event_reports_sessionFailed_carrying_the_shells_message() throws {
        let controller = startController()

        send("error", data: ["message": "the shell said no"], to: controller)

        XCTAssertEqual(results.count, 1)
        let error = try XCTUnwrap(signosoftError(of: results.first))
        XCTAssertEqual(error.code, .sessionFailed)
        XCTAssertEqual(error.message, "the shell said no")
    }

    func test_a_bridge_message_the_parser_rejects_is_ignored() throws {
        let controller = startController()

        controller.userContentController(
            WKUserContentController(),
            didReceive: StubScriptMessage(name: "signosoft", body: 42)
        )
        controller.userContentController(
            WKUserContentController(),
            didReceive: StubScriptMessage(name: "signosoft", body: ["data": ["x": 1]])
        )

        XCTAssertTrue(results.isEmpty)
    }

    func test_a_message_posted_to_another_handler_name_is_ignored() {
        let controller = startController()

        controller.userContentController(
            WKUserContentController(),
            didReceive: StubScriptMessage(name: "someOtherBridge", body: ["event": "cancelled"])
        )

        XCTAssertTrue(results.isEmpty)
    }

    func test_a_main_frame_response_below_400_reports_nothing() {
        let controller = startController()

        let policy = respond(statusCode: 200, isForMainFrame: true, to: controller)

        XCTAssertEqual(policy, .allow)
        XCTAssertTrue(results.isEmpty)
    }

    func test_a_subframe_response_of_4xx_reports_nothing() {
        let controller = startController()

        let policy = respond(statusCode: 500, isForMainFrame: false, to: controller)

        XCTAssertEqual(policy, .allow)
        XCTAssertTrue(results.isEmpty, "a failed iframe is not a failed ceremony")
    }

    func test_a_failed_provisional_navigation_reports_loadFailed() throws {
        let controller = startController()

        controller.webView(
            WKWebView(),
            didFailProvisionalNavigation: nil,
            withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(try errorCode(of: results.first), .loadFailed)
    }

    func test_a_cancelled_navigation_reports_nothing() {
        let controller = startController()

        controller.webView(
            WKWebView(),
            didFailProvisionalNavigation: nil,
            withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        )

        XCTAssertTrue(results.isEmpty, "a superseded load is not a failure")
    }

    func test_a_dead_web_content_process_reports_loadFailed() throws {
        let controller = startController()

        controller.webViewWebContentProcessDidTerminate(WKWebView())

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(try errorCode(of: results.first), .loadFailed)
    }

    /// `WKUserContentController` retains its message handler, so registering the
    /// controller directly would leak a whole WebView per ceremony.
    func test_a_controller_the_host_lets_go_of_is_deallocated() {
        weak var released: SignosoftSignerViewController?
        autoreleasepool {
            let controller = startController()
            released = controller
            send("cancelled", to: controller)
            self.controller = nil
        }

        XCTAssertNil(released, "the bridge registration must not retain the controller")
    }

    func test_the_signed_pdf_bytes_never_reach_the_diagnostic_tap() throws {
        let controller = startController()
        var seen: [String: Any]?
        controller.onEvent = { _, data in seen = data }

        send("signed", data: ["documentToken": "tok", "pdfBase64": "AAAA"], to: controller)

        XCTAssertNil(seen?["pdfBase64"])
        XCTAssertEqual(seen?["pdfBase64Length"] as? Int, 4)
    }

    // MARK: - Torn down without a result

    /// The wedge this guards against: no result means the host's completion never
    /// runs, the Dart `Future` behind it never completes, and the plugin's
    /// `isPresenting` stays true for the rest of the app's lifetime.
    func test_a_signer_dismissed_without_reporting_a_result_reports_cancelled() throws {
        let controller = startController()
        attach(controller)
        XCTAssertTrue(results.isEmpty, "nothing has ended the ceremony yet")

        detach(controller)

        XCTAssertEqual(results.count, 1, "a torn-down signer must still reach the host")
        XCTAssertTrue(isCancelled(results.first), "expected .cancelled")
    }

    /// The normal path, in the order `SignosoftSigner.present` runs it: report,
    /// then dismiss from inside the completion.
    func test_a_signer_that_already_reported_a_result_does_not_report_again_when_dismissed() throws {
        let controller = startController()
        attach(controller)

        send("signed", data: ["documentToken": "doc-token"], to: controller)
        XCTAssertEqual(results.count, 1)

        detach(controller)

        XCTAssertEqual(results.count, 1, "report-then-dismiss stays exactly one callback")
        guard case .signed(let info) = try XCTUnwrap(results.first) else {
            return XCTFail("the reported result must stand, not be replaced by .cancelled")
        }
        XCTAssertEqual(info.documentToken, "doc-token")
    }

    /// A permission alert or anything else presented over the signer also ends
    /// its appearance, and that ceremony is still live.
    func test_a_signer_that_disappears_without_being_torn_down_reports_nothing() {
        let controller = startController()
        attach(controller)

        cover(controller)

        XCTAssertTrue(results.isEmpty, "being covered is not being torn down")
    }

    // MARK: - Driving the controller

    /// Builds a controller pointed at the hanging socket and runs `viewDidLoad`,
    /// which is what starts the load and the watchdog.
    ///
    /// `loadTimeout: 0` disables the watchdog, so a test that is not about the
    /// watchdog cannot be raced by it.
    @discardableResult
    private func startController(
        loadTimeout: TimeInterval = 0,
        onResult: ((SignosoftSignerResult) -> Void)? = nil
    ) -> SignosoftSignerViewController {
        let controller = SignosoftSignerViewController(
            token: "test-token",
            baseURL: server.baseURL,
            loadTimeout: loadTimeout
        ) { [weak self] result in
            self?.results.append(result)
            onResult?(result)
        }
        controller.loadViewIfNeeded()
        self.controller = controller
        return controller
    }

    /// Puts the signer on screen inside a host container — the shape
    /// `SignosoftSignerSheet` has inside a `.fullScreenCover`, where the caller
    /// owns presentation.
    ///
    /// Modal `present`/`dismiss` is not usable here: this test bundle has no app
    /// host and therefore no window scene, so a presentation never completes.
    /// Containment needs no scene and exercises the same appearance callbacks.
    private func attach(_ controller: UIViewController) {
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        self.host = host

        host.addChild(controller)
        controller.view.frame = host.view.bounds
        host.view.addSubview(controller.view)
        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()
        controller.didMove(toParent: host)
    }

    /// Tears the signer out of its host, the way a route change does. The
    /// appearance transition is driven explicitly because with no window UIKit
    /// will not drive it itself.
    private func detach(_ controller: UIViewController) {
        controller.willMove(toParent: nil)
        controller.beginAppearanceTransition(false, animated: false)
        controller.view.removeFromSuperview()
        controller.endAppearanceTransition()
        controller.removeFromParent()
    }

    /// Ends the signer's appearance without taking it out of its host: what a
    /// system permission alert or any controller presented on top of it does.
    private func cover(_ controller: UIViewController) {
        controller.beginAppearanceTransition(false, animated: false)
        controller.endAppearanceTransition()
    }

    /// Posts a bridge message the way `HostBridgeService` does.
    private func send(
        _ event: String,
        data: [String: Any]? = nil,
        to controller: SignosoftSignerViewController
    ) {
        var body: [String: Any] = ["event": event]
        if let data { body["data"] = data }
        controller.userContentController(
            WKUserContentController(),
            didReceive: StubScriptMessage(name: "signosoft", body: body)
        )
    }

    /// Hands the controller an HTTP response the way WebKit does, and returns
    /// the policy it answered with.
    private func respond(
        statusCode: Int,
        isForMainFrame: Bool,
        to controller: SignosoftSignerViewController
    ) -> WKNavigationResponsePolicy? {
        let response = HTTPURLResponse(
            url: server.baseURL,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        var policy: WKNavigationResponsePolicy?
        controller.webView(
            WKWebView(),
            decidePolicyFor: StubNavigationResponse(response: response, isForMainFrame: isForMainFrame),
            decisionHandler: { policy = $0 }
        )
        return policy
    }

    /// Taps the close button: found the way an assistive technology would, and
    /// fired through whatever `.touchUpInside` action `UIControl` says it is
    /// wired to. Nothing here names a method on the controller.
    ///
    /// `sendActions(for:)` is a no-op in a test bundle with no key window, so
    /// the target-action table is walked directly.
    private func tapClose(on controller: SignosoftSignerViewController) throws {
        let button = try XCTUnwrap(
            controller.view.subviews
                .compactMap { $0 as? UIButton }
                .first { $0.accessibilityLabel == "Close" },
            "no close button in the view hierarchy"
        )

        var fired = 0
        for target in button.allTargets {
            for action in button.actions(forTarget: target, forControlEvent: .touchUpInside) ?? [] {
                _ = (target as AnyObject).perform(Selector(action), with: button)
                fired += 1
            }
        }
        XCTAssertGreaterThan(fired, 0, "the close button has no .touchUpInside action")
    }

    /// Lets timers fire without blocking the thread they fire on.
    private func spinRunLoop(for interval: TimeInterval) {
        let idle = expectation(description: "run loop spins for \(interval)s")
        idle.isInverted = true
        wait(for: [idle], timeout: interval)
    }

    // MARK: - Reading results

    private func isCancelled(_ result: SignosoftSignerResult?) -> Bool {
        if case .cancelled = result { return true }
        return false
    }

    private func signosoftError(of result: SignosoftSignerResult?) -> SignosoftError? {
        guard case .error(let error) = result else { return nil }
        return error as? SignosoftError
    }

    private func errorCode(of result: SignosoftSignerResult?) throws -> SignosoftErrorCode {
        try XCTUnwrap(
            signosoftError(of: result),
            "expected .error(SignosoftError), got \(String(describing: result))"
        ).code
    }
}

// MARK: - Test doubles

/// WebKit never lets anyone build one of these, so the delegate call has to be
/// made with a subclass that answers `name` and `body`. The seam is WebKit's own
/// public delegate API — the same one the real WebView calls.
private final class StubScriptMessage: WKScriptMessage {
    private let stubName: String
    private let stubBody: Any

    init(name: String, body: Any) {
        stubName = name
        stubBody = body
        super.init()
    }

    override var name: String { stubName }
    override var body: Any { stubBody }
}

private final class StubNavigationResponse: WKNavigationResponse {
    /// WebKit's `-dealloc` tears down a C++ member this instance never had, so
    /// these are deliberately never released.
    private static var retained: [WKNavigationResponse] = []

    private let stubResponse: URLResponse
    private let stubIsForMainFrame: Bool

    init(response: URLResponse, isForMainFrame: Bool) {
        stubResponse = response
        stubIsForMainFrame = isForMainFrame
        super.init()
        Self.retained.append(self)
    }

    override var response: URLResponse { stubResponse }
    override var isForMainFrame: Bool { stubIsForMainFrame }
}

/// A loopback TCP socket that listens and never accepts.
///
/// The kernel completes the handshake into the backlog, so a client connects and
/// then waits forever for bytes that never come: WebKit reports neither success
/// nor failure, which is exactly the "page has not become ready yet" state these
/// tests need. `https` is deliberate — the handshake stalls before any HTTP, so
/// App Transport Security never has an opinion and no plaintext leaves the box.
private final class HangingLoopbackServer {
    private var descriptor: Int32 = -1
    private let port: UInt16

    var baseURL: URL { URL(string: "https://127.0.0.1:\(port)/")! }

    init() throws {
        let fileDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else { throw Failure.socket(errno) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0 // any free port
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            let failure = Failure.bind(errno)
            Darwin.close(fileDescriptor)
            throw failure
        }
        guard listen(fileDescriptor, 16) == 0 else {
            let failure = Failure.listen(errno)
            Darwin.close(fileDescriptor)
            throw failure
        }

        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &actual) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fileDescriptor, $0, &length)
            }
        }
        guard named == 0 else {
            let failure = Failure.getsockname(errno)
            Darwin.close(fileDescriptor)
            throw failure
        }

        descriptor = fileDescriptor
        port = UInt16(bigEndian: actual.sin_port)
    }

    func close() {
        guard descriptor >= 0 else { return }
        Darwin.close(descriptor)
        descriptor = -1
    }

    enum Failure: Error {
        case socket(Int32)
        case bind(Int32)
        case listen(Int32)
        case getsockname(Int32)
    }
}
#endif
