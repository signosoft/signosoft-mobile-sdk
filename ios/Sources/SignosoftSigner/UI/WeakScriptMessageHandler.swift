#if canImport(WebKit)
import WebKit

/// Breaks the `WKUserContentController` -> handler -> controller retain cycle.
///
/// `WKUserContentController` retains its handler, so registering the view
/// controller directly leaks it and `deinit` never runs.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
#endif
