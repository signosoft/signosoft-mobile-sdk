import Foundation

//TODO: Move lookup keys into config files or plist

/// One message from the embedded shell.
///
/// Deliberately free of WebKit so the wire format can be tested off-device;
/// the view controller hands it the raw `WKScriptMessage.body`.
struct BridgeMessage {
    let event: String
    let data: [String: Any]?

    /// iOS delivers a JS object as a dictionary. JSON strings are accepted too,
    /// so the same parser keeps working if the transport changes.
    init?(body: Any) {
        guard let payload = Self.dictionary(from: body),
              let event = payload["event"] as? String
        else { return nil }

        self.event = event
        self.data = payload["data"] as? [String: Any]
    }



    /// The payload with the signed PDF bytes elided, cheap enough to log.
    /// Diagnostics must never carry megabytes of base64 back across the bridge.
    var diagnosticData: [String: Any]? {
        guard var data else { return nil }
        if let base64 = data.removeValue(forKey: "pdfBase64") as? String {
            data["pdfBase64Length"] = base64.count
        }
        return data
    }

    private static func dictionary(from body: Any) -> [String: Any]? {
        if let dictionary = body as? [String: Any] {
            return dictionary
        }
        if let string = body as? String,
           let data = string.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return parsed
        }
        return nil
    }
}
