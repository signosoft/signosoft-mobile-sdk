#if canImport(UIKit)
import UIKit
import WebKit

//NOTE: Consider switching from UIKit to SwiftUI 

/// Hosts the embedded Angular shell and translates its bridge messages into
/// `SignosoftSignerResult`.
///
/// Reports but never dismisses itself — the caller owns presentation, which is
/// what makes `SignosoftSignerSheet` usable inside `.fullScreenCover`.
public final class SignosoftSignerViewController: UIViewController {
    /// Must match the name `HostBridgeService` posts to on iOS.
    private static let handlerName = "signosoft" //WARN: Load from configuration

    /// Names the app-switcher cover in the view hierarchy, so a test can see
    /// the same thing the snapshot would.
    static let privacyCoverIdentifier = "signosoft.privacyCover"

    /// How long the shell may take to report itself ready.
    public static let defaultLoadTimeout: TimeInterval = 45

    private let token: String
    private let baseURL: URL
    private let loadTimeout: TimeInterval
    private let pdfStore: SignedPdfStore
    private let onResult: (SignosoftSignerResult) -> Void

    /// Optional tap into every bridge message, for debugging. The signed PDF
    /// bytes are elided.
    public var onEvent: ((String, [String: Any]?) -> Void)?

    private var webView: WKWebView!
    private let spinner = UIActivityIndicatorView(style: .large)
    private var timeoutTimer: Timer?
    private var didFinish = false
    /// Hides the ceremony from the app switcher's snapshot. See `setUpPrivacyCover`.
    private var privacyCover: UIView?

    public init(
        token: String,
        baseURL: URL,
        loadTimeout: TimeInterval = defaultLoadTimeout,
        onResult: @escaping (SignosoftSignerResult) -> Void
    ) {
        self.token = token
        self.baseURL = baseURL
        self.loadTimeout = loadTimeout
        self.pdfStore = SignedPdfStore()
        self.onResult = onResult
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        timeoutTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        webView?.configuration.userContentController
            .removeScriptMessageHandler(forName: Self.handlerName)
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        setUpWebView()
        setUpOverlay()
        setUpPrivacyCover()
        loadSigner()
    }

