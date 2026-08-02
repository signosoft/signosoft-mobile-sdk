#if canImport(UIKit)
import UIKit

/// Entry point of the Signosoft Mobile SDK for native iOS hosts.
///
/// Flutter apps should use the `signosoft_signer` plugin instead, which wraps
/// this.
public enum SignosoftSigner {
    /// Present the signing UI modally and dismiss it once the flow finishes.
    /// - Parameters:
    ///   - presenter: view controller to present from
    ///   - token: bioid from `createDocLink`
    ///   - baseURL: origin serving the embedded signing shell
    ///   - loadTimeout: how long the shell may take to report itself ready
    ///   - onEvent: optional tap into every bridge message, for debugging only
    ///   - completion: called exactly once, after the UI is dismissed
    public static func present(
        from presenter: UIViewController,
        token: String,
        baseURL: URL,
        loadTimeout: TimeInterval = SignosoftSignerViewController.defaultLoadTimeout,
        onEvent: ((String, [String: Any]?) -> Void)? = nil,
        completion: @escaping (SignosoftSignerResult) -> Void
    ) {
        let controller = SignosoftSignerViewController(
            token: token,
            baseURL: baseURL,
            loadTimeout: loadTimeout
        ) { result in
            presenter.dismiss(animated: true) { completion(result) }
        }
        controller.onEvent = onEvent
        presenter.present(controller, animated: true)
    }
}
#endif
