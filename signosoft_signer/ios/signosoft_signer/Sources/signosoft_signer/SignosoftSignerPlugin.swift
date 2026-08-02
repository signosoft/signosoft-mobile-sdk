import Flutter
import UIKit

// Under Swift Package Manager the core is a separate module. Under CocoaPods
// the podspec compiles it into this same module, so there is nothing to import.
#if canImport(SignosoftSigner)
import SignosoftSigner
#endif

/// Bridges the Dart `SignosoftSigner` API onto `SignosoftSigner.present`.
public final class SignosoftSignerPlugin: NSObject, FlutterPlugin {
    private static let channelName = "com.signosoft.signer"

    private let channel: FlutterMethodChannel
    private var isPresenting = false

    init(channel: FlutterMethodChannel) {
        self.channel = channel
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(
            SignosoftSignerPlugin(channel: channel),
            channel: channel
        )
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "open" else {
            result(FlutterMethodNotImplemented)
            return
        }

        let arguments = call.arguments as? [String: Any] ?? [:]
        guard let token = arguments["token"] as? String, !token.isEmpty else {
            result(Self.error(.invalidToken, "A bioid token is required."))
            return
        }
        guard let baseUrlString = arguments["baseUrl"] as? String,
              let baseURL = URL(string: baseUrlString)
        else {
            result(Self.error(.invalidBaseUrl, "A valid baseUrl is required."))
            return
        }
        guard let presenter = Self.topViewController() else {
            result(Self.error(.noPresenter, "No view controller available to present the signer."))
            return
        }
        guard !isPresenting else {
            result(Self.error(.alreadyOpen, "A signing session is already open."))
            return
        }

        isPresenting = true
        SignosoftSigner.present(
            from: presenter,
            token: token,
            baseURL: baseURL,
            loadTimeout: Self.loadTimeout(arguments["loadTimeoutMs"]),
            onEvent: Self.wantsDiagnostics(arguments) ? { [weak self] event, data in
                self?.channel.invokeMethod(
                    "diagnostic",
                    arguments: ["event": event, "data": data]
                )
            } : nil
        ) { [weak self] outcome in
            self?.isPresenting = false
            switch outcome {
            case .signed(let info):
                result(Self.payload(status: "signed", info: info))
            case .rejected(let info):
                result(Self.payload(status: "rejected", info: info))
            case .cancelled:
                result(["status": "cancelled"])
            case .error(let error):
                let signosoft = error as? SignosoftError
                result(Self.error(
                    signosoft?.code ?? .unknown,
                    signosoft?.message ?? error.localizedDescription
                ))
            }
        }
    }

    private static func payload(status: String, info: SignedInfo) -> [String: Any?] {
        [
            "status": status,
            "result": info.result,
            "document": info.document,
            "documentToken": info.documentToken,
            "lang": info.lang,
            "signaturesSigned": info.signaturesSigned,
            "signaturesTotal": info.signaturesTotal,
            "lastSignerFirstName": info.lastSignerFirstName,
            "lastSignerLastName": info.lastSignerLastName,
            "lastSignerEmail": info.lastSignerEmail,
            "downloadUrl": info.downloadUrl?.absoluteString,
            "signedPdfPath": info.signedPdfFileURL?.path,
        ]
    }

    /// Dart branches on `details["code"]`; the message is only ever shown to a
    /// developer.
    private static func error(_ code: SignosoftErrorCode, _ message: String) -> FlutterError {
        FlutterError(
            code: "signosoft_error",
            message: message,
            details: ["code": code.rawValue]
        )
    }

    private static func loadTimeout(_ value: Any?) -> TimeInterval {
        guard let milliseconds = (value as? NSNumber)?.doubleValue, milliseconds > 0 else {
            return SignosoftSignerViewController.defaultLoadTimeout
        }
        return milliseconds / 1000
    }

    /// Diagnostics cost a channel round trip per bridge event, so they are only
    /// forwarded when Dart asked for them.
    private static func wantsDiagnostics(_ arguments: [String: Any]) -> Bool {
        arguments["diagnostics"] as? Bool ?? false
    }

    /// Works whether or not the host app uses a scene delegate, so there is no
    /// AppDelegate window to reach for.
    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }

        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
