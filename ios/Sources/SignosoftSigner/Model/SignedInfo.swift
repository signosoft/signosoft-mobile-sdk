import Foundation

/// Payload delivered with `signed` / `rejected`. Mirrors the query params the
/// web app would otherwise put on its redirect URL.
public struct SignedInfo: Codable, Equatable {
    public let result: String
    public let document: String
    public let documentToken: String
    public let lang: String
    public let signaturesSigned: Int
    public let signaturesTotal: Int
    public let lastSignerFirstName: String
    public let lastSignerLastName: String
    public let lastSignerEmail: String
    /// Remote URL for the signed PDF. Present when the backend provides one —
    /// it does not yet, so this is nil today. See the integration guide.
    public let downloadUrl: URL?
    /// Signed PDF written into the host app's temporary directory. Distinct
    /// from `downloadUrl`: a local file, not a remote link. Nil on `rejected`,
    /// and nil on `signed` when the document could not be fetched or exceeded
    /// the bridge size ceiling.
    public let signedPdfFileURL: URL?

    public init(
        result: String,
        document: String,
        documentToken: String,
        lang: String,
        signaturesSigned: Int,
        signaturesTotal: Int,
        lastSignerFirstName: String,
        lastSignerLastName: String,
        lastSignerEmail: String,
        downloadUrl: URL? = nil,
        signedPdfFileURL: URL? = nil
    ) {
        self.result = result
        self.document = document
        self.documentToken = documentToken
        self.lang = lang
        self.signaturesSigned = signaturesSigned
        self.signaturesTotal = signaturesTotal
        self.lastSignerFirstName = lastSignerFirstName
        self.lastSignerLastName = lastSignerLastName
        self.lastSignerEmail = lastSignerEmail
        self.downloadUrl = downloadUrl
        self.signedPdfFileURL = signedPdfFileURL
    }
}

extension SignedInfo {
    /// Builds the payload from a `signed` / `rejected` bridge message.
    ///
    /// Every field is optional on the wire and defaulted here: a completed
    /// signature must never be lost to a missing or mistyped field.
    init(bridgeData data: [String: Any]?, pdfStore: SignedPdfStore) {
        let data = data ?? [:]
        self.init(
            result: Self.string(data["result"]),
            document: Self.string(data["document"]),
            documentToken: Self.string(data["documentToken"]),
            lang: Self.string(data["lang"]),
            signaturesSigned: Self.int(data["signaturesSigned"]),
            signaturesTotal: Self.int(data["signaturesTotal"]),
            lastSignerFirstName: Self.string(data["lastSignerFirstName"]),
            lastSignerLastName: Self.string(data["lastSignerLastName"]),
            lastSignerEmail: Self.string(data["lastSignerEmail"]),
            downloadUrl: Self.url(data["downloadUrl"]),
            signedPdfFileURL: pdfStore.write(
                base64: data["pdfBase64"] as? String,
                fileName: data["pdfFileName"] as? String
            )
        )
    }

    private static func string(_ value: Any?) -> String { value as? String ?? "" }

    private static func int(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? 0 }

    /// A download URL the host cannot open is worse than none, so anything
    /// empty or scheme-less becomes nil.
    private static func url(_ value: Any?) -> URL? {
        guard let string = value as? String, !string.isEmpty,
              let url = URL(string: string), url.scheme != nil
        else { return nil }
        return url
    }
}
