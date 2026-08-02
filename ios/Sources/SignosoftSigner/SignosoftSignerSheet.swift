#if canImport(UIKit)
import SwiftUI
import UIKit

/// SwiftUI wrapper for use with `.fullScreenCover`.
///
/// The controller never dismisses itself, so the caller stays in control of
/// presentation state — flip your own binding from `onResult`.
public struct SignosoftSignerSheet: UIViewControllerRepresentable {
    private let token: String
    private let baseURL: URL
    private let loadTimeout: TimeInterval
    private let onEvent: ((String, [String: Any]?) -> Void)?
    private let onResult: (SignosoftSignerResult) -> Void

    public init(
        token: String,
        baseURL: URL,
        loadTimeout: TimeInterval = SignosoftSignerViewController.defaultLoadTimeout,
        onEvent: ((String, [String: Any]?) -> Void)? = nil,
        onResult: @escaping (SignosoftSignerResult) -> Void
    ) {
        self.token = token
        self.baseURL = baseURL
        self.loadTimeout = loadTimeout
        self.onEvent = onEvent
        self.onResult = onResult
    }

    public func makeUIViewController(context: Context) -> SignosoftSignerViewController {
        let controller = SignosoftSignerViewController(
            token: token,
            baseURL: baseURL,
            loadTimeout: loadTimeout,
            onResult: onResult
        )
        controller.onEvent = onEvent
        return controller
    }

    public func updateUIViewController(
        _ uiViewController: SignosoftSignerViewController,
        context: Context
    ) {}
}
#endif