    /// A signer that goes away without having reported anything would otherwise
    /// leave the host's completion — and the Dart `Future` behind it — pending
    /// forever, which permanently wedges `isPresenting` in the Flutter plugin and
    /// makes every later `open()` answer `alreadyOpen`.
    ///
    /// Keyed on teardown specifically, not on merely disappearing: a system
    /// permission alert or any other controller presented on top of the signer
    /// also triggers `viewDidDisappear`, and that ceremony is still live.
    /// `finish` is idempotent, so the normal report-then-dismiss path is
    /// unaffected — this only fires when nothing else did.
    ///
    /// Reporting `.cancelled` here is knowingly optimistic. If the controller is
    /// torn down after the document was signed server-side but before the bridge
    /// message arrived, the host is told `cancelled` while the documentation
    /// promises `Cancelled` means "server state unchanged". That is a real,
    /// accepted imperfection, not an oversight: a distinct `Interrupted` outcome
    /// would fix it, but adding a case to the public result type breaks every
    /// consumer's `switch` at compile time and is a product decision.
    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || isMovingFromParent else { return }
        finish(.cancelled)
    }

    private func setUpWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        // Cookies and local storage from a ceremony must not outlive it, and
        // must not be readable by any other WebView the host app runs: the
        // default store persists to disk and is shared across the whole app.
        // Every ceremony gets a fresh bioid, so nothing needs to survive.
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(
            WeakScriptMessageHandler(self),
            name: Self.handlerName
        )

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        #if DEBUG
        if #available(iOS 16.4, *) {
            // Lets you attach Safari's Web Inspector to the WebView. Debug
            // builds only: in a release build this would hand anyone with the
            // device and a USB Mac the bioid and the bridge — including the
            // signer, whose identity the ceremony is asserting. The Android
            // side gates the same capability behind FLAG_DEBUGGABLE.
            webView.isInspectable = true
        }
        #endif

        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setUpOverlay() {
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)

        let closeButton = UIButton(type: .system)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .label
        closeButton.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.85)
        closeButton.layer.cornerRadius = 18
        closeButton.accessibilityLabel = "Close"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    /// iOS writes a screenshot of the app to disk when it goes to the
    /// background, and that snapshot shows whatever is on screen: a medical
    /// document and a handwritten signature. The Android side sets FLAG_SECURE
    /// for the same reason.
    private func setUpPrivacyCover() {
        let centre = NotificationCenter.default
        centre.addObserver(
            self,
            selector: #selector(showPrivacyCover),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        centre.addObserver(
            self,
            selector: #selector(hidePrivacyCover),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func showPrivacyCover() {
        guard privacyCover == nil, isViewLoaded else { return }
        let cover = UIView(frame: view.bounds)
        cover.backgroundColor = .systemBackground
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.accessibilityIdentifier = Self.privacyCoverIdentifier
        view.addSubview(cover)
        privacyCover = cover
    }

    @objc private func hidePrivacyCover() {
        privacyCover?.removeFromSuperview()
        privacyCover = nil
    }

    /// Never put a raw URL into a message a host will log or paste into a bug
    /// report. The `bioid` travels in the query string, it is a credential that
    /// signs the document, and `GETTING-STARTED.md` asks integrators to send us
    /// the message when something goes wrong. Scheme, host, port and path are
    /// what actually help a developer.
    private static func withoutQuery(_ url: URL?) -> String? {
        guard let url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString
    }

    /// Belt and braces behind `withoutQuery`, and the reason every failure goes
    /// through here rather than calling `finish` directly: text we did not write
    /// ourselves — `error.localizedDescription`, most of all — can carry the URL
    /// we loaded. Stripping the token on the way out means a message added later
    /// is safe by default instead of safe only if its author remembered.
    private func fail(_ code: SignosoftErrorCode, _ message: String) {
        let safe = token.isEmpty
            ? message
            : message.replacingOccurrences(of: token, with: "<redacted>")
        finish(.error(SignosoftError(code: code, message: safe)))
    }

    private func loadSigner() {
        // Rejected here rather than after a failed network load, so a bad
        // origin reports `invalidBaseUrl` immediately instead of a `loadFailed`
        // that arrives seconds later and blames the network. It is also what
        // stops a cleartext origin from ever carrying the bioid.
        guard SignosoftSigner.isUsableBaseURL(baseURL) else {
            fail(.invalidBaseUrl,
                 "baseUrl must be an https:// origin with a host — got "
                 + "\(Self.withoutQuery(baseURL) ?? "the value you passed"). "
                 + "Plain http:// is accepted only for localhost while developing.")
            return
        }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            fail(.invalidBaseUrl,
                 "Invalid base URL: \(Self.withoutQuery(baseURL) ?? "the value you passed")")
            return
        }
        // Angular is served from the root; an empty path would produce
        // "host?bioid=..." instead of "host/?bioid=...".
        if components.path.isEmpty {
            components.path = "/"
        }
        components.queryItems = [URLQueryItem(name: "bioid", value: token)]

        guard let url = components.url else {
            fail(.invalidBaseUrl,
                 "Could not build a signer URL from "
                 + "\(Self.withoutQuery(baseURL) ?? "the value you passed")")
            return
        }

        startTimeoutTimer()
        webView.load(URLRequest(url: url))
    }

    /// Without this a wrong `baseURL` leaves the patient on a blank screen
    /// forever: the page never loads, so no bridge event ever arrives.
    private func startTimeoutTimer() {
        guard loadTimeout > 0 else { return }
        timeoutTimer = Timer.scheduledTimer(
            withTimeInterval: loadTimeout,
            repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            self.fail(.loadTimeout,
                      "The signing page did not become ready within "
                      + "\(Int(self.loadTimeout))s. Check that baseUrl points at a "
                      + "reachable Signosoft signing shell.")
        }
    }

    @objc private func closeTapped() {
        finish(.cancelled)
    }

    private func finish(_ result: SignosoftSignerResult) {
        guard !didFinish else { return }
        didFinish = true
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        // Tear the page down rather than leave it running. It may hold a camera
        // or a microphone stream, and this controller deliberately never
        // dismisses itself — a host that reports the result but forgets to flip
        // its `.fullScreenCover` binding would otherwise leave a live ceremony
        // running unbounded.
        webView?.stopLoading()
        webView?.loadHTMLString("", baseURL: nil)
        onResult(result)
    }
}

