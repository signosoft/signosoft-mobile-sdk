import Foundation

/// Writes the signed PDF that the shell ships as base64 into a file the host
/// app can read.
///
/// The bytes cross the JS→native bridge inside a single script message. WebKit
/// itself copes with more than the ceiling below — measured on an iPad Pro 13"
/// simulator, a 50 MB document (69,905,064 base64 characters) was delivered
/// intact in about a second. The ceiling is ours, and it is about peak memory:
/// the base64 string, the decoded `Data` and the write buffer are all resident
/// at once.
///
/// Every failure yields nil rather than throwing: the signature is already
/// recorded server-side by the time this runs, so a missing local copy must
/// never turn a completed signature into an error. The host still gets
/// `signed`, with a null path, and fetches the document by `documentToken`.
struct SignedPdfStore {
    /// Decoded-bytes ceiling. Documents at or below this arrive as a local
    /// file; above it the signature still succeeds and the path is nil.
    static let defaultMaximumBytes = 32 * 1024 * 1024

    private let directory: URL
    private let maximumBytes: Int

    init(
        directory: URL = FileManager.default.temporaryDirectory,
        maximumBytes: Int = defaultMaximumBytes
    ) {
        self.directory = directory
        self.maximumBytes = maximumBytes
    }

    func write(base64: String?, fileName: String?) -> URL? {
        guard let base64, !base64.isEmpty else { return nil }
        // Four base64 characters carry three bytes; check before allocating.
        guard base64.count / 4 * 3 <= maximumBytes else { return nil }
        guard let data = Data(base64Encoded: base64), !data.isEmpty,
              data.count <= maximumBytes
        else { return nil }

        let url = directory.appendingPathComponent(Self.safeName(fileName))
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// The shell supplies the document's own name, so it is never trusted as a
    /// path: only the last component survives, and it may not walk upwards.
    static func safeName(_ fileName: String?) -> String {
        let fallback = "document.pdf"
        guard let last = fileName?.split(separator: "/").last else { return fallback }

        let name = String(last)
        guard !name.isEmpty, name != ".", name != ".." else { return fallback }
        return name
    }
}
