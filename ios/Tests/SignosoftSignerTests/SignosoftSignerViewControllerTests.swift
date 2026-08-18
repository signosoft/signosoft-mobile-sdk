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

        waitForResults(1)
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
        // The signed outcome is built off the main thread, so it has to have
        // landed before the events that must not replace it are sent. A shell
        // that posts a terminal event while that build is still in flight is a
        // real, unhandled ordering hazard — see the report accompanying this
        // change.
        waitForResults(1)
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

        waitForResults(1)
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

    // MARK: - What the shell is allowed to report

    /// Every other field may default — a missing middle name must never lose a
    /// signature. `documentToken` may not: it is the host's only handle on the
    /// document, so a blank one is a completed-looking ceremony the host cannot
    /// do anything with.
    func test_an_empty_documentToken_is_reported_as_a_failure_not_a_signature() throws {
        let controller = startController()

        send("signed", data: ["result": "success", "document": "12345"], to: controller)

        waitForResults(1)
        XCTAssertEqual(try errorCode(of: results.first), .sessionFailed)
        if case .signed = results.first {
            XCTFail("a token-less payload must not be handed to the host as a signature")
        }
    }

    /// WebKit delivers bridge messages on the main thread, and building the
    /// outcome decodes up to 32 MB of base64 and writes it to disk. Doing that
    /// inline froze the UI at the moment the signer expects confirmation.
    ///
    /// What a host can observe: the bridge call returns before the result does.
    func test_a_signed_result_is_delivered_without_blocking_the_main_thread() throws {
        let controller = startController()
        // Large enough that an inline decode and disk write would be felt.
        let payload = Data(repeating: 0x41, count: 4 * 1024 * 1024).base64EncodedString()

        send("signed", data: [
            "documentToken": "doc-token",
            "pdfFileName": "report.pdf",
            "pdfBase64": payload,
        ], to: controller)

        XCTAssertTrue(results.isEmpty, "the decode and the disk write must not run inline")

        waitForResults(1)
        guard case .signed(let info) = try XCTUnwrap(results.first) else {
            return XCTFail("expected .signed, got \(String(describing: results.first))")
        }
        // The work really happened off the main thread, it was not skipped.
        let file = try XCTUnwrap(info.signedPdfFileURL)
        XCTAssertEqual(try Data(contentsOf: file).count, 4 * 1024 * 1024)
        try? FileManager.default.removeItem(at: file)
    }

    /// This controller never dismisses itself, so a host that reports the result
    /// but forgets to flip its `.fullScreenCover` binding would otherwise leave
    /// a live page — possibly holding a camera or microphone stream — running.
    func test_the_page_is_stopped_once_a_result_has_been_reported() throws {
        let controller = startController()
        let webView = try webView(of: controller)
        XCTAssertEqual(webView.url?.host, "127.0.0.1",
                       "the ceremony is on the shell before it ends")

        try tapClose(on: controller)

        // Having no host is the whole invariant: the shell document is gone and
        // cannot still be holding a camera or a microphone. `finish` stops the
        // load and replaces the document with an empty one loaded from a nil
        // base URL, and WebKit settles the active URL for that in the UI
        // process, without waiting on the web content process — so this holds on
        // the first evaluation and the wait is only a safety net.
        //
        // `isLoading` is deliberately NOT part of this condition. Loading the
        // empty document starts a new load, so `isLoading` returns to true and
        // only clears once that load finishes — which needs WebKit's networking
        // and GPU processes, and on a cold CI runner those have taken longer to
        // launch than this whole timeout. That wait is unbounded and it proves
        // nothing about the invariant. Do not add it back.
        waitUntil("the shell page is torn down") {
            webView.url?.host == nil
        }
    }

    // MARK: - Which base URLs open at all

    /// `URL(string: "notaurl")` succeeds — it becomes a scheme-less relative
    /// URL — so this used to open, sit there, and report `loadFailed` seconds
    /// later, blaming the network for a typo.
    func test_a_baseUrl_with_no_host_is_rejected_before_the_webview_loads() throws {
        let controller = startController(baseURL: URL(string: "notaurl")!)

        XCTAssertEqual(results.count, 1, "the answer is immediate, not after a failed load")
        XCTAssertEqual(try errorCode(of: results.first), .invalidBaseUrl)
        XCTAssertNil(try webView(of: controller).url?.host,
                     "nothing was requested, so the bioid never left the app")
    }

    /// The guard against over-rejecting: the ordinary case must still open. The
    /// hanging server is `https://127.0.0.1:<port>/`, which is both.
    func test_an_https_baseUrl_with_a_host_is_accepted() throws {
        let controller = startController()

        XCTAssertTrue(results.isEmpty, "a usable origin must not be rejected")
        let webView = try webView(of: controller)
        waitUntil("the shell is being loaded") { webView.url?.host == "127.0.0.1" }
        XCTAssertEqual(webView.url?.query, "bioid=test-token")
    }

    // MARK: - What the ceremony leaves behind

    /// The default store persists to disk and is shared with every other
    /// WebView in the host app, so a finished ceremony's cookies and
    /// localStorage outlived it and were readable by unrelated in-app code.
    func test_a_ceremonys_cookies_and_storage_do_not_outlive_the_app_session() throws {
        let controller = startController()

        XCTAssertFalse(try webView(of: controller).configuration.websiteDataStore.isPersistent)
    }

    /// iOS writes a screenshot to disk when the app backgrounds. A medical
    /// document and a handwritten signature should not be in it.
    func test_the_ceremony_is_covered_while_the_app_is_not_active() throws {
        let controller = startController()

        NotificationCenter.default.post(
            name: UIApplication.willResignActiveNotification, object: nil
        )

        let cover = try XCTUnwrap(privacyCover(of: controller), "nothing hides the ceremony")
        XCTAssertEqual(cover, controller.view.subviews.last, "the cover must be on top")
        XCTAssertEqual(cover.frame, controller.view.bounds)
        XCTAssertFalse(cover.isHidden)
        XCTAssertNotNil(cover.backgroundColor, "a transparent cover hides nothing")

        NotificationCenter.default.post(
            name: UIApplication.didBecomeActiveNotification, object: nil
        )

        XCTAssertNil(privacyCover(of: controller), "the cover goes away with the snapshot")
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
        waitForResults(1)

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
        baseURL: URL? = nil,
        loadTimeout: TimeInterval = 0,
        onResult: ((SignosoftSignerResult) -> Void)? = nil
    ) -> SignosoftSignerViewController {
        let controller = SignosoftSignerViewController(
            token: "test-token",
            baseURL: baseURL ?? server.baseURL,
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

    /// The WebView the controller is actually driving, found the way anything
    /// outside the SDK would have to find it.
    private func webView(
        of controller: SignosoftSignerViewController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> WKWebView {
        try XCTUnwrap(
            controller.view.subviews.compactMap { $0 as? WKWebView }.first,
            "no WebView in the view hierarchy",
            file: file,
            line: line
        )
    }

    private func privacyCover(of controller: SignosoftSignerViewController) -> UIView? {
        controller.view.subviews.first {
            $0.accessibilityIdentifier == SignosoftSignerViewController.privacyCoverIdentifier
        }
    }

    /// Waits for results that no longer arrive inline: a signed or rejected
    /// outcome is now built off the main thread and reported back on it.
    private func waitForResults(
        _ count: Int,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        waitUntil("\(count) result(s) reach the host", timeout: timeout, file: file, line: line) {
            self.results.count >= count
        }
        XCTAssertEqual(results.count, count, "a session reports exactly once", file: file, line: line)
    }

    /// Spins the run loop until the condition holds, so main-thread work the SDK
    /// scheduled can actually run.
    private func waitUntil(
        _ what: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(condition(), "timed out waiting until \(what)", file: file, line: line)
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
