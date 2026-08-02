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
        webView?.configuration.userContentController
            .removeScriptMessageHandler(forName: Self.handlerName)
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        setUpWebView()
        setUpOverlay()
        loadSigner()
    }

    private func setUpWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(
            WeakScriptMessageHandler(self),
            name: Self.handlerName
        )

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 16.4, *) {
            // Lets you attach Safari's Web Inspector to the WebView.
            webView.isInspectable = true
        }

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

    private func loadSigner() {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            finish(.error(SignosoftError(
                code: .invalidBaseUrl,
                message: "Invalid base URL: \(baseURL.absoluteString)"
            )))
            return
        }
        // Angular is served from the root; an empty path would produce
        // "host?bioid=..." instead of "host/?bioid=...".
        if components.path.isEmpty {
            components.path = "/"
        }
        components.queryItems = [URLQueryItem(name: "bioid", value: token)]

        guard let url = components.url else {
            finish(.error(SignosoftError(
                code: .invalidBaseUrl,
                message: "Could not build a signer URL from \(baseURL.absoluteString)"
            )))
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
            self.finish(.error(SignosoftError(
                code: .loadTimeout,
                message: "The signing page did not become ready within "
                    + "\(Int(self.loadTimeout))s. Check that baseUrl points at a "
                    + "reachable Signosoft signing shell."
            )))
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
            finish(.signed(SignedInfo(bridgeData: bridgeMessage.data, pdfStore: pdfStore)))
        case "rejected":
            finish(.rejected(SignedInfo(bridgeData: bridgeMessage.data, pdfStore: pdfStore)))
        case "cancelled":
            finish(.cancelled)
        case "error":
            finish(.error(SignosoftError(
                code: .sessionFailed,
                message: bridgeMessage.data?["message"] as? String
                    ?? "The signing session could not be established."
            )))
        default:
            break
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

        finish(.error(SignosoftError(
            code: .loadFailed,
            message: "The signing shell answered HTTP \(response.statusCode) at "
                + "\(response.url?.absoluteString ?? baseURL.absoluteString). "
                + "Check that baseUrl points at the root of a deployed shell."
        )))
    }

    private func reportLoadFailure(_ error: Error) {
        // Superseded or user-cancelled loads are not failures worth reporting.
        if (error as NSError).code == NSURLErrorCancelled { return }
        finish(.error(SignosoftError(
            code: .loadFailed,
            message: "Could not load the signing page. \(error.localizedDescription)"
        )))
    }

    /// The WebView's content process can be killed under memory pressure — most
    /// plausibly by a large document. The page is gone and will not come back
    /// on its own, so report rather than leave a white screen.
    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(.error(SignosoftError(
            code: .loadFailed,
            message: "The signing page stopped unexpectedly, most likely from "
                + "memory pressure. The signature was not recorded."
        )))
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