// MARK: - Bridge

extension SignosoftSignerViewController: WKScriptMessageHandler {
    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.handlerName,
              let bridgeMessage = BridgeMessage(body: message.body)
        else { return }

        onEvent?(bridgeMessage.event, bridgeMessage.diagnosticData)

        switch bridgeMessage.event {
        case "ready":
            timeoutTimer?.invalidate()
            timeoutTimer = nil
            spinner.stopAnimating()
            spinner.isHidden = true
        case "signed":
            deliverOutcome(bridgeMessage.data, as: SignosoftSignerResult.signed)
        case "rejected":
            deliverOutcome(bridgeMessage.data, as: SignosoftSignerResult.rejected)
        case "cancelled":
            finish(.cancelled)
        case "error":
            fail(.sessionFailed,
                 bridgeMessage.data?["message"] as? String
                 ?? "The signing session could not be established.")
        default:
            break
        }
    }

    /// Builds the outcome off the main thread and reports it back on it.
    ///
    /// Decoding up to 32 MB of base64 and writing it to disk is the most
    /// expensive thing the SDK does, and it landed on the main thread because
    /// that is where WebKit delivers bridge messages — freezing the UI at the
    /// exact moment the signer is waiting for confirmation.
    private func deliverOutcome(
        _ data: [String: Any]?,
        as makeResult: @escaping (SignedInfo) -> SignosoftSignerResult
    ) {
        guard !didFinish else { return }
        let store = pdfStore
        DispatchQueue.global(qos: .userInitiated).async {
            let info = SignedInfo(bridgeData: data, pdfStore: store)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // Every other field may safely default — losing a signer's
                // middle name must not lose a signature. `documentToken` may
                // not: it is the only handle the host has on the document, and
                // a blank one turns a completed ceremony into a backend call
                // for nothing. Better a loud failure than a hollow success.
                guard !info.documentToken.isEmpty else {
                    self.fail(.sessionFailed,
                              "The signing shell reported an outcome with no "
                              + "documentToken, so the document cannot be identified.")
                    return
                }
                self.finish(makeResult(info))
            }
        }
    }
}

// MARK: - Navigation

extension SignosoftSignerViewController: WKNavigationDelegate {
    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        reportLoadFailure(error)
    }

    public func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        reportLoadFailure(error)
    }

    /// A misconfigured `baseURL` usually answers — with a 404 or a 502 — rather
    /// than refusing the connection. WebKit renders that as a page and reports
    /// no error, so without this the signer sits on the host's error page until
    /// the load timeout expires.
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(.allow)

        guard navigationResponse.isForMainFrame,
              let response = navigationResponse.response as? HTTPURLResponse,
              response.statusCode >= 400
        else { return }

        fail(.loadFailed,
             "The signing shell answered HTTP \(response.statusCode) at "
             + "\(Self.withoutQuery(response.url) ?? Self.withoutQuery(baseURL) ?? "the signing shell"). "
             + "Check that baseUrl points at the root of a deployed shell.")
    }

    private func reportLoadFailure(_ error: Error) {
        // Superseded or user-cancelled loads are not failures worth reporting.
        if (error as NSError).code == NSURLErrorCancelled { return }
        fail(.loadFailed, "Could not load the signing page. \(error.localizedDescription)")
    }

    /// The WebView's content process can be killed under memory pressure — most
    /// plausibly by a large document. The page is gone and will not come back
    /// on its own, so report rather than leave a white screen.
    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        fail(.loadFailed,
             "The signing page stopped unexpectedly, most likely from memory "
             + "pressure. The signature was not recorded.")
    }
}

// MARK: - Camera / microphone prompts

extension SignosoftSignerViewController: WKUIDelegate {
    public func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.prompt)
    }
}
#endif
